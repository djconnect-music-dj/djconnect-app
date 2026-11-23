import Combine
import Foundation
import DJConnectCore

/// Independent, memory-only guest client. It never receives the paired app model.
@MainActor final class DJConnectLiveGuestModel: ObservableObject {
    struct Message: Identifiable { let id = UUID(); let user: Bool; let text: String }
    struct Moment: Decodable, Identifiable {
        let moment_id: String; let title: String?; let summary: String?
        var id: String { moment_id }
    }
    struct Artwork: Decodable, Equatable, Hashable {
        let reference: String; let item_id: String; let expires_at: String
        func isCurrent(at date: Date) -> Bool {
            reference.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil &&
                !item_id.isEmpty && DJConnectHistoryEntry.date(expires_at).map { $0 > date } == true
        }
    }
    struct Playback: Decodable { let item_id: String?; let title: String?; let artist: String?; let state: String; let artwork: Artwork?; let source_url: String? }
    struct Session: Decodable { let session_id: String; let locale: String; let mood: String; let persona: String; let presence: String }
    struct ViewState: Decodable { let mode: String; let dynamics: Double; let mood: String; let persona: String }
    struct FlowItem: Decodable, Identifiable {
        let moment_id: String; let title: String?; let summary: String?; let content: String?
        let artwork: Artwork?; let playback_item_id: String?; let source_attribution: Attribution?; let created_at: String?
        let flow_expires_at: String?; let display_expires_at: String?; let source_expires_at: String?
        var id: String { moment_id }
        func isCurrent(at now: Date) -> Bool {
            let dates = [flow_expires_at ?? display_expires_at, source_expires_at].compactMap { $0 }.compactMap(DJConnectHistoryEntry.date)
            return dates.min().map { $0 > now } == true
        }
    }
    struct Attribution: Decodable { let provider: String?; let url: String? }
    struct ObservedPlayback: Decodable, Identifiable {
        let entry_id: String; let playback_item_id: String; let title: String; let artist: String?; let album: String?
        let source_url: String; let observed_at: String; let expires_at: String; let artwork: Artwork?
        var id: String { entry_id }
        func isCurrent(at date: Date) -> Bool {
            !entry_id.isEmpty && !playback_item_id.isEmpty &&
                DJConnectHistoryEntry.date(observed_at).map { $0 <= date } == true &&
                DJConnectHistoryEntry.date(expires_at).map { date < $0 } == true && Self.spotifyURL(source_url) != nil
        }
        private static func spotifyURL(_ value: String) -> URL? { DJConnectLiveGuestModel.spotifyURL(value) }
    }
    enum PublicRow: Identifiable {
        case moment(FlowItem), playback(ObservedPlayback)
        var id: String { switch self { case .moment(let item): "moment:" + item.id; case .playback(let item): "playback:" + item.id } }
        var date: Date { switch self {
            case .moment(let item): DJConnectHistoryEntry.date(item.created_at ?? "") ?? .distantPast
            case .playback(let item): DJConnectHistoryEntry.date(item.observed_at) ?? .distantPast
        } }
    }
    nonisolated static func spotifyURL(_ value: String?) -> URL? {
        guard let value, value.range(of: "^https://open\\.spotify\\.com/track/[A-Za-z0-9]{22}$", options: .regularExpression) != nil else { return nil }
        return URL(string: value)
    }
    var publicRows: [PublicRow] {
        (sharedFlow.map(PublicRow.moment) + observedPlayback.map(PublicRow.playback)).sorted { $0.date < $1.date }
    }

    struct Horizon: Decodable {
        struct Section: Decodable { let title: String; let text: String }
        let valid_until: String; let sections: [Section]
        var isCurrent: Bool { DJConnectHistoryEntry.date(valid_until).map { $0 > Date() } == true }
    }
    struct Capabilities: Decodable {
        let shared_information: Bool; let request_song: Bool; let owner_controls: Bool
        let profile_history: Bool; let music_dna: Bool
        var isGuestOnly: Bool { shared_information && !owner_controls && !profile_history && !music_dna }
    }
    private struct Grant: Decodable {
        let guest_id: String; let issuer_epoch: String; let guest_token: String
        let lease_expires_in: Double; let capabilities: Capabilities
    }
    private struct Renewal: Decodable { let guest_id: String; let lease_expires_in: Double; let capabilities: Capabilities }
    private struct Context: Decodable {
        let guest_id: String; let capabilities: Capabilities
        let playback: Playback; let moments: [Moment]
        let session: Session?; let shared_flow: [FlowItem]?; let observed_playback: [ObservedPlayback]?; let horizon: Horizon?; let view: ViewState?
    }
    private struct RequestState: Decodable { let request_id: String; let state: String; let title: String }
    struct Choice: Decodable, Identifiable { let action_id: String; let title: String; let artist: String?; var id: String { action_id } }
    private struct ChoiceSet: Decodable { let result_set_id: String; let items: [Choice] }
    private struct Answer: Decodable {
        let success: Bool; let guest_id: String; let text: String
        let guest_request: RequestState?; let request_choices: ChoiceSet?
    }
    private struct Status: Decodable { let request: RequestState }

