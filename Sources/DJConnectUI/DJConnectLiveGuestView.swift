import SwiftUI
import DJConnectCore
import ImageIO

/// Guest navigation has no paired model, owner controls or personal data sources.
struct DJConnectLiveGuestView: View {
    @ObservedObject var guest: DJConnectLiveGuestModel
    let language: String
    @State private var pastedLink = ""
    @State private var showsHelp = false
    @State private var showsHorizon = false
    @State private var showsVibescape = false

    private func text(_ key: String) -> String { DJConnectLocalization.localized(key: key, language: language) }

    var body: some View {
        NavigationStack {
            Group {
                if guest.isJoined { joinedContent }
                else { joinContent }
            }
            .navigationTitle("VibeCast Live")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { guest.disconnect() } label: {
                        Label(text(guest.isJoined ? "ui.live.leave" : "ui.cancel"), systemImage: guest.isJoined ? "stop.fill" : "xmark")
                    }
                    .accessibilityIdentifier("live-guest-leave")
                }
                ToolbarItem(placement: .primaryAction) {
                    Image(systemName: guest.isJoined ? "person.2.wave.2.fill" : "person.2.slash")
                        .accessibilityLabel(text(guest.isJoined ? "ui.live.connected" : "ui.live.not_connected"))
                        .accessibilityIdentifier("live-guest-connection")
                }
                if guest.isJoined {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { showsHorizon = true } label: { Image(systemName: "sun.horizon") }
                            .accessibilityLabel("Horizon")
                        Button { showsVibescape = true } label: { Image(systemName: "sparkles.tv") }
                            .accessibilityLabel("Vibescape")
                    }
                }
            }
            .background(DJConnectCanvasBackground())
            .sheet(isPresented: $showsHelp) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("VibeCast Live").font(.title2.bold())
                    Text(text(guest.requestSongsAllowed ? "ui.live.help" : "ui.live.help_information_only"))
                    Button(text("ui.close")) { showsHelp = false }
                }.padding(24)
            }
            .sheet(isPresented: $showsHorizon) {
                NavigationStack {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        ScrollView {
                            if let horizon = guest.horizon, horizon.isCurrent {
                                VStack(alignment: .leading, spacing: 16) {
                                    ForEach(Array(horizon.sections.enumerated()), id: \.offset) { _, section in Text(section.text) }
                                }.padding(24)
                            }
                        }
                    }
                    .navigationTitle("Horizon")
                    .toolbar { Button(text("ui.close")) { showsHorizon = false } }
                }
            }
            .sheet(isPresented: $showsVibescape) {
                NavigationStack {
                    DJConnectGuestVibescape(guest: guest, language: language)
                        .toolbar { Button(text("ui.close")) { showsVibescape = false } }
                }
            }
        }
        .accessibilityIdentifier("live-guest-root")
    }

    private var joinContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "qrcode.viewfinder").font(.system(size: 52))
                Text(text("ui.live.join_instructions"))
                    .multilineTextAlignment(.center)
                if guest.invitation != nil {
                    Button(text("ui.live.join")) { Task { await guest.join() } }
                        .djConnectButtonStyle(DJConnectButtonStyle(emphasis: .primary, expands: true))
                        .disabled(guest.isBusy)
                        .accessibilityIdentifier("live-guest-confirm")
                } else {
                    TextField(text("ui.live.invitation_link"), text: $pastedLink)
                        .textContentType(.URL)
                        .accessibilityIdentifier("live-guest-invitation")
                    Button(text("ui.live.open_invitation")) {
                        let link = pastedLink; pastedLink = ""; _ = guest.receive(link)
                    }
                    .disabled(pastedLink.isEmpty || guest.isBusy)
                }
                if let key = guest.statusKey { Text(text(key)).foregroundStyle(.secondary) }
                if guest.isBusy { ProgressView() }
            }.padding(24)
        }
    }

    private var joinedContent: some View {
        TabView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let playback = guest.playback {
                        VStack(alignment: .leading, spacing: 4) {
                            if let art = playback.artwork {
                                DJConnectGuestArtwork(guest: guest, artwork: art).frame(width: 100, height: 100)
                            }
                            Text(playback.title ?? "").font(.title2.bold())
                            Text(playback.artist ?? "").foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("live-guest-current-track")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .topTrailing) {
                            if playback.item_id != nil {
                                Menu {
                                    ForEach(["❤️", "🔥", "👏", "😍", "💃"], id: \.self) { emoji in
                                        Button(emoji) { Task { await guest.react(emoji) } }
                                    }
                                } label: { Text("❤️").font(.title2) }
                                .disabled(guest.isBusy)
                                .accessibilityLabel(text("ui.live.react"))
                                .accessibilityIdentifier("live-guest-emotion-menu")
                            }
                        }
                    }
                    if let title = guest.playingRequestTitle {
                        Label(String(format: text("ui.live.request_playing"), title), systemImage: "music.note")
                            .accessibilityIdentifier("live-guest-request-playing")
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        ForEach(guest.sharedFlow.filter { $0.isCurrent(at: context.date) }) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                if let art = item.artwork {
                                    DJConnectGuestArtwork(guest: guest, artwork: art).frame(width: 72, height: 72)
                                }
                                if let title = item.title { Text(title).font(.headline) }
                                Text(item.content ?? item.summary ?? "")
                            }
                        }
                    }
                    ForEach(guest.sharedFlow.isEmpty ? guest.moments : []) { moment in
                        VStack(alignment: .leading, spacing: 6) {
                            if let title = moment.title { Text(title).font(.headline) }
                            if let summary = moment.summary { Text(summary) }
                        }
                    }
                    ForEach(guest.messages) { message in
                        HStack {
                            if message.user { Spacer(minLength: 24) }
                            Text(message.text).padding(12)
                                .background(.white.opacity(message.user ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 16))
                            if !message.user { Spacer(minLength: 24) }
                        }
                    }
                    ForEach(guest.choices) { choice in
                        Button(choice.title + (choice.artist.map { " — " + $0 } ?? "")) {
                            Task { await guest.send(language: language, choice: choice) }
                        }.disabled(guest.isBusy)
                    }
                    if let key = guest.statusKey { Text(text(key)).foregroundStyle(.secondary) }
                }.padding(20)
            }
            .safeAreaInset(edge: .bottom) { composer }
            .tabItem { Label(text("ui.session.title"), systemImage: "person.2") }
            Color.clear.tabItem { Label(text("ui.queue"), systemImage: "list.number") }
                .accessibilityIdentifier("live-guest-empty-queue")
            Color.clear.tabItem { Label(text("ui.playlists"), systemImage: "rectangle.stack") }
                .accessibilityIdentifier("live-guest-empty-playlists")
            Color.clear.tabItem { Label("Ask DJ", systemImage: "bubble.left") }
                .accessibilityIdentifier("live-guest-empty-ask-dj")
        }
    }

    private var composer: some View {
        HStack(spacing: 12) {
            Button { showsHelp = true } label: { Image(systemName: "questionmark.circle") }
                .accessibilityLabel(text("ui.live.help_title"))
                .accessibilityIdentifier("live-guest-help")
            TextField(text(guest.requestSongsAllowed ? "ui.live.composer" : "ui.live.composer_information_only"), text: $guest.draft, axis: .vertical)
                .lineLimit(1...4)
                .accessibilityIdentifier("live-guest-composer")
            Button { Task { await guest.send(language: language) } } label: {
                if guest.isBusy { ProgressView() } else { Image(systemName: "paperplane.fill") }
            }
            .disabled(!guest.canSend)
            .accessibilityLabel(text("ui.send"))
            .accessibilityIdentifier("live-guest-send")
        }
        .padding(14)
        .background(.regularMaterial)
    }
}

