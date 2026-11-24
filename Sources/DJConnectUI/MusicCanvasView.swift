import SwiftUI
import DJConnectCore

/// A foreground presentation of Core-owned state. No local defaults or cadence.
@MainActor
struct MusicCanvasView: View {
    @ObservedObject var model: DJConnectAppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot: DJConnectCanvasSnapshot?
    @State private var busy = false
    @State private var refreshing = false
    @State private var readID = UUID()
    @State private var operationID: UUID?
    @State private var notice: String?
    @State private var selected: DJConnectCanvasTarget?
    @State private var cleanupRemote = false
    @State private var confirmingForget = false
    @State private var allowRemaining = false
    @State private var width = ""
    @State private var height = ""
    @State private var orientation = "portrait"
    @State private var preview: DJConnectSessionArtworkImage?

    private var scope: String {
        [model.sessionHistory.authorizedProfileID ?? "", model.activeDJSession?.id ?? "",
         String(describing: model.sessionHistory.responseEpoch), model.homeAssistantURL,
         model.haLocalURL, model.haRemoteURL, String(describing: model.haConnectionMode),
         String(describing: model.pairingStatus), String(describing: scenePhase)].joined(separator: "|")
    }
    private func text(_ key: String) -> String {
        DJConnectLocalization.localized(key: "ui.canvas." + key, language: model.language)
    }
    private func current(_ captured: String) -> Bool {
        captured == scope && scenePhase == .active && model.pairingStatus == .paired && !model.isDemoMode
    }

