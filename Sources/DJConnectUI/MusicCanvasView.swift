import SwiftUI
import DJConnectCore

/// A foreground presentation of Core-owned state. No local defaults or cadence.
@MainActor
struct MusicCanvasView: View {
    @ObservedObject var model: DJConnectAppModel
    let onSnapshot: (DJConnectCanvasSnapshot?, String) -> Void
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

    private struct PreviewRequest: Equatable {
        let targetID: String
        let revision: String?
        let scope: String
    }

    private var previewRequest: PreviewRequest? {
        guard let selected, selected.preview_available, current(scope) else { return nil }
        return PreviewRequest(targetID: selected.id, revision: selected.preview_revision, scope: scope)
    }

    private var scope: String {
        Self.scope(for: model, scenePhase: scenePhase)
    }

    static func scope(for model: DJConnectAppModel, scenePhase: ScenePhase) -> String {
        [model.sessionHistory.authorizedProfileID ?? "", model.activeDJSession?.id ?? "",
         String(describing: model.sessionHistory.responseEpoch), model.homeAssistantURL,
         model.haLocalURL, model.haRemoteURL,
         String(describing: model.pairingStatus), String(describing: scenePhase)].joined(separator: "|")
    }
    private func text(_ key: String) -> String {
        DJConnectLocalization.localized(key: "ui.canvas." + key, language: model.language)
    }
    private func current(_ captured: String) -> Bool {
        captured == scope && scenePhase == .active && model.pairingStatus == .paired && !model.isDemoMode
    }