    @Published private(set) var isPresented = false
    @Published private(set) var isJoined = false
    @Published private(set) var isBusy = false
    @Published private(set) var invitation: DJConnectGuestInvitation?
    @Published private(set) var messages: [Message] = []
    @Published private(set) var moments: [Moment] = []
    @Published private(set) var playback: Playback?
    @Published private(set) var session: Session?
    @Published private(set) var sharedFlow: [FlowItem] = []
    @Published private(set) var observedPlayback: [ObservedPlayback] = []
    @Published private(set) var horizon: Horizon?
    @Published private(set) var viewState: ViewState?
    @Published private(set) var choices: [Choice] = []
    @Published private(set) var statusKey: String?
    @Published private(set) var playingRequestTitle: String?
    @Published private(set) var requestSongsAllowed = false
    @Published var draft = ""
    private var grant: Grant?
    private var transport: (any DJConnectGuestTransporting)?
    private let makeTransport: (DJConnectGuestInvitation) -> any DJConnectGuestTransporting
    private var leaseDeadline: ContinuousClock.Instant?
    private var loop: Task<Void, Never>?
    private var leaseTask: Task<Void, Never>?
    private var generation = UUID(), thread = UUID().uuidString
    private var renewSequence = 0
    private var pendingRequests: Set<String> = [], notifiedRequests: Set<String> = []
    private var choiceSetID: String?
    struct ArtworkClock {
        private struct Receipt { let artwork: Artwork; let deadline: ContinuousClock.Instant }
        private var receipts: [String: Receipt] = [:]
        mutating func observe(_ artwork: [Artwork], wall: Date, tick: ContinuousClock.Instant) {
            for art in artwork where receipts[art.reference] == nil && receipts.count < 128 {
                guard art.isCurrent(at: wall), let expiry = DJConnectHistoryEntry.date(art.expires_at) else { continue }
                receipts[art.reference] = Receipt(artwork: art,
                    deadline: tick.advanced(by: .seconds(min(28800, expiry.timeIntervalSince(wall)))))
            }
        }
        func accepts(_ art: Artwork, wall: Date, tick: ContinuousClock.Instant) -> Bool {
            guard let receipt = receipts[art.reference] else { return false }
            return receipt.artwork == art && art.isCurrent(at: wall) && tick < receipt.deadline
        }
    }
    private var artworkClock = ArtworkClock()
    private var artworkCache: [Artwork: Data] = [:]
    private func admitsArtwork(_ art: Artwork) -> Bool {
        guard current, artworkClock.accepts(art, wall: Date(), tick: .now) else { return false }
        return (playback?.artwork == art && playback?.item_id == art.item_id) ||
            sharedFlow.contains { $0.artwork == art && $0.playback_item_id == art.item_id && $0.isCurrent(at: Date()) } ||
            observedPlayback.contains { $0.artwork == art && $0.playback_item_id == art.item_id && $0.isCurrent(at: Date()) }
    }
    func loadArtwork(_ art: Artwork) async -> Data? {
        guard admitsArtwork(art), let grant, let transport else { return nil }
        if let data = artworkCache[art] { return data }
        let original = generation
        do {
            let bytes = try await transport.send(.artwork, body: body(["reference": art.reference]), bearer: grant.guest_token)
            guard generation == original, admitsArtwork(art), !bytes.isEmpty, bytes.count <= 256000 else { return nil }
            if artworkCache.count >= 16 { artworkCache.removeAll() }
            artworkCache[art] = bytes
            return bytes
        } catch { return nil } // An unavailable image cannot manufacture a replacement source.
    }
    func artworkIsCurrent(_ art: Artwork) -> Bool { admitsArtwork(art) }


    init(makeTransport: @escaping (DJConnectGuestInvitation) -> any DJConnectGuestTransporting = { DJConnectGuestTransport(invitation: $0) }) {
        self.makeTransport = makeTransport
    }

