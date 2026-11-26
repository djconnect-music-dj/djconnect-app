import SwiftUI
import DJConnectCore
import ImageIO

private let vibeCastPartyTitle = "VibeCast Party"

struct VibeCastPartyMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            DJPersonaMark(includesWaveform: false)
                .fill(.white)
            Image(systemName: "party.popper.fill")
                .font(.system(size: size * 23 / 86, weight: .semibold))
                .foregroundStyle(.white)
                .offset(y: size * 2 / 86)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct VibeCastPartyHero: View {
    private let size: CGFloat = 86

    var body: some View {
        DJConnectHeroShine(artwork: djConnectIconGradient
            .frame(width: size, height: size)
            .mask(VibeCastPartyMark(size: size)))
    }
}

struct VibeCastPartyJoinLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            VibeCastPartyMark(size: 28)
            Text(title)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DJConnectLiveGuestJoinView: View {
    @ObservedObject var guest: DJConnectLiveGuestModel
    let language: String
    #if os(macOS)
    @State private var address = ""
    @State private var manualCode = ""
    #endif
    #if os(iOS)
    @State private var scanning = false
    #endif

    private func text(_ key: String) -> String {
        DJConnectLocalization.localized(key: key, language: language)
    }

    var body: some View {
        DJConnectGlassDialogSurface(title: vibeCastPartyTitle, icon: VibeCastPartyHero()) {
            VStack(spacing: 14) {
                if guest.invitation != nil {
                    Button {
                        Task { await guest.join() }
                    } label: {
                        VibeCastPartyJoinLabel(title: text("ui.live.join"))
                    }
                        .djConnectButtonStyle(DJConnectButtonStyle(emphasis: .primary, expands: true))
                        .disabled(guest.isBusy)
                        .accessibilityIdentifier("live-guest-confirm")
                } else if guest.isBusy {
                    ProgressView()
                } else {
                    #if os(iOS)
                    Button { scanning = true } label: {
                        Label(text("ui.scan.qr.code"), systemImage: "qrcode.viewfinder")
                    }
                    .djConnectButtonStyle(DJConnectButtonStyle(emphasis: .primary, expands: true))
                    .accessibilityIdentifier("live-guest-scan")
                    #elseif os(macOS)
                    TextField(text("ui.live.tv_address"), text: $address)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)
                        .accessibilityIdentifier("live-guest-tv-address")
                    TextField(text("ui.live.tv_code"), text: $manualCode)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("live-guest-tv-code")
                        .onSubmit(openCode)
                    Button(text("ui.continue"), action: openCode)
                        .djConnectButtonStyle(DJConnectButtonStyle(emphasis: .primary, expands: true))
                        .disabled(address.isEmpty || manualCode.isEmpty)
                    #endif
                }
                if let key = guest.statusKey { Text(text(key)).foregroundStyle(.secondary) }
                DJConnectNotNowLinkButton(language: language, key: "ui.not.now.b1e535") {
                    guest.disconnect()
                }
                .accessibilityIdentifier("live-guest-leave")
            }
        }
        .accessibilityIdentifier("live-guest-join")
        #if os(iOS)
        .fullScreenCover(isPresented: $scanning) {
            PairingQRScannerView(language: language, instructionsKey: "ui.live.join_instructions",
                                 confirmsDetection: false) { value in
                scanning = false
                guest.receiveScan(value)
            }
        }
        #endif
    }

    #if os(macOS)
    private func openCode() {
        guard !address.isEmpty, !manualCode.isEmpty else { return }
        guest.receiveCode(manualCode, address: address)
        if guest.invitation != nil { manualCode = "" }
    }
    #endif
}

/// Guest navigation has no paired model, owner controls or personal data sources.
struct DJConnectLiveGuestView: View {
    @ObservedObject var guest: DJConnectLiveGuestModel
    let language: String
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var showsHelp = false
    @State private var confirmsLeaving = false
    @State private var mode: Mode = .flow
    @State private var artworkSample: (artwork: DJConnectLiveGuestModel.Artwork, color: Color)?

