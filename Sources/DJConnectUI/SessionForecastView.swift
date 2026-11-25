import SwiftUI
import DJConnectCore

extension DJConnectAppModel {
    func forecastImageIsCurrent(_ image: DJConnectSessionForecast.Imagery, projection: DJConnectSessionForecast) -> Bool {
        visibleSessionForecast(at: Date()) == projection && projection.current_anchor != nil && projection.imagery.contains(image) &&
            image.admittedPath(sessionID: projection.session_id, at: Date()) != nil
    }
    func loadForecastImage(_ image: DJConnectSessionForecast.Imagery, projection: DJConnectSessionForecast) async throws -> DJConnectSessionArtworkImage {
        let epoch = sessionHistory.responseEpoch
        guard forecastImageIsCurrent(image, projection: projection) else { throw CancellationError() }
        let result = try await withHomeAssistantClient(allowsOperationReplay: false) {
            try await $0.sessionForecastArtwork(image, sessionID: projection.session_id)
        }
        guard !Task.isCancelled, epoch == sessionHistory.responseEpoch,
              forecastImageIsCurrent(image, projection: projection) else { throw CancellationError() }
        return result
    }
}

/// Authored text is independent of optional imagery. No generated local claims.
struct SessionForecastTextView: View {
    let sections: [DJConnectSessionForecast.Section]
    let language: String
    let showsSourceLinks: Bool

    init(projection: DJConnectSessionForecast, language: String) {
        self.init(sections: projection.sections, language: language)
    }

    init(sections: [DJConnectSessionForecast.Section], language: String, showsSourceLinks: Bool = true) {
        self.sections = sections
        self.language = language
        self.showsSourceLinks = showsSourceLinks
    }

    private func text(_ key: String) -> String { DJConnectLocalization.localized(key: key, language: language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        if let glyph = ["current": "play.fill", "guidance": "clock", "aim": "target"][section.id] {
                            Image(systemName: glyph)
                                .symbolRenderingMode(.monochrome)
                                .font(.title3.weight(.semibold))
                                .accessibilityHidden(true)
                        }
                        Text(section.title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    }
                    .foregroundStyle(.white)
                    Text(text("ui.session.forecast.claim." + section.claim_type))
                        .font(.caption).foregroundStyle(.white.opacity(0.78))
                    sectionText(section)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if showsSourceLinks, section.id != "current", let source = section.source_url.flatMap(URL.init(string:)) {
                        Link(destination: source) {
                            Text(text("ui.session.forecast.source")).underline().foregroundStyle(.white)
                        }.frame(minHeight: 44)
                    }
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .djSessionFrostedSurface().id(section.id)
            }
        }
        .scrollTargetLayout()
        .accessibilityIdentifier("session-forecast-text")
    }

    @ViewBuilder private func sectionText(_ section: DJConnectSessionForecast.Section) -> some View {
        if section.id == "guidance", let guidance = DJConnectForecastQueueGuidance(text: section.text) {
            VStack(alignment: .leading, spacing: 12) {
                Text(guidance.intro)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(guidance.tracks.indices, id: \.self) { index in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").accessibilityHidden(true)
                            Text(guidance.tracks[index])
                        }
                    }
                }
                Text(guidance.note)
            }
        } else {
            Text(section.text).lineSpacing(3)
        }
    }


}

/// Standalone scroll host used by isolated component qualification.
/// The live Session embeds only SessionForecastContent below its shared header.
/// Transient viewport state belongs to the native screen, not a Profile.
/// Recording geometry must not invalidate the full Flow for every scroll pixel.
@MainActor final class SessionForecastViewport {
    private(set) var offset: CGFloat = 0
    func record(_ value: CGFloat) {
        guard value.isFinite else { return }
        offset = max(0, value)
    }
}

