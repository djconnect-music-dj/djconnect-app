#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import DJConnectCore
@testable import DJConnectUI

@Test func macMainScreensShareTheListWidthAndKeepWideExceptions() {
    let capped: [DJConnectSection] = [.djSession, .savedSessions, .trackInsight, .askDJ, .queue, .more, .musicDNA, .discovery,
                                     .playlists, .settings, .logs, .about, .legal, .privacy]
    let wide: [DJConnectSection] = [.games]
    for section in capped {
        #expect(section.detailWidth(in: 1_920) == 1_032)
        #expect(section.detailWidth(in: 820) == 820)
        #expect(section.detailWidth(in: 1_200, maximum: nil) == 1_200)
    }
    for section in wide {
        #expect(section.detailWidth(in: 1_920) == 1_920)
    }
}

@Test(.isolatedAppKitResources) @MainActor func macDetailWidthPreservesAnExistingNarrowPanel() throws {
    let width: CGFloat = 1_600
    let detailWidth = DJConnectSection.djSession.detailWidth(in: width)
    let content = VStack(spacing: 0) {
        Rectangle().fill(.white).frame(maxWidth: 728).frame(height: 20)
        Rectangle().fill(.white).frame(height: 20)
    }
    .padding(.horizontal, 16)
    .frame(width: detailWidth)
    .frame(width: width)
    let renderer = ImageRenderer(content: content)
    renderer.scale = 1
    let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    #expect(bitmap.colorAt(x: 400, y: 10)?.alphaComponent == 0)
    #expect(bitmap.colorAt(x: 800, y: 10)?.alphaComponent == 1)
    #expect(bitmap.colorAt(x: 400, y: 30)?.alphaComponent == 1)
    #expect(bitmap.colorAt(x: 200, y: 30)?.alphaComponent == 0)
}

@Test(.isolatedAppKitResources, arguments: [CGFloat(820), 1_600])
@MainActor func macDetailCentersBothGuttersOverOneContinuousCanvas(width: CGFloat) throws {
    let height: CGFloat = 100
    let screen = DJConnectDetailViewport(section: .askDJ, mood: nil) {
        Rectangle().fill(.white).frame(height: 20)
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(DJConnectMainScreenBackground())
    }
    let renderer = ImageRenderer(content: screen.frame(width: width, height: height))
    renderer.scale = 1
    let actual = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    let reference = ImageRenderer(content: DJConnectMainScreenBackground().frame(width: width, height: height))
    reference.scale = 1
    let canvas = NSBitmapImageRep(cgImage: try #require(reference.cgImage))

    let inset = Int((width - DJConnectSection.askDJ.detailWidth(in: width)) / 2) + 16
    let rightEdge = Int(width) - inset
    let white = try #require(actual.colorAt(x: inset, y: 10)?.usingColorSpace(.deviceRGB))
    #expect(min(white.redComponent, white.greenComponent, white.blueComponent) > 0.99)
    #expect(actual.colorAt(x: rightEdge - 1, y: 10) == actual.colorAt(x: inset, y: 10))
    #expect(actual.colorAt(x: inset - 1, y: 10) == canvas.colorAt(x: inset - 1, y: 10))
    #expect(actual.colorAt(x: rightEdge, y: 10) == canvas.colorAt(x: rightEdge, y: 10))
    for x in [0, inset, Int(width) / 2, rightEdge - 1, Int(width) - 1] {
        #expect(actual.colorAt(x: x, y: 70) == canvas.colorAt(x: x, y: 70))
    }
}

/// Exercises the shipping MomentCard, not only the two-column helper. The
/// thumbnail descriptor is a declared UI fixture; no private pixels are read.
/// Its reserved100-point slot must keep every ordinary typed contribution's
/// text at top-right even while the separately authorized image is loading.
@Test(.isolatedAppKitResources, arguments: [CGFloat(320), 620, 1100])
@MainActor func actualMomentCardsKeepTextBesideTrackThumbnail(width: CGFloat) throws {
    let suite = "moment-card-columns-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    let model = DJConnectAppModel(defaults: defaults, tokenStore: DJConnectInMemoryTokenStore(), startBackgroundTasks: false)
    defer { model.markInactiveSession(); defaults.removePersistentDomain(forName: suite) }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let raw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Fixtures/session-artwork-core-5c7ecb79.json"))) as? [String: Any])
    let examples = try #require(raw["examples"] as? [String: [String: Any]])
    let projection = try #require(examples["album_story"]?["projection"])
    let media = try JSONDecoder().decode(DJConnectSessionMedia.self, from: JSONSerialization.data(withJSONObject: projection))
    for type in ["album", "artist", "music_announcement", "dj_bulletin"] {
        var moment = try #require(DJConnectDemoSessionData.make(language: "nl").active.broadcast.djMoments.first)
        moment.sessionID = media.sessionID; moment.momentID = try #require(media.momentID)
        moment.type = type
        moment.title = "A real card with a long title"
        moment.content = String(repeating: "Long contribution text wraps without moving beneath the album thumbnail. ", count: 5)
        moment.sourceReferences = []; moment.sources = []; moment.researchSources = []
        let view = MomentCard(moment: moment, kind: type, presentation: nil, language: "nl",
                              artworkMedia: media, artworkModel: model, usesCurrentAvatar: true)
            .environment(\.scenePhase, .background)
            .environment(\.dynamicTypeSize, .accessibility2)
            .environment(\.djConnectGlassEffectsEnabled, false)
            .foregroundStyle(.white).frame(width: width, alignment: .leading).background(.black)
        let renderer = ImageRenderer(content: view); renderer.scale = 1
        let image = try #require(renderer.nsImage)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        #expect(image.size.width == width)
        #expect(image.size.height > 100)
        var firstTextX = bitmap.pixelsWide
        for y in 0..<min(80, bitmap.pixelsHigh) {
            for x in 0..<bitmap.pixelsWide {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if max(c.redComponent, max(c.greenComponent, c.blueComponent)) > 0.15 {
                    firstTextX = min(firstTextX, x)
                }
            }
        }
        #expect(firstTextX >= 115 && firstTextX < bitmap.pixelsWide,
                "Actual \(type) text must start beyond the100-point thumbnail plus16-point gap")
        if let path = ProcessInfo.processInfo.environment["DJCONNECT_MOMENT_COLUMNS_DIR"] {
            let folder = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: folder.appendingPathComponent("\(type)-\(Int(width)).png"))
        }
    }
}
#endif