    private enum Mode { case flow, horizon, vibeScape, requested }

    private let spacing: CGFloat = 12
    private let gutter: CGFloat = 20
    private var locale: Locale { Locale(identifier: DJConnectLocalization.supportedLanguageCode(language)) }

    private func text(_ key: String) -> String { DJConnectLocalization.localized(key: key, language: language) }

    var body: some View {
        Group {
            if mode == .vibeScape {
                DJConnectGuestVibescape(guest: guest, language: language) { toggleControls in
                    VStack(spacing: spacing) {
                        header
                        modeSelector(onVibeScape: toggleControls)
                    }
                    .padding(.top, 8)
                }
                .accessibilityIdentifier("live-guest-vibescape")
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { clock in
                    let tint = currentArtworkTint
                    VStack(spacing: spacing) {
                        header
                        modeSelector { mode = .vibeScape }
                        if mode == .horizon {
                            horizon(tint: tint)
                        } else if mode == .requested {
                            requestedTracks
                        } else {
                            flow(at: clock.date, tint: tint)
                        }
                    }
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background { background(tint: tint) }
                }
            }
        }
        #if os(macOS)
        .toolbar(mode == .vibeScape ? .hidden : .automatic, for: .windowToolbar)
        .windowToolbarFullScreenVisibility(mode == .vibeScape ? .onHover : .visible)
        #endif
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .djConnectPopup(isPresented: $confirmsLeaving) {
            leaveConfirmation
        }
        .accessibilityIdentifier("live-guest-root")
    }

    private var currentArtworkTint: Color? {
        guard let artworkSample, guest.playback?.artwork == artworkSample.artwork,
              guest.artworkIsCurrent(artworkSample.artwork) else { return nil }
        return artworkSample.color
    }