struct SessionForecastPanel<Header: View>: View {
    @ObservedObject var model: DJConnectAppModel
    let header: Header
    let viewport: SessionForecastViewport
    @State private var position: ScrollPosition
    @Environment(\.scenePhase) private var scenePhase
    init(model: DJConnectAppModel, viewport: SessionForecastViewport, @ViewBuilder header: () -> Header) {
        self.model = model; self.header = header()
        self.viewport = viewport
        // The panel is removed while Flow is selected. Restore its device-local
        // viewport even when no authored text ID intersects the top edge.
        _position = State(initialValue: ScrollPosition(y: viewport.offset))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                SessionForecastContent(model: model)
            }
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, value in viewport.record(value) }
    }
}

/// Lower content only: playback, artwork and persona stay owned by the Session.
struct SessionForecastContent: View {
    @ObservedObject var model: DJConnectAppModel
    @ObservedObject private var history: DJConnectSessionHistoryModel
    @State private var readProgress = ReadProgress()
    @Environment(\.scenePhase) private var scenePhase
    init(model: DJConnectAppModel) {
        self.model = model; history = model.sessionHistory
    }
    private func text(_ key: String) -> String { DJConnectLocalization.localized(key: key, language: model.language) }
    private var deadlines: [Date] {
        [model.forecastCursor?.projection?.valid_until.flatMap(DJConnectSessionForecast.timestamp),
         model.forecastTrackHandoffDeadline, model.previousForecastDirectionDeadline].compactMap { $0 }
            + (model.forecastCursor?.projection?.imagery.compactMap { DJConnectSessionForecast.timestamp($0.expires_at) } ?? [])
    }
    struct RefreshContext: Equatable {
        let scope: DJConnectAppModel.ForecastScope?
        let ownerEpoch: UUID
        let ownerReady: Bool
        let authority: UUID
        let recovering: Bool
        let unavailable: Bool
        let phase: ScenePhase
        var automaticReadPermitted = true
    }
    var contextKey: RefreshContext {
        .init(scope: model.sessionForecastRefreshScope, ownerEpoch: history.responseEpoch, ownerReady: history.hasAuthorizedOwner,
              authority: model.forecastAuthorityGeneration, recovering: model.djSessionIsRecovering,
              unavailable: model.djSessionLiveUnavailable, phase: scenePhase,
              automaticReadPermitted: model.permitsAutomaticSessionForecastRead)
    }
    // Only the first read for a Session and owner needs a loading placeholder.
    // Later reads can replace the empty state with content when Core supplies it.
    struct ReadProgress {
        var completedContext: RefreshContext?

        func showsLoading(context: RefreshContext, canRead: Bool) -> Bool {
            guard context.phase == .active, context.automaticReadPermitted, canRead else { return false }
            guard let completedContext else { return true }
            return completedContext.ownerEpoch != context.ownerEpoch ||
                completedContext.scope?.sessionID != context.scope?.sessionID
        }
    }
    private var showsLoading: Bool {
        readProgress.showsLoading(context: contextKey, canRead: model.canRefreshSessionForecast)
    }
    private var demoSections: [DJConnectSessionForecast.Section] {
        [
            .init(id: "current", title: text("demo.horizon.current"), claim_type: "current", text: "Midnight City · M83"),
            .init(id: "guidance", title: text("demo.horizon.guidance"), claim_type: "intention", text: text("demo.session.direction")),
            .init(id: "aim", title: text("demo.horizon.aim"), claim_type: "conditional_target", text: text("demo.horizon.direction"))
        ]
    }