/// Reuses the native GPU renderer with public session style and local dynamics only.
private struct DJConnectGuestVibescape: View {
    @ObservedObject var guest: DJConnectLiveGuestModel
    let language: String
    @StateObject private var visit = VisualDirectorVisit()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var unavailable = false

    private var style: [String] {
        [guest.session?.session_id ?? "", guest.viewState?.mood ?? "", guest.viewState?.persona ?? ""]
    }
    var body: some View {
        VStack {
            if unavailable {
                Image(systemName: "sparkles.tv").font(.largeTitle)
            } else if visit.scene != nil {
                VibeScapeMetalView(visit: visit, reduceMotion: reduceMotion,
                    isActive: scenePhase == .active, unavailable: { unavailable = true })
            }
            Slider(value: Binding(get: { Double(visit.dynamics) }, set: { _ = visit.setDynamics(Float($0)) }), in: 0...1)
                .accessibilityLabel(DJConnectLocalization.localized(key: "ui.live.local_dynamics", language: language))
                .disabled(visit.scene == nil)
                .padding()
        }
        .navigationTitle("Vibescape")
        .task(id: style) {
            guard guest.isJoined, let state = guest.viewState,
                  let persona = DJConnectSessionPersonaValue(rawValue: state.persona) else { visit.revoke(); return }
            visit.enter(mood: state.mood, occurrence: nil, family: VibeScapeFamily(persona: persona))
            _ = visit.setDynamics(Float(state.dynamics))
        }
        .onDisappear { visit.revoke() }
    }
}


/// Only the current guest-purpose bytes render here, with original source
/// expiry. Pixels and the guest bearer never enter a file or owner cache.
private struct DJConnectGuestArtwork: View {
    @ObservedObject var guest: DJConnectLiveGuestModel
    let artwork: DJConnectLiveGuestModel.Artwork
    @State private var image: CGImage?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if guest.artworkIsCurrent(artwork), let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .djConnectBreathingArtwork()
                    .accessibilityIdentifier("live-guest-artwork")
            }
        }
        .task(id: artwork) {
            image = nil
            guard let bytes = await guest.loadArtwork(artwork), !Task.isCancelled,
                  guest.artworkIsCurrent(artwork),
                  let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 8192, height <= 8192,
                  width * height <= 20_000_000 else { return }
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary)
        }
        .onDisappear { image = nil }
    }
}