    private func background(tint: Color?) -> some View {
        let base = Color(red: 0.08, green: 0.12, blue: 0.18)
        return ZStack {
            base
            LinearGradient(
                colors: [.black.opacity(0.30), (tint ?? Color(red: 0.27, green: 0.39, blue: 0.56)).opacity(0.44),
                         (tint ?? .blue).opacity(0.19), .black.opacity(0.40)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: 8) {
            VibeCastPartyMark(size: 36)
            Text(vibeCastPartyTitle)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if guest.requestedTracks != nil {
                Menu {
                    Button { mode = .requested } label: {
                        Label(text("ui.live.requested"), systemImage: "music.note.list")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(text("ui.live.requested"))
                .accessibilityIdentifier("live-guest-requested-menu")
            }
            Button { confirmsLeaving = true } label: {
                Image(systemName: "stop.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .djSessionFrostedSurface(cornerRadius: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text("ui.live.leave"))
            .accessibilityIdentifier("live-guest-leave")
        }
        .padding(.horizontal, gutter)
    }

    private var leaveConfirmation: some View {
        DJConnectGlassDialogSurface(
            title: text("ui.live.leave_confirmation"),
            icon: VibeCastPartyHero()
        ) {
            VStack(spacing: 12) {
                Button(text("ui.live.leave")) {
                    confirmsLeaving = false
                    guest.disconnect()
                }
                .djConnectButtonStyle(DJConnectButtonStyle(emphasis: .destructive, expands: true, usesDestructiveGlass: true))
                .accessibilityIdentifier("live-guest-confirm-leave")

                Button(text("ui.cancel"), role: .cancel) { confirmsLeaving = false }
                    .djConnectButtonStyle(DJConnectButtonStyle(expands: true))
                    .accessibilityIdentifier("live-guest-cancel-leave")
                    .keyboardShortcut(.cancelAction)
            }
        }
        .accessibilityIdentifier("live-guest-leave-confirmation")
    }

    private func modeSelector(onVibeScape: @escaping () -> Void) -> some View {
        SessionModeToggleButtons(
            showsForecast: Binding(get: { mode == .horizon }, set: { mode = $0 ? .horizon : .flow }),
            language: language, openVibeScape: onVibeScape, isVibeScape: mode == .vibeScape,
            showsAnotherPage: mode == .requested
        )
        .padding(.horizontal, gutter)
    }

    private var requestedTracks: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: spacing) {
                Text(text("ui.live.requested"))
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                if let tracks = guest.requestedTracks, !tracks.isEmpty {
                    ForEach(tracks) { track in
                        QueueTrackRow(
                            title: track.title,
                            subtitle: track.artist.isEmpty ? nil : track.artist
                        ) {
                            if let artwork = track.artwork {
                                DJConnectGuestArtwork(guest: guest, artwork: artwork, queueCover: true)
                            } else {
                                QueueArtworkView(url: nil)
                            }
                        } accessory: {
                            EmptyView()
                        }
                    }
                } else {
                    Text(text("ui.live.requested_empty")).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 1000)
            .padding(.horizontal, gutter)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("live-guest-requested")
    }

    private func clock(_ date: Date) -> some View {
        VStack(spacing: 1) {
            Text(date, format: .dateTime.hour().minute().locale(locale))
                .font(.system(.largeTitle, design: .default, weight: .heavy).monospacedDigit())
            Text(date, format: .dateTime.weekday(.wide).day().month(.wide).locale(locale))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.70))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func flow(at date: Date, tint: Color?) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: spacing) {
                clock(date)
                if let playback = guest.playback, let title = playback.title, !title.isEmpty {
                    currentTrack(playback, title: title, tint: tint)
                }
                if let title = guest.playingRequestTitle {
                    Label(String(format: text("ui.live.request_playing"), title), systemImage: "music.note")
                        .accessibilityIdentifier("live-guest-request-playing")
                }
                ForEach(guest.publicRows.reversed()) { row in
                    publicRow(row, at: date, tint: tint)
                }
                if guest.sharedFlow.isEmpty {
                    ForEach(guest.moments.reversed()) { moment in
                        contribution(title: moment.title, body: moment.summary ?? "", at: nil,
                                     artwork: nil, source: nil, tint: tint)
                    }
                }
                ForEach(guest.messages) { message in
                    HStack {
                        if message.user { Spacer(minLength: 24) }
                        Text(message.text).padding(12)
                            .djSessionFrostedSurface(cornerRadius: 18, surfaceTint: tint?.opacity(0.50))
                        if !message.user { Spacer(minLength: 24) }
                    }
                }
                ForEach(guest.choices) { choice in
                    Button(choice.title + (choice.artist.map { " — " + $0 } ?? "")) {
                        Task { await guest.send(language: language, choice: choice) }
                    }
                    .djConnectButtonStyle(DJConnectButtonStyle(expands: true))
                    .disabled(guest.isBusy)
                }
                if let key = guest.statusKey { Text(text(key)).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, gutter)
            .padding(.bottom, spacing)
            .frame(maxWidth: .infinity)
        }
        .environment(\.djConnectScrollingSurface, true)
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .accessibilityIdentifier("live-guest-flow")
    }

    private func currentTrack(_ playback: DJConnectLiveGuestModel.Playback, title: String, tint: Color?) -> some View {
        let layout = dynamicType.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
        return layout {
            Group {
                if let art = playback.artwork, art.item_id == playback.item_id,
                   DJConnectLiveGuestModel.spotifyURL(playback.source_url) != nil {
                    DJConnectGuestArtwork(guest: guest, artwork: art, currentPlayback: true,
                                          isPlaying: playback.state == "playing") { color in
                        artworkSample = (art, color)
                    }
                } else {
                    AlbumArtworkPlaceholder(tint: tint ?? .gray, isPlaying: playback.state == "playing")
                        .djAlbumArtworkGlassCard(tint: tint)
                }
            }
            .frame(width: 112, height: 112)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 4) {
                    Text(title).font(.title3.bold()).frame(maxWidth: .infinity, alignment: .leading)
                    if playback.item_id != nil { emotionMenu }
                }
                if let artist = playback.artist, !artist.isEmpty {
                    Text(artist).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                }
                if let album = playback.album, !album.isEmpty {
                    Text(album).font(.footnote).foregroundStyle(.white.opacity(0.73))
                }
                if let progress = playback.progress {
                    VStack(alignment: .trailing, spacing: 2) {
                        ProgressView(value: Double(progress.position), total: Double(progress.duration))
                            .tint(.white)
                        Text("\(elapsed(progress.position)) / \(elapsed(progress.duration))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(.top, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("live-guest-playback-progress")
                }
                if let source = DJConnectLiveGuestModel.spotifyURL(playback.source_url) {
                    spotifyLink(source)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("live-guest-current-track")
    }

    private var emotionMenu: some View {
        Menu {
            ForEach(["❤️", "🔥", "👏", "😍", "💃"], id: \.self) { emoji in
                Button(emoji) { Task { await guest.react(emoji) } }
            }
        } label: {
            Image(systemName: "heart").frame(minWidth: 40, minHeight: 36)
        }
        .buttonStyle(.plain)
        .disabled(guest.isBusy)
        .accessibilityLabel(text("ui.live.react"))
        .accessibilityIdentifier("live-guest-emotion-menu")
    }

    @ViewBuilder private func publicRow(_ row: DJConnectLiveGuestModel.PublicRow, at date: Date, tint: Color?) -> some View {
        switch row {
        case .moment(let item):
            if item.isCurrent(at: date) {
                let source = item.source_attribution?.provider?.lowercased() == "spotify"
                    ? DJConnectLiveGuestModel.spotifyURL(item.source_attribution?.url) : nil
                contribution(title: item.title, body: item.content ?? item.summary ?? "", at: row.date,
                             artwork: source != nil && item.artwork?.item_id == item.playback_item_id ? item.artwork : nil,
                             source: source, tint: tint)
            }
        case .playback(let item):
            if item.isCurrent(at: date), let source = DJConnectLiveGuestModel.spotifyURL(item.source_url) {
                let recording = [item.title, item.artist].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
                contribution(title: text("ui.session.history.playback"), body: recording, at: row.date,
                             artwork: item.artwork?.item_id == item.playback_item_id ? item.artwork : nil,
                             source: source, tint: tint)
                    .accessibilityIdentifier("live-guest-observed-playback")
            }
        }
    }

    private func contribution(title: String?, body: String, at date: Date?, artwork: DJConnectLiveGuestModel.Artwork?,
                              source: URL?, tint: Color?) -> some View {
        let layout = dynamicType.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
        return layout {
            if let artwork {
                DJConnectGuestArtwork(guest: guest, artwork: artwork).frame(width: 70)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    if let title { Text(title).accessibilityAddTraits(.isHeader) }
                    Spacer(minLength: 4)
                    if let date, date != .distantPast {
                        Text(date, format: .dateTime.hour().minute().locale(locale)).monospacedDigit()
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
                Text(body)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let source { spotifyLink(source) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .djSessionFrostedSurface(surfaceTint: tint?.opacity(0.50))
    }

    private func spotifyLink(_ source: URL) -> some View {
        Link(destination: source) {
            Image("SpotifyAttribution").resizable().scaledToFit().frame(width: 68, height: 20)
        }
        .accessibilityLabel("Spotify")
    }

    private func elapsed(_ milliseconds: Int) -> String {
        Duration.seconds(milliseconds / 1_000).formatted(.time(pattern: .minuteSecond).locale(locale))
    }

    private func horizon(tint: Color?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                if let horizon = guest.horizon, horizon.isCurrent, !horizon.sections.isEmpty {
                    SessionHorizonHero(theme: .init(sessionMood: guest.session?.mood))
                    ForEach(Array(horizon.sections.enumerated()), id: \.offset) { _, section in
                        Text(section.text)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    DJConnectEmptyState(title: text("ui.session.forecast.empty"), systemImage: "sun.horizon")
                        .frame(minHeight: 220)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(16)
            .djSessionFrostedSurface(surfaceTint: tint?.opacity(0.50))
            .padding(.horizontal, gutter)
            .padding(.bottom, spacing)
            .frame(maxWidth: .infinity)
        }
        .environment(\.djConnectScrollingSurface, true)
        .accessibilityIdentifier("live-guest-horizon")
    }

    private var helpPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(vibeCastPartyTitle)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button { showsHelp = false } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .djConnectButtonStyle(DJConnectButtonStyle(shape: .icon))
                .accessibilityLabel(text("ui.close"))
            }
            ViewThatFits(in: .vertical) {
                helpText
                ScrollView { helpText }
                    .scrollBounceBehavior(.basedOnSize)
            }
        }
        .padding(16)
        .frame(idealWidth: 340, maxWidth: 400, maxHeight: 420)
        .djConnectGlassPopoutSurface(nativePresentation: true)
        .accessibilityIdentifier("live-guest-help-popover")
    }

    private var helpText: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text(guest.requestSongsAllowed ? "ui.live.help" : "ui.live.help_information_only"))
            Text(text("ui.ask_dj.accuracy_notice"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var composer: some View {
        HStack(spacing: 12) {
            Button { showsHelp = true } label: {
                Image(systemName: "questionmark.circle").frame(width: 32, height: 32)
            }
                .buttonStyle(.plain)
                .accessibilityLabel(text("ui.live.help_title"))
                .accessibilityIdentifier("live-guest-help")
                .popover(isPresented: $showsHelp, arrowEdge: .bottom) {
                    helpPopover
                        .presentationCompactAdaptation(.popover)
                }
            TextField(text(guest.requestSongsAllowed ? "ui.live.composer" : "ui.live.composer_information_only"), text: $guest.draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("live-guest-composer")
            Button { Task { await guest.send(language: language) } } label: {
                Group {
                    if guest.isBusy { ProgressView() } else { Image(systemName: "paperplane.fill") }
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(!guest.canSend)
            .accessibilityLabel(text("ui.send"))
            .accessibilityIdentifier("live-guest-send")
        }
        .padding(14)
        .djSessionFrostedSurface()
        .frame(maxWidth: 760)
        .padding(.horizontal, gutter)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}

/// Reuses the native GPU renderer with public session style and local dynamics only.
private struct DJConnectGuestVibescape<TopControls: View>: View {
    @ObservedObject var guest: DJConnectLiveGuestModel
    let language: String
    @ViewBuilder let topControls: (@escaping () -> Void) -> TopControls
    @StateObject private var visit = VisualDirectorVisit()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var unavailable = false
    @State private var controlsVisible = true
    @State private var controlsGeneration = UUID()
    @State private var adjustingDynamics = false
    #if os(macOS)
    @State private var hoveringControls = false
    @State private var topBounds = CGRect.zero
    @State private var bottomBounds = CGRect.zero
    #else
    private let hoveringControls = false
    #endif

    private var style: [String] {
        [guest.session?.session_id ?? "", guest.viewState?.mood ?? "", guest.viewState?.persona ?? ""]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !unavailable, visit.scene != nil {
                VibeScapeMetalView(visit: visit, reduceMotion: reduceMotion,
                    isActive: scenePhase == .active, unavailable: { unavailable = true })
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            if unavailable {
                Text(DJConnectLocalization.localized(key: "ui.vibescape.unavailable", language: language))
                    .padding(28)
            }
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: showControls)
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                topControls(toggleControls)
                    #if os(macOS)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { topBounds = $0 }
                    #endif
                Spacer(minLength: 0)
                VibeScapeDynamicsControls(visit: visit, language: language,
                    editingChanged: dynamicsEditingChanged, didFollowDJ: showControls)
                    .disabled(visit.scene == nil || unavailable)
                    .frame(maxWidth: 480)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    #if os(macOS)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { bottomBounds = $0 }
                    #endif
            }
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)
            .accessibilityHidden(!controlsVisible)
        }
        #if os(macOS)
        .onContinuousHover(coordinateSpace: .global) { phase in
            switch phase {
            case let .active(point):
                updateControlHover(topBounds.contains(point) || bottomBounds.contains(point))
            case .ended:
                updateControlHover(false)
            }
        }
        #endif
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: controlsVisible)
        .task(id: controlsGeneration) {
            guard controlsVisible, !adjustingDynamics, !hoveringControls else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard !Task.isCancelled, !adjustingDynamics, !hoveringControls else { return }
            controlsVisible = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("VibeScape")
        .accessibilityAction(named: Text(DJConnectLocalization.localized(
            key: "ui.vibescape.dynamics", language: language)), showControls)
        .task(id: style) {
            guard guest.isJoined, let state = guest.viewState,
                  let persona = DJConnectSessionPersonaValue(rawValue: state.persona) else { visit.revoke(); return }
            visit.enter(mood: state.mood, occurrence: nil, family: VibeScapeFamily(persona: persona))
            visit.updateTrackIntensity(Float(state.dynamics))
        }
        .onChange(of: guest.viewState?.dynamics) { _, value in
            visit.updateTrackIntensity(value.map(Float.init))
        }
        .onDisappear { visit.revoke() }
    }

    private func showControls() {
        controlsVisible = true
        controlsGeneration = UUID()
    }

    private func toggleControls() {
        DJConnectHaptics.selection()
        controlsVisible.toggle()
        controlsGeneration = UUID()
    }

    private func dynamicsEditingChanged(_ editing: Bool) {
        if editing {
            DJConnectHaptics.selection()
            visit.beginDynamicsAdjustment()
        }
        adjustingDynamics = editing
        showControls()
    }

    #if os(macOS)
    private func updateControlHover(_ inside: Bool) {
        guard hoveringControls != inside else { return }
        hoveringControls = inside
        if inside { showControls() }
        else { controlsGeneration = UUID() }
    }
    #endif
}

/// Only the current guest-purpose bytes render here, with original source
/// expiry. Pixels and the guest bearer never enter a file or owner cache.
private struct DJConnectGuestArtwork: View {
    @ObservedObject var guest: DJConnectLiveGuestModel
    let artwork: DJConnectLiveGuestModel.Artwork
    var currentPlayback = false
    var isPlaying = false
    var queueCover = false
    var onTint: ((Color) -> Void)? = nil
    @State private var loadedCover: (artwork: DJConnectLiveGuestModel.Artwork, image: CGImage, tint: Color?)?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let loadedCover, loadedCover.artwork == artwork, guest.artworkIsCurrent(artwork) {
                let cover = Image(decorative: loadedCover.image, scale: 1).resizable().scaledToFit()
                    .accessibilityIdentifier("live-guest-artwork")
                if currentPlayback {
                    cover.djAlbumArtworkGlassCard(tint: loadedCover.tint)
                } else if queueCover {
                    cover.clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    cover.clipShape(RoundedRectangle(cornerRadius: 9))
                        .padding(4)
                        .djSessionFrostedSurface(cornerRadius: 14, surfaceTint: loadedCover.tint)
                }
            } else if currentPlayback {
                AlbumArtworkPlaceholder(tint: .gray, isPlaying: isPlaying)
                    .djAlbumArtworkGlassCard(tint: nil)
            } else if queueCover {
                QueueArtworkView(url: nil)
            }
        }
        .task(id: artwork) {
            loadedCover = nil
            guard let bytes = await guest.loadArtwork(artwork), !Task.isCancelled,
                  guest.artworkIsCurrent(artwork),
                  let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 8192, height <= 8192,
                  width * height <= 20_000_000 else { return }
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary) else { return }
            let tint = averageArtworkColor(from: thumbnail)
            loadedCover = (artwork, thumbnail, tint)
            if let tint { onTint?(tint) }
        }
        .onDisappear { loadedCover = nil }
    }
}