    var body: some View {
        TimelineView(SessionEntryRefreshSchedule(deadlines: deadlines)) { clock in
            VStack(alignment: .leading, spacing: 12) {
                let mood = model.isDemoMode ? model.activeDJSession?.selectedMood : model.sessionForecastRefreshScope?.mood
                SessionHorizonHero(theme: .init(sessionMood: mood))
                Text(text("ui.session.forecast.title")).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text(text("ui.session.forecast.notice")).font(.callout).foregroundStyle(.secondary)
                if model.isDemoMode {
                    Text(text("demo.horizon.notice")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    SessionForecastTextView(sections: demoSections, language: model.language)
                } else if scenePhase == .active, let projection = model.visibleSessionForecast(at: clock.date),
                          !projection.sections.isEmpty {
                    ForEach(projection.sections) { section in
                        if section.id == "current" {
                            if let session = model.activeDJSession,
                               let current = SessionHorizonNowMetadata(sessionID: session.id,
                                   playback: session.broadcast.playback, forecast: projection) {
                                SessionHorizonTrackContent(heading: section.title, mood: session.selectedMood,
                                    language: model.language, title: current.title, artist: current.artist, intro: nil,
                                    artworkURL: model.resolvedArtworkURL(current.artworkURL.flatMap { URL(string: $0) }),
                                    sourceURL: current.sourceURL, showsDJAvatar: false)
                                    .accessibilityIdentifier("session-horizon-now")
                            } else {
                                // Keep authored text when current metadata cannot
                                // be joined; never parse it into substitute facts.
                                SessionForecastTextView(sections: [section], language: model.language)
                            }
                            if let session = model.activeDJSession {
                                SessionHorizonMomentCard(model: model, session: session)
                            }
                        } else {
                            SessionForecastTextView(sections: [section], language: model.language)
                        }
                    }
                } else {
                    let handoffPending = scenePhase == .active && model.isForecastTrackHandoffPending(at: clock.date)
                    if showsLoading || handoffPending {
                        Text(text("ui.session.forecast.loading"))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        DJConnectEmptyState(title: text("ui.session.forecast.empty"), systemImage: "sun.horizon")
                            .frame(minHeight: 360)
                            .accessibilityIdentifier("session-forecast-empty")
                    }
                    let previous = handoffPending ? model.previousForecastDirection(at: clock.date) : []
                    if !previous.isEmpty {
                        SessionForecastTextView(sections: previous, language: model.language, showsSourceLinks: false)
                    }
                }
            }.padding(.horizontal, 20).padding(.bottom, 16)
                .scrollTargetLayout()
        }
        .accessibilityIdentifier("session-forecast-panel")
        .onDisappear { model.cancelVisibleSessionForecastRead() }
        .task(id: contextKey) {
            let context = contextKey
            guard context.phase == .active, context.automaticReadPermitted else { return }
            while !Task.isCancelled {
                await model.refreshSessionForecast(automatic: true)
                guard !Task.isCancelled else { return }
                readProgress.completedContext = context
                guard contextKey == context, model.permitsAutomaticSessionForecastRead else { return }
                do { try await Task.sleep(for: .seconds(model.sessionForecastNextReadDelay)) } catch { return }
            }
        }
    }
}

private struct SessionHorizonHero: View {
    let theme: DJConnectSessionMoodTheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private final class ShaderBundleToken {}

    private static let shaders: ShaderLibrary = {
        #if SWIFT_PACKAGE
        ShaderLibrary.bundle(.module)
        #else
        ShaderLibrary.bundle(Bundle(for: ShaderBundleToken.self))
        #endif
    }()

    private var palette: [Color] {
        theme.horizonHeroColorValues.map { value in
            Color(red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255)
        }
    }

    @ViewBuilder private func artwork(size: CGSize, colors: [Color]) -> some View {
        let image = Image("HorizonHero")
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
        if theme == .brand {
            image
        } else {
            ZStack {
                LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                image.blendMode(.luminosity)
            }
            .frame(width: size.width, height: size.height)
            .compositingGroup()
        }
    }

