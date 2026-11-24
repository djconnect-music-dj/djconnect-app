import Foundation
import Testing
@testable import DJConnectCore

@Suite("MusicOrigin") struct MusicOriginTests {
    func fixture() throws -> [String: Any] {
        let url = try #require(askDJMomentsFixtureBundle().url(forResource: "music-origin-v1", withExtension: "json", subdirectory: "Fixtures") ?? askDJMomentsFixtureURL("music-origin-v1"))
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    func decode<T: Decodable>(_ value: Any, _: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: value))
    }
    @Test func avatarMenuSelectsOriginAndAdmitsSameRetainedCard() throws {
        let f = try fixture()
        let capability = try decode(try #require(f["capability"]), DJConnectAskDJMoments.Capability.self)
        let inventory = try decode(try #require(f["inventory"]), DJConnectAskDJMoments.Inventory.self)
        #expect(capability.admits(client: .ios) && capability.admits(client: .macos))
        #expect(inventory.admits(session: inventory.sessionID, capability: capability))
        let item = try #require(inventory.orderedTypes.first { $0.typeID == "music_origin" })
        #expect(item.available && item.momentType == "music_origin")
        #expect(item.title(language: "nl") == "Waar ken ik dit nummer van?")
        let request = DJConnectAskDJMoments.Request(sessionID: inventory.sessionID, item: item)
        let response = try decode(try #require(f["response"]), DJConnectAskDJMoments.Response.self)
        #expect(response.matches(request, originalID: response.operationID))
        #expect(response.state == .accepted)
        let result = try #require(response.result)
        let capturedAt = try #require(f["captured_at"] as? String)
        let now = try #require(DJConnectHistoryEntry.date(capturedAt))
        #expect(result.admits(request: request, item: item, operationID: response.operationID, at: now))
        #expect(result.entryID != nil && result.retention == "retained" && result.historyState == "content_retained")
        #expect(result.moment.userRequested?.subjectReference == item.subject.reference)
    }
    @Test func actualCoreProducerPreservesNativeTypeUncertaintyAndSourceConsultation() throws {
        let f = try fixture(), response = try #require(f["response"] as? [String: Any])
        let result = try #require(response["result"] as? [String: Any])
        let moment = try decode(try #require(result["moment"]), DJConnectMoment.self)
        #expect(moment.isMusicOriginV1 && moment.isSupportedNativeType)
        #expect(moment.musicOrigin?.relation.kind == "interpolation")
        #expect(moment.musicOrigin?.relation.uncertainty == "possible")
        #expect(moment.musicOrigin?.relation.direction == "current_to_related")
        #expect(moment.researchSources.first?["consultation"] == "search_excerpt")
        #expect(moment.artwork == nil)
        #expect(try decode(JSONSerialization.jsonObject(with: JSONEncoder().encode(moment)), DJConnectMoment.self).musicOrigin == moment.musicOrigin)
    }
    @Test(arguments: ["unknown_schema", "unknown_relation", "unknown_direction", "invalid_media", "missing_subject"])
    func malformedPayloadCannotInheritNativeOrRequestedResultAdmission(_ mutation: String) throws {
        let f = try fixture(), response = try #require(f["response"] as? [String: Any])
        let result = try #require(response["result"] as? [String: Any])
        var moment = try #require(result["moment"] as? [String: Any])
        var origin = try #require(moment["music_origin"] as? [String: Any])
        var relation = try #require(origin["relation"] as? [String: Any])
        switch mutation {
        case "unknown_schema": origin["schema_version"] = 99
        case "unknown_relation": relation["kind"] = "invented"
        case "unknown_direction": relation["direction"] = "both"
        case "invalid_media": relation["kind"] = "media_use"
        default: origin.removeValue(forKey: "subject")
        }
        origin["relation"] = relation; moment["music_origin"] = origin
        let decoded = try decode(moment, DJConnectMoment.self)
        #expect(!decoded.isMusicOriginV1 && !decoded.isSupportedNativeType)
    }
    @Test(arguments: ["en", "nl", "de", "fr", "es"])
    func commonComposerNoticeAndUncertainDirectionAreLocalized(_ language: String) {
        for key in ["ui.ask_dj.accuracy_notice", "ui.music_origin.possible", "ui.music_origin.sample.related_to_current"] {
            let value = DJConnectLocalization.localized(key: key, language: language)
            #expect(value != key && !value.isEmpty)
        }
    }
}

#if os(macOS)
import AppKit
import SwiftUI
@testable import DJConnectUI

@Test(.isolatedAppKitResources) @MainActor func musicOriginNativeCardWrapsAtPhoneAndMacWidths() async throws {
    _ = NSApplication.shared
    let helper = MusicOriginTests()
    let packet = try helper.fixture(), response = try #require(packet["response"] as? [String: Any])
    let result = try #require(response["result"] as? [String: Any])
    let moment = try helper.decode(try #require(result["moment"]), DJConnectMoment.self)
    let origin = try #require(moment.musicOrigin)
    for language in ["en", "nl", "de", "fr", "es"] {
        for width: CGFloat in [320, 900] {
            let content = VStack(alignment: .leading, spacing: 16) {
                MusicOriginContentView(origin: origin, title: moment.title, story: moment.content, language: language, discover: {})
                Text("Ask DJ").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(10).background(.white.opacity(0.12))
            }.padding(20).frame(width: width).foregroundStyle(.white).background(Color.indigo)
                .environment(\.dynamicTypeSize, .accessibility2).environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: content)
            let height = ceil(host.fittingSize.height)
            #expect(height > 200 && height < 2400)
            let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderBack(nil)
            try await Task.sleep(for: .milliseconds(30))
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            #expect(host.bounds.width == width)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap); window.close()
            if let folder = ProcessInfo.processInfo.environment["DJCONNECT_MUSIC_ORIGIN_ARTIFACT_DIR"] {
                let directory = URL(fileURLWithPath: folder)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("origin-\(language)-\(Int(width)).png"))
            }
        }
    }
}
#endif