    var body: some View {
        MusicCanvasPopupSurface(title: "Music Canvas", language: model.language, done: { dismiss() }) {
            VStack(alignment: .leading, spacing: 18) {
                Section {
                    Text(text("description")).foregroundStyle(.secondary)
                    if let snapshot {
                        Toggle(text("enabled"), isOn: Binding(get: { snapshot.preferences.enabled }, set: { enabled in
                            change { $0.enabled = enabled }
                        }))
                        if !snapshot.image_generation_available {
                            Text(text("provider_required")).foregroundStyle(.secondary)
                        }
                    }
                }
                if let snapshot {
                    Section(text("screens")) {
                        if snapshot.targets.isEmpty { Text(text("no_screens")).foregroundStyle(.secondary) }
                        ForEach(snapshot.targets) { target in
                            HStack {
                                Toggle(isOn: Binding(get: { snapshot.preferences.selected_targets.contains(target.id) }, set: { enabled in
                                    change {
                                        if enabled { $0.selected_targets.append(target.id) }
                                        else {
                                            $0.selected_targets.removeAll { $0 == target.id }
                                            $0.cadence_overrides.removeValue(forKey: target.id)
                                        }
                                    }
                                })) {
                                    VStack(alignment: .leading) {
                                        Text(target.name)
                                        Text(status(target.state)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Button {
                                    selected = target; cleanupRemote = false; allowRemaining = false
                                    width = ""; height = ""; orientation = "portrait"; preview = nil
                                    if target.preview_available { loadPreview(target.id) }
                                } label: { Image(systemName: "info.circle") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(target.name + " — " + text("details"))
                            }
                        }
                    }
                    Section(text("presentation")) {
                        Picker(text("composition"), selection: Binding(get: { snapshot.preferences.composition }, set: { value in
                            change { $0.composition = value }
                        })) {
                            ForEach(["central", "free", "full"], id: \.self) { Text(text($0)).tag($0) }
                        }
                        Picker(text("matte"), selection: Binding(get: { snapshot.preferences.matte }, set: { value in
                            change { $0.matte = value }
                        })) {
                            ForEach(["off", "matching", "contrast"], id: \.self) { Text(text($0)).tag($0) }
                        }
                        Picker(text("cadence"), selection: Binding(get: { snapshot.preferences.cadence }, set: { value in
                            change { $0.cadence = value }
                        })) {
                            ForEach(DJConnectCanvasPreferences.cadences, id: \.self) { Text(text("cadence." + $0)).tag($0) }
                        }
                    }
                }
                if let notice {
                    Text(notice).foregroundStyle(.secondary).accessibilityIdentifier("canvas-notice")
                    Button(DJConnectLocalization.localized(key: "ui.retry", language: model.language)) {
                        let captured = scope
                        Task { await refresh(captured) }
                    }
                    .djConnectButtonStyle(DJConnectButtonStyle())
                    .disabled(refreshing)
                    .accessibilityIdentifier("music-canvas-retry")
                }
                if busy || (snapshot == nil && notice == nil) {
                    ProgressView().accessibilityLabel(text("working"))
                }
            }
            .disabled(busy)
            .task(id: scope) {
                snapshot = nil; selected = nil; preview = nil; notice = nil
                readID = UUID(); operationID = nil; busy = false; refreshing = false
                let captured = scope
                guard current(captured) else { return }
                while !Task.isCancelled && current(captured) {
                    if !busy { await refresh(captured) }
                    try? await Task.sleep(for: .seconds(5))
                }
            }
            .djConnectPopup(item: $selected) { target in
                details(target)
            }
            .onChange(of: scenePhase) { _, value in
                if value != .active { snapshot = nil; selected = nil; preview = nil }
            }
        }
        .accessibilityIdentifier("music-canvas-popup")
    }

    private func details(_ target: DJConnectCanvasTarget) -> some View {
        MusicCanvasPopupSurface(title: target.name, language: model.language, done: {
            selected = nil; preview = nil
        }) {
            VStack(alignment: .leading, spacing: 18) {
                Section {
                    Text(status(target.state))
                    if target.preview_available, let preview {
                        Image(decorative: preview.image, scale: 1).resizable().scaledToFit()
                    }
                }
                if let snapshot, snapshot.can_manage_devices, (target.state == "canvas_manual_takeover" || target.state != "ready" && !target.preview_available) {
                    Section(text("setup")) {
                        if target.screen.width == nil { TextField(text("width"), text: $width) }
                        if target.screen.height == nil { TextField(text("height"), text: $height) }
                        if target.screen.orientation == nil {
                            Picker(text("orientation"), selection: $orientation) {
                                Text(text("portrait")).tag("portrait")
                                Text(text("landscape")).tag("landscape")
                            }
                        }
                        Text(text(target.adapter == "samsung" ? "tv_permission" : "screen_setup"))
                            .font(.caption).foregroundStyle(.secondary)
                        Button(text("connect")) { setup(target) }
                    }
                }
                if let snapshot, snapshot.preferences.selected_targets.contains(target.id) {
                    Section(text("cadence")) {
                        Picker(text("override"), selection: Binding(get: {
                            snapshot.preferences.cadence_overrides[target.id] ?? "inherit"
                        }, set: { value in
                            change {
                                if value == "inherit" { $0.cadence_overrides.removeValue(forKey: target.id) }
                                else { $0.cadence_overrides[target.id] = value }
                            }
                        })) {
                            Text(text("inherit")).tag("inherit")
                            ForEach(DJConnectCanvasPreferences.cadences, id: \.self) { Text(text("cadence." + $0)).tag($0) }
                        }
                    }
                }
                if snapshot?.can_manage_devices == true {
                    Section {
                        Text(text("forget_detail")).font(.caption).foregroundStyle(.secondary)
                        if target.shared_profiles > 1 { Text(text("shared_warning")).foregroundStyle(.secondary) }
                        if target.remote_cleanup {
                            Toggle(text("cleanup_remote"), isOn: $cleanupRemote)
                        }
                        Button(text(allowRemaining || target.forgetting == true ? "forget_anyway" : "forget"), role: .destructive) {
                            confirmingForget = true
                        }
                    }
                }
                if let notice { Text(notice).foregroundStyle(.secondary) }
                if busy { ProgressView() }
            }
            .disabled(busy)
            .confirmationDialog(text("forget") + " — " + target.name, isPresented: $confirmingForget, titleVisibility: .visible) {
                Button(text(allowRemaining || target.forgetting == true ? "forget_anyway" : "forget"), role: .destructive) { forget(target) }
                Button(text("cancel"), role: .cancel) {}
            } message: { Text(text("forget_detail")) }
        }
        .accessibilityIdentifier("music-canvas-target-popup")
    }

    private func status(_ state: String) -> String {
        let known = ["disabled", "waiting_music", "preparing", "delivering", "displayed", "delivered_unknown",
                     "needs_setup", "discovered", "ready", "busy", "image_provider_required"]
        if known.contains(state) { return text("state." + state) }
        if state == "canvas_manual_takeover" { return text("state.waiting_screen") }
        if state == "canvas_public_asset_required" { return text("asset_required") }
        return text("state.unavailable")
    }

    private func refresh(_ captured: String) async {
        guard current(captured), !busy, !refreshing else { return }
        let requestID = UUID()
        readID = requestID; refreshing = true
        defer { if readID == requestID { refreshing = false } }
        do {
            let value = try await model.withHomeAssistantClient { try await $0.musicCanvas() }
            guard current(captured), !Task.isCancelled, readID == requestID else { return }
            snapshot = value; notice = nil
            if let selected { self.selected = value.targets.first { $0.id == selected.id } }
        } catch {
            guard current(captured), !Task.isCancelled, readID == requestID else { return }
            // A failed refresh cannot retain an old management grant or private image.
            snapshot = nil; selected = nil; preview = nil
            notice = text((error as? DJConnectCanvasReadFailure) == .notOffered ? "not_offered" : "unavailable")
            model.recordCanvasReadFailure(error)
        }
    }

    private func change(_ patch: (inout DJConnectCanvasPreferences) -> Void) {
        guard let snapshot, !busy else { return }
        var prefs = snapshot.preferences; patch(&prefs)
        perform(snapshot) { client, id in try await client.updateMusicCanvas(snapshot, preferences: prefs, operationID: id) }
    }
    private func setup(_ target: DJConnectCanvasTarget) {
        guard let snapshot else { return }
        let screen = DJConnectCanvasScreen(width: target.screen.width == nil ? Int(width) : nil,
            height: target.screen.height == nil ? Int(height) : nil,
            orientation: target.screen.orientation == nil ? orientation : nil)
        perform(snapshot) { client, id in try await client.setupMusicCanvas(snapshot, targetID: target.id, screen: screen, operationID: id) }
    }
    private func forget(_ target: DJConnectCanvasTarget) {
        guard let snapshot else { return }
        let cleanup = cleanupRemote, remaining = allowRemaining || target.forgetting == true
        perform(snapshot) { client, id in try await client.forgetMusicCanvas(snapshot, targetID: target.id,
            cleanupRemote: cleanup, allowRemainingArt: remaining, operationID: id) }
    }
    private func perform(_ before: DJConnectCanvasSnapshot,
                         operation: @escaping (DJConnectClient, UUID) async throws -> DJConnectCanvasReceipt) {
        guard !busy else { return }
        busy = true; notice = nil
        let captured = scope, id = UUID()
        operationID = id
        readID = UUID() // An older read cannot overwrite this pending choice.
        Task {
            guard current(captured), operationID == id else { return }
            var receipt: DJConnectCanvasReceipt?
            do {
                receipt = try await model.withHomeAssistantClient(allowsOperationReplay: false) { try await operation($0, id) }
            } catch {
                guard current(captured), operationID == id else { return }
                receipt = try? await model.withHomeAssistantClient {
                    try await $0.musicCanvasOperation(binding: before.binding, operationID: id)
                }
            }
            guard current(captured), operationID == id else { return }
            if receipt?.state == "cleanup_failed" {
                allowRemaining = true; notice = text("cleanup_failed")
            } else if receipt?.state == "unknown" || receipt?.state == "pending" || receipt == nil {
                notice = text("uncertain")
            } else if receipt?.state == "rejected" || receipt?.success == false {
                notice = text("change_failed")
            } else if receipt?.state == "confirmed", receipt?.revision == nil {
                selected = nil; preview = nil
            }
            busy = false
            operationID = nil
            await refresh(captured)
        }
    }
    private func loadPreview(_ target: String) {
        let captured = scope
        Task {
            do {
                let bytes = try await model.withHomeAssistantClient { try await $0.musicCanvasPreview(targetID: target) }
                guard current(captured), selected?.id == target else { return }
                preview = bytes
            } catch {
                guard current(captured), selected?.id == target else { return }
                snapshot = nil; selected = nil; preview = nil
                notice = text("unavailable")
            }
        }
    }
}

/// The same app canvas, hero, frosted content and explicit action used by
/// ordinary DJConnect popups. It owns presentation only, never Canvas state.
@MainActor struct MusicCanvasPopupSurface<Content: View>: View {
    let title: String
    let language: String
    let done: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            DJConnectCanvasBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 12) {
                        DJConnectHeroGlyph(systemImage: "photo.artframe")
                        Text(title).font(.title2.bold()).multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                    }.frame(maxWidth: .infinity)
                    content().padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .djSessionFrostedSurface()
                    Button(DJConnectLocalization.localized(key: "ui.canvas.done", language: language), action: done)
                        .djConnectButtonStyle(DJConnectButtonStyle(emphasis: .primary, expands: true))
                        .accessibilityIdentifier("music-canvas-done")
                }.padding(24)
            }.scrollBounceBehavior(.basedOnSize)
        }
        .frame(minWidth: djConnectDialogMinimumWidth, idealWidth: 560, maxWidth: 680)
        #if os(macOS)
        .frame(minHeight: 420, idealHeight: 640)
        #endif
        .presentationBackground { DJConnectCanvasBackground() }
    }
}