    var canSend: Bool { isJoined && !isBusy && current && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var current: Bool { grant != nil && leaseDeadline.map { .now < $0 } == true }

    func showJoin() { disconnect(); isPresented = true }

    @discardableResult func receive(_ raw: String) -> Bool {
        guard let url = URLComponents(string: raw), url.scheme == "djconnect", url.host == "join" else { return false }
        disconnect(); isPresented = true
        do { invitation = try DJConnectGuestInvitation.parse(raw); statusKey = nil }
        catch { statusKey = "ui.live.invalid_invitation" }
        return true
    }

    func join() async {
        guard !isBusy, let invitation else { return }
        let original = generation, tick = ContinuousClock.now
        let client = makeTransport(invitation)
        transport = client; self.invitation = nil // One explicit redemption attempt.
        isBusy = true
        defer { if generation == original { isBusy = false } }
        do {
            let data = try await client.send(.redeem, body: invitation.redemptionBody(), bearer: nil)
            let received = try JSONDecoder().decode(Grant.self, from: data)
            guard generation == original, received.issuer_epoch == invitation.issuerEpoch,
                  !received.guest_id.isEmpty, received.guest_id.utf8.count <= 128,
                  received.guest_token.hasPrefix("djcg_"), received.capabilities.isGuestOnly,
                  received.lease_expires_in.isFinite, received.lease_expires_in > 0, received.lease_expires_in <= 60,
                  tick.advanced(by: .seconds(received.lease_expires_in)) > .now else { throw DJConnectGuestTransport.Failure.invalidResponse }
            grant = received; leaseDeadline = tick.advanced(by: .seconds(received.lease_expires_in))
            scheduleLeaseExpiry()
            requestSongsAllowed = received.capabilities.request_song
            isJoined = true; statusKey = nil
            await refresh(original)
            guard generation == original, current else { return }
            loop = Task { [weak self] in await self?.poll(original) }
        } catch {
            guard generation == original else { return }
            disconnect(); isPresented = true; statusKey = "ui.live.invalid_invitation"
        }
    }

    private func body(_ extra: [String: Any] = [:]) throws -> Data {
        guard current, let grant else { throw DJConnectGuestTransport.Failure.withdrawn }
        return try JSONSerialization.data(withJSONObject: extra.merging([
            "contract_version": 1, "guest_id": grant.guest_id, "issuer_epoch": grant.issuer_epoch
        ]) { _, binding in binding })
    }

    private func poll(_ original: UUID) async {
        var lastRenewal = ContinuousClock.now
        while generation == original && current && !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard generation == original, current, !Task.isCancelled else { break }
            if ContinuousClock.now - lastRenewal >= .seconds(20) {
                guard await renew(original) else { return }
                lastRenewal = .now
            }
            await refresh(original)
        }
        if generation == original { disconnect() }
    }

    private func renew(_ original: UUID) async -> Bool {
        guard let grant, let transport else { return false }
        let tick = ContinuousClock.now, sequence = renewSequence + 1
        do {
            let data = try await transport.send(.renew, body: body(["renew_sequence": sequence]), bearer: grant.guest_token)
            let value = try JSONDecoder().decode(Renewal.self, from: data)
            guard generation == original, current, value.guest_id == grant.guest_id, value.capabilities.isGuestOnly,
                  value.lease_expires_in.isFinite, value.lease_expires_in > 0, value.lease_expires_in <= 60,
                  tick.advanced(by: .seconds(value.lease_expires_in)) > .now else { throw DJConnectGuestTransport.Failure.withdrawn }
            renewSequence = sequence; leaseDeadline = tick.advanced(by: .seconds(value.lease_expires_in))
            scheduleLeaseExpiry(); return true
        } catch { if generation == original { disconnect() }; return false }
    }

    private func refresh(_ original: UUID) async {
        guard let transport, let grant else { return }
        do {
            let data = try await transport.send(.context, body: body(), bearer: grant.guest_token)
            let value = try JSONDecoder().decode(Context.self, from: data)
            guard generation == original, current, value.guest_id == grant.guest_id, value.capabilities.isGuestOnly,
                  value.moments.count <= 100 else { throw DJConnectGuestTransport.Failure.invalidResponse }
            playback = value.playback; moments = value.moments
            session = value.session
            sharedFlow = Array((value.shared_flow ?? []).prefix(64))
            observedPlayback = Array((value.observed_playback ?? []).prefix(12))
            horizon = value.horizon.flatMap { $0.isCurrent && $0.sections.count <= 3 ? $0 : nil }
            viewState = value.view.flatMap { ["flow", "vibescape"].contains($0.mode) && $0.dynamics.isFinite && (0...1).contains($0.dynamics) ? $0 : nil }
            artworkClock.observe(([playback?.artwork].compactMap { $0 }) + sharedFlow.compactMap(\.artwork) + observedPlayback.compactMap(\.artwork), wall: Date(), tick: .now)
            artworkCache = artworkCache.filter { admitsArtwork($0.key) }
            requestSongsAllowed = value.capabilities.request_song
            for identifier in pendingRequests {
                let bytes = try await transport.send(.requestStatus, body: body(["request_id": identifier]), bearer: grant.guest_token)
                let status = try JSONDecoder().decode(Status.self, from: bytes)
                guard generation == original, current, status.request.request_id == identifier else { return }
                if status.request.state == "actually_playing", notifiedRequests.insert(identifier).inserted {
                    playingRequestTitle = status.request.title
                }
                if ["actually_playing", "rejected", "expired"].contains(status.request.state) { pendingRequests.remove(identifier) }
            }
        } catch { if generation == original { disconnect() } }
    }