    var body: some View {
        let loadScope = scope
        let request = previewRequest
        let settingsTitle = DJConnectLocalization.localized(key: "ui.settings", language: model.language)
        DJConnectGlassDialogSurface(
            title: selected == nil ? "Music Canvas" : settingsTitle,
            icon: DJConnectHeroGlyph(systemImage: "photo.artframe")
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if let selected, let snapshot {
                    targetSettings(selected, snapshot: snapshot).disabled(busy)
                } else {
                    Text(text("description")).foregroundStyle(.secondary)
                    if let snapshot { screenChooser(snapshot) }
                }
                if let snapshot, !snapshot.image_generation_available {
                    Text(text("provider_required")).foregroundStyle(.secondary)
                }
                if let notice {
                    Text(notice).foregroundStyle(.secondary).accessibilityIdentifier("canvas-notice")
                    Button(DJConnectLocalization.localized(key: "ui.retry", language: model.language)) {
                        let captured = scope
                        Task { await refresh(captured) }
                    }
                    .djConnectButtonStyle(DJConnectButtonStyle())
                    .disabled(refreshing || busy)
                    .accessibilityIdentifier("music-canvas-retry")
                }
                if busy || (refreshing && snapshot == nil && notice == nil) {
                    ProgressView().accessibilityLabel(text("working"))
                }
            }
            VStack(spacing: 12) {
                if selected != nil {
                    Button(DJConnectLocalization.localized(key: "ui.session.intro.back", language: model.language)) {
                        selected = nil
                        preview = nil
                    }
                    .djConnectButtonStyle(DJConnectButtonStyle(expands: true))
                    .controlSize(.large)
                    .accessibilityIdentifier("music-canvas-back")
                }
                Button(text("done")) { dismiss() }
                    .djConnectButtonStyle(DJConnectButtonStyle(emphasis: .primary, expands: true))
                    .controlSize(.large)
                    .accessibilityIdentifier("music-canvas-done")
            }
        }
        .accessibilityIdentifier(selected == nil ? "music-canvas-popup" : "music-canvas-settings-page")
        .task(id: request) { await loadPreview(request) }
        .task(id: loadScope) {
            guard !Task.isCancelled, scope == loadScope else { return }
            snapshot = nil; selected = nil; preview = nil; notice = nil
            readID = UUID(); operationID = nil; busy = false; refreshing = false
            guard current(loadScope) else {
                if scenePhase == .active { notice = text("not_offered") }
                return
            }
            while !Task.isCancelled && current(loadScope) {
                if !busy { await refresh(loadScope) }
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onChange(of: scenePhase) { _, value in
            if value != .active { snapshot = nil; selected = nil; preview = nil }
        }
    }

    private func screenChooser(_ snapshot: DJConnectCanvasSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text("choose_screens")).font(.headline).accessibilityAddTraits(.isHeader)
            if snapshot.targets.isEmpty { Text(text("no_screens")).foregroundStyle(.secondary) }
            ForEach(snapshot.targets) { target in
                let isSelected = snapshot.preferences.enabled && snapshot.preferences.selected_targets.contains(target.id)
                HStack(spacing: 0) {
                    Button {
                        change {
                            if isSelected {
                                $0.selected_targets.removeAll { $0 == target.id }
                            } else if $0.enabled {
                                $0.selected_targets.append(target.id)
                            } else {
                                $0.selected_targets = [target.id]
                            }
                            $0.enabled = !$0.selected_targets.isEmpty
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.62))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(target.name).multilineTextAlignment(.leading)
                                Text(status(target.state)).font(.caption).foregroundStyle(.secondary)
                                if target.adapter == "switchbot", needsScreenGeometry(target), !snapshot.can_manage_devices {
                                    Text(text("switchbot_ha_setup")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 44)
                        .padding(.leading, 12)
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("music-canvas-screen-" + target.id)
                    Button {
                        selected = target
                        cleanupRemote = false; allowRemaining = false
                        width = ""; height = ""; orientation = "portrait"; preview = nil
                    } label: {
                        Image(systemName: "chevron.forward")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(
                        DJConnectLocalization.localized(key: "ui.settings", language: model.language) + " — " + target.name
                    )
                    .accessibilityIdentifier("music-canvas-screen-settings-" + target.id)
                }
                .buttonStyle(.plain)
                .background(.white.opacity(isSelected ? 0.15 : 0.06), in: RoundedRectangle(cornerRadius: 12))
                .disabled(busy)
            }
        }
    }

    private func settingRow<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            control()
        }
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
    }

    private func needsScreenGeometry(_ target: DJConnectCanvasTarget) -> Bool {
        target.screen.width == nil || target.screen.height == nil || target.screen.orientation == nil
    }

    private func matteSetting(_ matte: String, update: @escaping @MainActor @Sendable (String) -> Void) -> some View {
        settingRow(text("matte")) {
            Picker(text("matte"), selection: Binding(get: { matte }, set: update)) {
                ForEach(DJConnectCanvasPresentation.mattes, id: \.self) { Text(text($0)).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private func trackTitleSetting(
        _ enabled: Bool, identifier: String, update: @escaping @MainActor @Sendable (Bool) -> Void
    ) -> some View {
        settingRow(text("show_track_title")) {
            Toggle(text("show_track_title"), isOn: Binding(get: { enabled }, set: update))
                .labelsHidden()
                .accessibilityIdentifier(identifier)
        }
    }

    private func targetSettings(_ target: DJConnectCanvasTarget, snapshot: DJConnectCanvasSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 4) {
                Text(target.name).font(.headline)
                Text(status(target.state)).font(.caption).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            if target.preview_available, selected?.id == target.id, let preview {
                Image(decorative: preview.image, scale: 1).resizable().scaledToFit()
            }
            if snapshot.preferences.presentation_overrides != nil {
                let style = snapshot.preferences.presentation(for: target)
                if snapshot.per_screen_composition_and_cadence == true {
                    let composition = style.composition ?? snapshot.preferences.composition
                    settingRow(text("composition")) {
                        Picker(text("composition"), selection: Binding(get: { composition }, set: { value in
                            change { $0.updatePresentation(for: target) { $0.composition = value } }
                        })) {
                            ForEach(DJConnectCanvasPreferences.compositions, id: \.self) { Text(text($0)).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    let cadence = style.cadence ?? snapshot.preferences.cadence_overrides[target.id] ?? snapshot.preferences.cadence
                    settingRow(text("cadence")) {
                        Picker(text("cadence"), selection: Binding(get: { cadence }, set: { value in
                            change { $0.updatePresentation(for: target) { $0.cadence = value } }
                        })) {
                            ForEach(DJConnectCanvasPreferences.cadences, id: \.self) { Text(text("cadence." + $0)).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
                matteSetting(style.matte) { value in
                    change { $0.updatePresentation(for: target) { $0.matte = value } }
                }
                trackTitleSetting(style.show_track_title, identifier: "music-canvas-show-track-title-" + target.id) { enabled in
                    change { $0.updatePresentation(for: target) { $0.show_track_title = enabled } }
                }
            }
            if snapshot.can_manage_devices,
               target.state == "canvas_manual_takeover" || target.state == "discovered" || needsScreenGeometry(target) {
                if target.adapter == "switchbot", target.screen.width == nil,
                   target.screen.height == nil, target.screen.orientation == nil {
                    Button(text("switchbot_13_portrait")) {
                        width = "1200"
                        height = "1600"
                        orientation = "portrait"
                    }
                    .djConnectButtonStyle(DJConnectButtonStyle())
                    .accessibilityIdentifier("music-canvas-switchbot-13-portrait")
                }
                if target.screen.width == nil {
                    settingRow(text("width")) {
                        TextField(text("width"), text: $width).labelsHidden().multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110)
                    }
                }
                if target.screen.height == nil {
                    settingRow(text("height")) {
                        TextField(text("height"), text: $height).labelsHidden().multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110)
                    }
                }
                if target.screen.orientation == nil {
                    settingRow(text("orientation")) {
                        Picker(text("orientation"), selection: $orientation) {
                            Text(text("portrait")).tag("portrait")
                            Text(text("landscape")).tag("landscape")
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
                Text(text(target.adapter == "samsung" ? "tv_permission" : "screen_setup"))
                    .font(.caption).foregroundStyle(.secondary)
                Button(text("connect")) { setup(target) }
                    .djConnectButtonStyle(DJConnectButtonStyle())
            }
            if snapshot.can_manage_devices {
                if target.shared_profiles > 1 { Text(text("shared_warning")).foregroundStyle(.secondary) }
                if target.remote_cleanup {
                    settingRow(text("cleanup_remote")) {
                        Toggle(text("cleanup_remote"), isOn: $cleanupRemote).labelsHidden()
                    }
                }
                Button(text(allowRemaining || target.forgetting == true ? "forget_anyway" : "forget"), role: .destructive) {
                    confirmingForget = true
                }
            }
        }
        .confirmationDialog(text("forget") + " — " + target.name, isPresented: $confirmingForget, titleVisibility: .visible) {
            Button(text(allowRemaining || target.forgetting == true ? "forget_anyway" : "forget"), role: .destructive) { forget(target) }
            Button(text("cancel"), role: .cancel) {}
        } message: { Text(text("forget_detail")) }
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
            let value = try await model.withHomeAssistantClient(notifiesTransportFailure: false) {
                try await $0.musicCanvas()
            }
            guard current(captured), !Task.isCancelled, readID == requestID else { return }
            snapshot = value; notice = nil
            onSnapshot(value, captured)
            if let selected { self.selected = value.targets.first { $0.id == selected.id } }
        } catch {
            guard current(captured), !Task.isCancelled, readID == requestID else { return }
            // A failed refresh cannot retain an old management grant or private image.
            snapshot = nil; selected = nil; preview = nil
            onSnapshot(nil, captured)
            notice = text((error as? DJConnectCanvasReadFailure) == .notOffered ? "not_offered" : "unavailable")
            model.recordCanvasReadFailure(error)
        }
    }

    private func change(_ patch: (inout DJConnectCanvasPreferences) -> Void) {
        guard let snapshot, !busy else { return }
        var prefs = snapshot.preferences
        patch(&prefs)
        prefs.cadence_overrides = prefs.cadence_overrides.filter { prefs.selected_targets.contains($0.key) }
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
        refreshing = false
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
    private func loadPreview(_ request: PreviewRequest?) async {
        guard !Task.isCancelled, previewRequest == request else { return }
        preview = nil
        guard let request else { return }
        while !Task.isCancelled, previewRequest == request {
            do {
                let bytes = try await model.withHomeAssistantClient(notifiesTransportFailure: false) {
                    try await $0.musicCanvasPreview(targetID: request.targetID)
                }
                guard !Task.isCancelled, previewRequest == request else { return }
                preview = bytes
                if request.revision != nil { return }
            } catch {
                guard !Task.isCancelled, previewRequest == request else { return }
                preview = nil
            }
            // Older Core versions have no revision to invalidate the preview.
            try? await Task.sleep(for: .seconds(request.revision == nil ? 15 : 5))
        }
    }
}

/// Uses the feedback popup's glass surface for the heading, controls and actions.
@MainActor struct DJConnectGlassDialogSurface<Icon: View, Content: View>: View {
    let title: String
    let icon: Icon
    @ViewBuilder var content: () -> Content

    private var card: some View {
        VStack(spacing: 16) {
            icon
            Text(title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .djSessionFrostedSurface()
        .padding(28)
    }

    var body: some View {
        ZStack {
            DJConnectCanvasBackground()
            ViewThatFits(in: .vertical) {
                card.fixedSize(horizontal: false, vertical: true)
                ScrollView { card }.scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(minWidth: djConnectDialogMinimumWidth, idealWidth: 520, maxWidth: 620)
        .presentationBackground { DJConnectCanvasBackground() }
    }
}
