import SwiftUI
import DJConnectCore

struct MusicOriginContentView: View {
    let origin: DJConnectMusicOrigin
    let title: String
    let story: String
    let language: String
    var discover: (() -> Void)? = nil
    func text(_ key: String) -> String { DJConnectLocalization.localized(key: "ui.music_origin." + key, language: language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text("label")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text(origin.subject.title).font(.subheadline.weight(.semibold))
            Text(origin.subject.artist).font(.caption).foregroundStyle(.secondary)
            // Spell out direction; an unqualified arrow must not turn a
            // possible relationship into a definite sample claim.
            Text([origin.relation.uncertainty == "stated" ? "" : text(origin.relation.uncertainty),
                  text(origin.relation.kind + "." + origin.relation.direction)].filter { !$0.isEmpty }.joined(separator: " "))
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Text([origin.relation.target.title, origin.relation.target.artist].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text(story).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if origin.hasOriginalTarget, let discover {
                Button(text("discover"), action: discover).frame(minHeight: 44)
                    .accessibilityIdentifier("music-origin-discover-original")
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("music-origin-content")
    }
}


/// An explicit information request through the ordinary pinned Ask DJ composer.
/// No player, queue or client-owned lookup is introduced.
@MainActor func discoverMusicOrigin(_ origin: DJConnectMusicOrigin, sessionID: String,
    model: DJConnectAppModel, begin: () -> Void) {
    guard origin.hasOriginalTarget, model.activeDJSession?.id == sessionID else { return }
    begin()
    let title = [origin.relation.target.title, origin.relation.target.artist].filter { !$0.isEmpty }.joined(separator: " — ")
    model.askDJDraft = String(format: DJConnectLocalization.localized(key: "ui.music_origin.discover_question", language: model.language), title)
    model.sendAskDJText()
}
