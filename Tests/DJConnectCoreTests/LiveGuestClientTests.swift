import Foundation
import Testing
@testable import DJConnectCore
@testable import DJConnectUI

private final class GuestFixtureTransport: DJConnectGuestTransporting, @unchecked Sendable {
    struct Call { let action: DJConnectGuestTransport.Action; let body: Data; let bearer: String? }
    private let lock = NSLock()
    private var calls: [Call] = []
    private var state = "queue_confirmed"
    private var wrongGuest = false
    private var hasArtwork = false
    func setArtwork(_ value: Bool) { lock.withLock { hasArtwork = value } }
    var recorded: [Call] { lock.withLock { calls } }
    func setState(_ value: String) { lock.withLock { state = value } }
    func withdrawGuest() { lock.withLock { wrongGuest = true } }
    func cancel() {}

    func send(_ action: DJConnectGuestTransport.Action, body: Data, bearer: String?) async throws -> Data {
        let snapshot = lock.withLock { calls.append(.init(action: action, body: body, bearer: bearer)); return (state, wrongGuest, hasArtwork) }
        let caps: [String: Any] = ["shared_information": true, "request_song": true,
            "owner_controls": false, "profile_history": false, "music_dna": false]
        let request: [String: Any] = ["request_id": "own-request", "title": "Strong", "state": snapshot.0]
        let value: [String: Any]
        switch action {
        case .redeem:
            value = ["guest_id": "guest-one", "issuer_epoch": String(repeating: "A", count: 43),
                     "guest_token": "djcg_synthetic", "lease_expires_in": 60.0, "capabilities": caps]
        case .renew:
            value = ["guest_id": "guest-one", "lease_expires_in": 60.0, "capabilities": caps]
        case .context:
            var playback: [String: Any] = ["item_id": "current-recording", "state": "playing", "title": "Strong", "artist": "London Grammar"]
            if snapshot.2 { playback["artwork"] = ["reference": String(repeating: "a", count: 64), "item_id": "current-recording", "expires_at": ISO8601DateFormatter().string(from: Date().addingTimeInterval(30))] }
            value = ["guest_id": snapshot.1 ? "other-guest" : "guest-one", "capabilities": caps,
                "playback": playback,
                "moments": [["moment_id": "public-moment", "title": "Public DJ contribution", "summary": "Public text"]]]
        case .ask, .request:
            value = ["success": true, "guest_id": "guest-one", "text": "Je verzoek is ontvangen.", "guest_request": request]
        case .requestStatus: value = ["request": request]
        case .artwork:
            try await Task.sleep(for: .milliseconds(30))
            return Data([1, 2, 3])
        case .leave, .emotion: value = ["success": true]
        }
        return try JSONSerialization.data(withJSONObject: value)
    }
}

@MainActor private func joinedGuest(_ wire: GuestFixtureTransport) async throws -> DJConnectLiveGuestModel {
    let model = DJConnectLiveGuestModel(makeTransport: { _ in wire })
    let link = "djconnect://join#v=1&ha_url=https%3A%2F%2Fha.example.com&issuer_epoch=\(String(repeating: "A", count: 43))&invitation_id=\(String(repeating: "B", count: 32))&invitation_secret=\(String(repeating: "C", count: 43))"
    #expect(model.receive(link))
    #expect(wire.recorded.isEmpty) // Opening a link is not admission.
    await model.join()
    #expect(model.isJoined)
    return model
}

@Test @MainActor func nativeGuestRequiresConfirmationAndUsesOnlyItsOwnCredential() async throws {
    let wire = GuestFixtureTransport(), model = try await joinedGuest(wire)
    defer { model.disconnect() }
    #expect(model.invitation == nil)
    #expect(wire.recorded.first?.action == .redeem && wire.recorded.first?.bearer == nil)
    model.draft = "Speel London Grammar"
    await model.send(language: "nl")
    let call = try #require(wire.recorded.first { $0.action == .ask })
    #expect(call.bearer == "djcg_synthetic")
    let payload = try #require(JSONSerialization.jsonObject(with: call.body) as? [String: Any])
    #expect(payload["guest_id"] as? String == "guest-one")
    #expect(payload["identity"] == nil && payload["profile_id"] == nil && payload["device_token"] == nil)
    #expect(model.messages.count == 2)
}

@Test @MainActor func nativeGuestLeavesWithoutRetainingConversationOrPublicSnapshot() async throws {
    let wire = GuestFixtureTransport(), model = try await joinedGuest(wire)
    model.draft = "Speel London Grammar"; await model.send(language: "nl")
    #expect(!model.messages.isEmpty && !model.moments.isEmpty && model.playback != nil)
    model.disconnect()
    #expect(!model.isJoined && !model.isPresented && !model.isBusy)
    #expect(model.messages.isEmpty && model.moments.isEmpty && model.playback == nil)
    #expect(model.draft.isEmpty && model.choices.isEmpty && model.playingRequestTitle == nil)
}

@Test @MainActor func guestRequestFeedbackRequiresObservedPlaybackAndIsNotRepeated() async throws {
    let wire = GuestFixtureTransport(), model = try await joinedGuest(wire)
    defer { model.disconnect() }
    model.draft = "Speel London Grammar"; await model.send(language: "nl")
    await model.refreshForDisplay()
    #expect(model.playingRequestTitle == nil) // Queued is not playing.
    wire.setState("actually_playing")
    await model.refreshForDisplay()
    #expect(model.playingRequestTitle == "Strong")
    let reads = wire.recorded.filter { $0.action == .requestStatus }.count
    await model.refreshForDisplay()
    #expect(wire.recorded.filter { $0.action == .requestStatus }.count == reads)
}

@Test @MainActor func guestContextFromAnotherParticipantWithdrawsAllLocalData() async throws {
    let wire = GuestFixtureTransport(), model = try await joinedGuest(wire)
    wire.withdrawGuest(); await model.refreshForDisplay()
    #expect(!model.isJoined && model.moments.isEmpty && model.playback == nil && model.messages.isEmpty)
}

@Test @MainActor func guestArtworkUsesOnlyCurrentGuestPurposeAndCannotReturnAfterLeave() async throws {
    let wire = GuestFixtureTransport()
    wire.setArtwork(true)
    let model = try await joinedGuest(wire)
    let art = try #require(model.playback?.artwork)
    #expect(await model.loadArtwork(art) == Data([1, 2, 3]))
    let call = try #require(wire.recorded.last(where: { $0.action == .artwork }))
    let body = try #require(JSONSerialization.jsonObject(with: call.body) as? [String: Any])
    #expect(Set(body.keys) == ["contract_version", "issuer_epoch", "guest_id", "reference"])
    #expect(call.bearer == "djcg_synthetic")
    wire.setArtwork(false); await model.refreshForDisplay()
    #expect(!model.artworkIsCurrent(art))
    #expect(await model.loadArtwork(art) == nil)
    wire.setArtwork(true); await model.refreshForDisplay()
    let fresh = try #require(model.playback?.artwork)
    let pending = Task { await model.loadArtwork(fresh) }
    try await Task.sleep(for: .milliseconds(1))
    model.disconnect()
    #expect(await pending.value == nil)
    #expect(await model.loadArtwork(fresh) == nil)
}
