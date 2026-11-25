import SwiftUI
import DJConnectCore
#if os(macOS)
import AppKit
#endif

struct AskDJMomentsCardContent: View {
    @ObservedObject var controller: AskDJMomentsController
    let language: String
    let mood: String?
    let result: () -> AnyView
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var reading = false
    @State private var scrollVisible = false
    #if os(macOS)
    @State private var windowVisible = false
    #else
    @State private var windowVisible = true
    #endif
    private func text(_ key: String) -> String { DJConnectLocalization.localized(key: "ui.ask_moments." + key, language: language) }
    var body: some View {
        let generation = controller.generation
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(text("title")).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button { controller.close() } label: { Image(systemName: "xmark") }
                    .djConnectButtonStyle(DJConnectButtonStyle(shape: .icon))
                    .accessibilityLabel(text("close"))
                    .accessibilityIdentifier("ask-moments-close")
            }
            switch controller.presentation.phase {
            case .choosing:
                if controller.loading { Text(text("loading_inventory")) }
                if let inventory = controller.inventory {
                    AskDJMomentsCatalogue(inventory: inventory, language: language, unavailableLabel: text("unavailable"),
                                          mood: mood, select: controller.select)
                }
            case .pending:
                if !controller.outcomeUnknown {
                    Text(controller.pendingText ?? text("loading_inventory")).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("ask-moments-pending")
                }
                if controller.noticeText != nil {
                    Button(text("check_status")) { controller.checkStatus() }.frame(minHeight: 44)
                }
            case .presenting:
                result()
                    .id("requested-rich-result-" + generation.uuidString)
                    .onScrollVisibilityChange(threshold: 0.01) { visible in
                        guard controller.generation == generation else { return }
                        scrollVisible = visible
                        controller.visibility(visible && windowVisible && scenePhase == .active, generation: generation)
                    }
                    .onDisappear { controller.visibility(false, generation: generation) }
                if let accepted = controller.currentResult,
                   accepted.retention == "retained" || accepted.moment.privateBulletinHeadlines.isEmpty {
                    Text(text(accepted.retention == "retained" ? "already_saved" : "not_retained"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(text(reading ? "release_reading" : "keep_reading"), isOn: $reading)
                    .onChange(of: reading) { _, active in controller.hold(.reading, active, generation: generation) }
                    .frame(minHeight: 44)
            case .notice:
                if controller.canChooseAgain {
                    Button(text("choose")) { controller.chooseAgain() }
                        .djConnectButtonStyle(DJConnectButtonStyle())
                        .accessibilityIdentifier("ask-moments-choose-again")
                } else if controller.operationID != nil {
                    Button(text("check_status")) { controller.checkStatus() }.frame(minHeight: 44)
                }
            case .idle: EmptyView()
            }
            if let notice = controller.noticeText { Text(notice).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ask-moments-current-card")
        .onChange(of: scenePhase) { _, phase in
            controller.visibility(scrollVisible && windowVisible && phase == .active, generation: generation)
        }
        .onChange(of: voiceOver, initial: true) { _, enabled in controller.hold(.accessibility, enabled, generation: generation) }
        .onChange(of: controller.presentation.momentID) { _, id in
            if id == nil { scrollVisible = false }
            controller.hold(.accessibility, voiceOver, generation: generation)
        }
        .onAppear { reading = controller.presentation.holds.contains(.reading) }
        .onDisappear { controller.visibility(false, generation: generation) }
        .background {
            #if os(macOS)
            AskDJMomentsWindowVisibility { visible in
                guard windowVisible != visible else { return }
                windowVisible = visible
                controller.visibility(scrollVisible && visible && scenePhase == .active, generation: generation)
            }.frame(width: 0, height: 0)
            #endif
        }
        .task {
            while !Task.isCancelled {
                controller.tick()
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
        }
    }
}

struct AskDJMomentsCatalogue: View {
    let inventory: DJConnectAskDJMoments.Inventory
    let language: String
    let unavailableLabel: String
    var mood: String? = nil
    let select: (DJConnectAskDJMoments.Item) -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    private var iconGradient: LinearGradient {
        let colors = contrast == .increased ? [Color.white] : DJConnectSessionMoodTheme(sessionMood: mood).swiftUIColors
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            if let context = inventory.subjectContext,
               context.artist != nil || context.album != nil || context.trackTitle != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let artist = context.artist {
                        Text(artist).font(.title3.weight(.semibold))
                            .accessibilityLabel(DJConnectLocalization.localized(key: "ui.artist", language: language))
                            .accessibilityValue(artist)
                    }
                    if let album = context.album {
                        Label(album, systemImage: "opticaldisc").font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityLabel(DJConnectLocalization.localized(key: "ui.album", language: language))
                            .accessibilityValue(album)
                    }
                    if let track = context.trackTitle {
                        Label(track, systemImage: "music.note").font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityLabel(DJConnectLocalization.localized(key: "ui.track", language: language))
                            .accessibilityValue(track)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("ask-moments-subject-context")
            }
            if inventory.visibleTypes.isEmpty {
                Text(unavailableLabel).foregroundStyle(.secondary)
                    .accessibilityIdentifier("ask-moments-no-available-types")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), alignment: .leading)], alignment: .leading, spacing: 10) {
                ForEach(inventory.visibleTypes) { item in
                    Button { select(item) } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: symbol(for: item.typeID))
                                .font(.title2.weight(.medium))
                                .foregroundStyle(iconGradient)
                                .frame(width: 32, height: 32)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title(language: language)).font(.headline)
                                if !item.available {
                                    Text(item.unavailableReason(language: language) ?? unavailableLabel)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                    .djConnectButtonStyle(DJConnectButtonStyle(shape: .segmented, expands: true))
                    .disabled(!item.available)
                    .accessibilityIdentifier("ask-moments-type-" + item.typeID)
                }
            }
        }
        }.frame(maxHeight: 480)
    }
    private func symbol(for type: String) -> String {
        switch type {
        case "artist_story", "artist_discovery": return "person.wave.2"
        case "album_story", "album_continuity": return "opticaldisc"
        case "shared_producer", "producer_recommendation", "recording_story": return "slider.horizontal.3"
        case "music_origin": return "sparkle.magnifyingglass"
        case "dj_bulletin": return "newspaper"
        default: return "music.note"
        }
    }
}

#if os(macOS)
/// A mounted/offscreen SwiftUI node is not proof that its Mac window is visible.
private struct AskDJMomentsWindowVisibility: NSViewRepresentable {
    var changed: (Bool) -> Void
    func makeNSView(context: Context) -> Probe { Probe(changed: changed) }
    func updateNSView(_ view: Probe, context: Context) { view.changed = changed; view.report() }
    final class Probe: NSView {
        var changed: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []
        init(changed: @escaping (Bool) -> Void) { self.changed = changed; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver); observers = []
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                })
            }
            report()
        }
        func report() {
            let visible = window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false
            let changed = changed
            DispatchQueue.main.async { changed(visible) }
        }
        isolated deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
#endif