    var body: some View {
        let colors = palette
        GeometryReader { geometry in
            let artwork = artwork(size: geometry.size, colors: colors)
            if !reduceMotion && scenePhase == .active {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { clock in
                    let cycleDuration = 9.0
                    let seconds = clock.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycleDuration)
                    artwork
                        .drawingGroup()
                        .distortionEffect(
                            Self.shaders.horizonWave(.boundingRect, .float(Float(seconds * 2 * .pi / cycleDuration))),
                            maxSampleOffset: CGSize(width: 0, height: 5)
                        )
                }
            } else {
                artwork
            }
        }
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(8)
        .djSessionFrostedSurface(
            cornerRadius: 22,
            surfaceTint: theme == .brand ? Color(red: 0.52, green: 0.26, blue: 0.72) : colors.last
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Keeps the search row in place while revealing the shared glass field.
struct SessionCollapsibleSearch<Content: View>: View {
    let expanded: Bool
    let label: String
    let identifier: String
    let open: () -> Void
    let boundsChanged: (CGRect) -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            if expanded {
                content()
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
            } else {
                Button(action: open) {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
                .transition(.opacity)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: expanded)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { boundsChanged($0) }
    }
}

private struct SessionForecastArtwork: View {
    @ObservedObject var model: DJConnectAppModel
    let projection: DJConnectSessionForecast
    let artwork: DJConnectSessionForecast.Imagery
    @Environment(\.scenePhase) private var scenePhase
    @State private var pixels: DJConnectSessionArtworkImage?
    @State private var loadedKey: String?
    @State private var generation = UUID()
    private var permitted: Bool {
        scenePhase == .active && model.forecastImageIsCurrent(artwork, projection: projection)
    }
    private var requestKey: String {
        [projection.session_id, String(projection.revision), artwork.url,
         String(describing: model.sessionHistory.responseEpoch), String(permitted)].joined(separator: "|")
    }
    var body: some View {
        Group {
            if permitted, loadedKey == requestKey, let pixels, let logo = spotifyAttributionLogo,
               let source = URL(string: artwork.source_url) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(decorative: pixels.image, scale: 1).resizable().scaledToFit()
                        .frame(maxWidth: 480, maxHeight: 360)
                        .accessibilityLabel(artwork.subject.name)
                    Link(destination: source) {
                        HStack {
                            logo.resizable().scaledToFit().frame(width: 80, height: 24)
                            Text(artwork.subject.name)
                        }.frame(minHeight: 44)
                    }.accessibilityLabel("Spotify · " + artwork.subject.name)
                }.padding(16).frame(maxWidth: .infinity, alignment: .center).djSessionFrostedSurface()
            }
        }
        .task(id: requestKey) {
            let key = requestKey
            let request = UUID(); generation = request
            pixels = nil; loadedKey = nil
            guard permitted, spotifyAttributionLogo != nil,
                  let until = DJConnectSessionForecast.timestamp(projection.valid_until),
                  let imageUntil = DJConnectSessionForecast.timestamp(artwork.expires_at) else { return }
            defer { if generation == request { pixels = nil; loadedKey = nil } }
            do {
                let result = try await model.loadForecastImage(artwork, projection: projection)
                guard !Task.isCancelled, permitted, key == requestKey, generation == request else { return }
                pixels = result; loadedKey = key
                try await Task.sleep(for: .seconds(max(0, min(until, imageUntil).timeIntervalSinceNow)))
            } catch { /* Optional art failure never suppresses authored text. */ }
        }
        .onDisappear { generation = UUID(); pixels = nil; loadedKey = nil }
    }
}

/// Scheduling only: the input is the cursor's ORIGINAL remaining lease. This
/// cannot change the cursor or grant a new observation/permission.
enum SessionForecastReadCadence {
    static func delay(originalRemaining: TimeInterval?) -> TimeInterval {
        guard let remaining = originalRemaining, remaining.isFinite else { return 8 }
        return min(8, max(1, remaining - 1))
    }
}

/// Matching DATA only. The caller must first admit the forecast through the
/// existing owner/Session/source/epoch/deadline gate.
struct SessionHorizonNowMetadata {
    let title: String
    let artist: String
    let artworkURL: String?
    let sourceURL: URL
    init?(sessionID: String, playback: DJConnectSessionPlayback?, forecast: DJConnectSessionForecast) {
        guard forecast.session_id == sessionID, let anchor = forecast.current_anchor, let playback,
              playback.state == "playing", playback.itemID == anchor.item_id,
              playback.sourceURL == anchor.source_url,
              let title = playback.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let artist = playback.artist, !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let source = URLComponents(string: anchor.source_url), source.scheme == "https",
              source.host == "open.spotify.com", source.port == nil, source.user == nil, source.password == nil,
              source.query == nil, source.fragment == nil,
              source.path.range(of: #"^/track/[A-Za-z0-9]{22}$"#, options: .regularExpression) != nil,
              let sourceURL = source.url else { return nil }
        self.title = title; self.artist = artist; artworkURL = playback.artworkURL; self.sourceURL = sourceURL
    }
}