    func refreshForDisplay() async { await refresh(generation) }

    private func scheduleLeaseExpiry() {
        leaseTask?.cancel()
        guard let deadline = leaseDeadline else { return }
        let original = generation
        leaseTask = Task { [weak self] in
            do { try await ContinuousClock().sleep(until: deadline) } catch { return }
            guard let self, self.generation == original, self.leaseDeadline == deadline else { return }
            self.disconnect()
        }
    }

    private static let emotions = ["❤️": "heart", "🔥": "fire", "👏": "applause", "😍": "love", "💃": "dance"]

    func react(_ emoji: String) async {
        guard current, !isBusy, let transport, let grant,
              let item = playback?.item_id, let emotion = Self.emotions[emoji] else { return }
        let original = generation; isBusy = true
        defer { if generation == original { isBusy = false } }
        do {
            _ = try await transport.send(.emotion, body: body(["client_message_id": UUID().uuidString,
                "playback_item_id": item, "emotion": emotion]), bearer: grant.guest_token)
        } catch {
            guard generation == original else { return }
            if error is URLError { disconnect() }
            else if case DJConnectGuestTransport.Failure.withdrawn = error { disconnect() }
            else { statusKey = "ui.live.request_failed" }
        }
    }

    func send(language: String, choice: Choice? = nil) async {
        guard current, !isBusy, let transport, let grant else { return }
        if choice == nil {
            let emoji = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.emotions[emoji] != nil { draft = ""; await react(emoji); return }
        }
        let text = choice.map { $0.title + ($0.artist.map { " — " + $0 } ?? "") } ?? draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 1600 else { return }
        var extra: [String: Any] = ["text": text, "client_message_id": UUID().uuidString, "thread_id": thread, "language": language]
        if let choice, let choiceSetID, choices.contains(where: { $0.id == choice.id }) {
            extra["choice_action"] = ["result_set_id": choiceSetID, "action_id": choice.id]
        } else if choice != nil { return }
        let original = generation; isBusy = true
        messages.append(.init(user: true, text: text)); messages = Array(messages.suffix(24))
        draft = ""; choices = []; self.choiceSetID = nil
        defer { if generation == original { isBusy = false } }
        do {
            let data = try await transport.send(choice == nil ? .ask : .request, body: body(extra), bearer: grant.guest_token)
            let answer = try JSONDecoder().decode(Answer.self, from: data)
            guard generation == original, current, answer.guest_id == grant.guest_id, answer.success,
                  answer.text.utf8.count <= 16000 else { throw DJConnectGuestTransport.Failure.invalidResponse }
            messages.append(.init(user: false, text: answer.text)); messages = Array(messages.suffix(24))
            if let request = answer.guest_request, pendingRequests.count < 128 { pendingRequests.insert(request.request_id) }
            choices = Array((answer.request_choices?.items ?? []).prefix(5)); self.choiceSetID = answer.request_choices?.result_set_id
        } catch {
            guard generation == original else { return }
            if error is URLError { disconnect() }
            else if case DJConnectGuestTransport.Failure.withdrawn = error { disconnect() }
            else { statusKey = "ui.live.request_failed" }
        }
    }

    func disconnect() {
        let previousTransport = transport, previousGrant = grant
        let leaveBody = try? body()
        artworkCache.removeAll(); artworkClock = ArtworkClock()
        generation = UUID(); loop?.cancel(); loop = nil
        leaseTask?.cancel(); leaseTask = nil
        grant = nil; transport = nil; invitation = nil; leaseDeadline = nil
        messages = []; moments = []; playback = nil; choices = []; choiceSetID = nil
        session = nil; sharedFlow = []; observedPlayback = []; horizon = nil; viewState = nil
        pendingRequests = []; notifiedRequests = []; playingRequestTitle = nil
        draft = ""; renewSequence = 0; thread = UUID().uuidString
        isJoined = false; isBusy = false; isPresented = false; statusKey = nil
        requestSongsAllowed = false
        if let previousTransport, let previousGrant, let leaveBody {
            Task { _ = try? await previousTransport.send(.leave, body: leaveBody, bearer: previousGrant.guest_token); previousTransport.cancel() }
        } else { previousTransport?.cancel() }
    }
}
