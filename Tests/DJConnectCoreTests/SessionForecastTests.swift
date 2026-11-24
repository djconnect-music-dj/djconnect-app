import Foundation
import CryptoKit
import Testing
@testable import DJConnectCore
import SwiftUI
@testable import DJConnectUI
#if os(macOS)
import AppKit
#endif

private func forecastCases() throws -> [[String: Any]] {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/session-forecast-core-3cfa5512.json")
    return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
}
private func forecastDecode(_ object: Any) throws -> DJConnectSessionForecast {
    try JSONDecoder().decode(DJConnectSessionForecast.self, from: JSONSerialization.data(withJSONObject: object))
}

@Test(.isolatedClientResources) func forecastActualProducerLocalesAndPersonasDecodeWithOriginalExpiry() throws {
    let cases = try forecastCases()
    #expect(Set(cases.compactMap { $0["language"] as? String }) == ["en", "nl", "de", "fr", "es"])
    #expect(Set(cases.compactMap { $0["persona"] as? String }).count == 4)
    for item in cases {
        let read = try #require(item["owner_read"] as? [String: Any])
        let forecast = try forecastDecode(try #require(read["forecast"]))
        #expect(forecast.structurallyValid)
        let issued = try #require(DJConnectSessionForecast.timestamp(forecast.issued_at))
        let until = try #require(DJConnectSessionForecast.timestamp(forecast.valid_until))
        #expect(forecast.isVisible(sessionID: forecast.session_id, playbackItemID: forecast.current_anchor?.item_id,
                                  playbackSource: forecast.current_anchor?.source_url, at: issued))
        #expect(!forecast.isVisible(sessionID: forecast.session_id, playbackItemID: forecast.current_anchor?.item_id,
                                   playbackSource: forecast.current_anchor?.source_url, at: until))
        #expect(!forecast.isVisible(sessionID: "another-session", playbackItemID: forecast.current_anchor?.item_id,
                                   playbackSource: forecast.current_anchor?.source_url, at: issued))
        #expect(!forecast.isVisible(sessionID: forecast.session_id, playbackItemID: "other-track",
                                   playbackSource: forecast.current_anchor?.source_url, at: issued))
    }
}

@Test(.isolatedClientResources) func forecastRevisionsCannotRestoreWithdrawnOrConflictingContent() throws {
    let item = try #require(forecastCases().first)
    let read = try #require(item["owner_read"] as? [String: Any])
    var object = try #require(read["forecast"] as? [String: Any])
    let latest = try forecastDecode(object)
    var cursor = DJConnectForecastCursor(sessionID: latest.session_id)
    cursor.receive(latest)
    #expect(cursor.projection == latest)
    object["revision"] = latest.revision - 1
    cursor.receive(try forecastDecode(object))
    #expect(cursor.projection == latest)
    object["revision"] = latest.revision
    object["summary"] = "Conflicting equal revision"
    cursor.receive(try forecastDecode(object))
    #expect(cursor.projection == nil)
    cursor.receive(latest)
    #expect(cursor.projection == nil)
    object["revision"] = latest.revision + 1
    let fresh = try forecastDecode(object)
    cursor.receive(fresh)
    #expect(cursor.projection == fresh)
    cursor.withdraw()
    cursor.receive(fresh)
    #expect(cursor.projection == nil)
    #expect(cursor.revisionFloor == fresh.revision)
}

@Test(.isolatedClientResources) func forecastUnknownSchemaAndIntentCannotBecomePlaybackClaims() throws {
    let item = try #require(forecastCases().first)
    let read = try #require(item["owner_read"] as? [String: Any])
    let original = try #require(read["forecast"] as? [String: Any])
    for (key, value) in [("contract_version", 2 as Any), ("nominal_window_seconds", 1200 as Any),
                         ("supported_window_seconds", 901 as Any), ("revision", -1 as Any)] {
        var object = original; object[key] = value
        #expect(try !forecastDecode(object).structurallyValid)
    }
    var object = original
    var sections = try #require(object["sections"] as? [[String: Any]])
    sections[0]["claim_type"] = "guaranteed_upcoming"
    object["sections"] = sections
    #expect(try !forecastDecode(object).structurallyValid)
}

@Test(.isolatedClientResources) func forecastEmptyWithoutTimestampsIsAnHonestWithdrawal() throws {
    let value = try forecastDecode(["contract_version": 1, "session_id": "s", "revision": 0,
        "state": "empty", "nominal_window_seconds": 900, "supported_window_seconds": 0,
        "summary": "", "sections": [], "imagery": []])
    #expect(value.structurallyValid)
    #expect(!value.isVisible(sessionID: "s", playbackItemID: nil, playbackSource: nil, at: Date()))
}

@Test(.isolatedClientResources) func forecastReadUsesExactOrdinaryPairedContractWithoutHistoryLimit() throws {
    let client = DJConnectClient(baseURL: URL(string: "https://fixture.invalid")!,
        identity: .init(deviceID: "djconnect-ios-ABCDEF123456", deviceName: "Test", clientType: .ios, firmware: "test", platform: .ios),
        tokenStore: DJConnectInMemoryTokenStore(token: "synthetic-test-only"))
    let request = try client.sessionForecastRequest(sessionID: "fixture-session")
    let url = try #require(request.url)
    #expect(request.httpMethod == "GET")
    #expect(url.path == "/api/djconnect/v1/session/forecast/fixture-session")
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(Set(query.map(\.name)) == ["device_id", "client_type", "contract_version"])
    #expect(query.first { $0.name == "contract_version" }?.value == "1")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-test-only")
    #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
}

@Test(.isolatedClientResources) func forecastMonotonicLeaseSurvivesFrozenClockAndArtOnlyRevision() throws {
    let read = try #require(forecastCases().first?["owner_read"] as? [String: Any])
    var object = try #require(read["forecast"] as? [String: Any])
    let forecast = try forecastDecode(object)
    let issued = try #require(DJConnectSessionForecast.timestamp(forecast.issued_at))
    var cursor = DJConnectForecastCursor(sessionID: forecast.session_id)
    cursor.receive(forecast, at: issued, uptime: 100)
    #expect(cursor.visible(playbackItemID: forecast.current_anchor?.item_id, playbackSource: forecast.current_anchor?.source_url,
                           at: issued, uptime: 101) != nil)
    object["revision"] = forecast.revision + 1
    // Same original expiry: art changes cannot renew the native lease.
    cursor.receive(try forecastDecode(object), at: issued.addingTimeInterval(10), uptime: 200)
    #expect(cursor.visible(playbackItemID: forecast.current_anchor?.item_id, playbackSource: forecast.current_anchor?.source_url,
                           at: issued.addingTimeInterval(11), uptime: 221) == nil)
    #expect(cursor.visible(playbackItemID: forecast.current_anchor?.item_id, playbackSource: forecast.current_anchor?.source_url,
                           at: issued.addingTimeInterval(-1), uptime: 201) == nil)
}

@Test(.isolatedClientResources) func forecastOptionalArtCannotBecomeHotlinkOrSuppressAuthoredText() throws {
    let read = try #require(forecastCases().first?["owner_read"] as? [String: Any])
    var object = try #require(read["forecast"] as? [String: Any])
    let original = try forecastDecode(object)
    let image = try #require(original.imagery.first)
    let issued = try #require(DJConnectSessionForecast.timestamp(original.issued_at))
    #expect(image.admittedPath(sessionID: original.session_id, at: issued) != nil)
    #expect(image.admittedPath(sessionID: "another-session", at: issued) == nil)
    #expect(image.admittedPath(sessionID: original.session_id, at: Date.distantFuture) == nil)
    let source = try #require((object["imagery"] as? [[String: Any]])?.first)
    for replacement in ["https://untrusted.invalid/art.jpg", "//untrusted.invalid/art.jpg", image.url + "?token=other", image.url + "/../other"] {
        var bad = source; bad["url"] = replacement
        object["imagery"] = [bad]
        let decoded = try forecastDecode(object)
        #expect(decoded.structurallyValid)
        #expect(decoded.summary == original.summary)
        #expect(decoded.imagery.first?.admittedPath(sessionID: original.session_id, at: issued) == nil)
    }
    object["imagery"] = [["broken": true]]
    let decoded = try forecastDecode(object)
    #expect(decoded.structurallyValid && decoded.imagery.isEmpty && decoded.summary == original.summary)
}


@Test(.isolatedClientResources, arguments: ["", "short", String(repeating: "A", count: 23), "../outside", "valid?query=1", "spotify:artist:6eUKZXaKkcviH0Ku9w2n3V", String(repeating: "é", count: 22)])
func forecastOptionalArtRequiresCanonicalArtistIdentity(_ artistID: String) throws {
    let read = try #require(forecastCases().first?["owner_read"] as? [String: Any])
    var object = try #require(read["forecast"] as? [String: Any])
    let original = try forecastDecode(object)
    var image = try #require((object["imagery"] as? [[String: Any]])?.first)
    var subject = try #require(image["subject"] as? [String: Any])
    subject["id"] = "spotify:artist:" + artistID
    image["subject"] = subject
    let url = "https://open.spotify.com/artist/" + artistID.replacingOccurrences(of: "spotify:artist:", with: "")
    image["source_url"] = url
    var attribution = try #require(image["attribution"] as? [String: Any])
    attribution["url"] = url; image["attribution"] = attribution
    object["imagery"] = [image]
    let decoded = try forecastDecode(object)
    let issued = try #require(DJConnectSessionForecast.timestamp(decoded.issued_at))
    #expect(decoded.structurallyValid && decoded.summary == original.summary)
    #expect(decoded.imagery.first?.admittedPath(sessionID: decoded.session_id, at: issued) == nil)
}

#if os(macOS)
@Test(.isolatedClientResources) @MainActor func forecastNativeTextRendersAllAuthoredLocalesAndLargeType() throws {
    for item in try forecastCases() where item["persona"] as? String == "home_dj" {
        let language = try #require(item["language"] as? String)
        let read = try #require(item["owner_read"] as? [String: Any])
        let forecast = try forecastDecode(try #require(read["forecast"]))
        let content = SessionForecastTextView(projection: forecast, language: language)
            .environment(\.dynamicTypeSize, .accessibility2)
            .frame(width: 320).padding(16).foregroundStyle(.white).background(Color.purple)
        let renderer = ImageRenderer(content: content)
        let image = try #require(renderer.nsImage)
        #expect(image.size.width == 352 && image.size.height > 200)
        if let folder = ProcessInfo.processInfo.environment["DJCONNECT_FORECAST_ARTIFACT_DIR"] {
            let directory = URL(fileURLWithPath: folder)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let tiff = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("forecast-" + language + ".png"))
        }
    }
}
#endif

#if canImport(DJConnectUI) && canImport(SwiftUI)
@Test(.isolatedClientResources) @MainActor
func forecastInitialPresentationWaitsForCurrentContextRead() {
    func context(authority: UUID = UUID(), phase: ScenePhase = .active) -> SessionForecastContent.RefreshContext {
        .init(scope: nil, ownerEpoch: UUID(), ownerReady: true, authority: authority,
              recovering: false, unavailable: false, phase: phase)
    }
    let first = context()
    var progress = SessionForecastContent.ReadProgress()
    #expect(progress.showsLoading(context: first, canRead: true, readInFlight: false),
            "First paint precedes .task and must not announce an unconfirmed failure")
    #expect(progress.showsLoading(context: first, canRead: true, readInFlight: true))
    progress.completedContext = first
    #expect(!progress.showsLoading(context: first, canRead: true, readInFlight: false),
            "A completed read without visible content must still show unavailable")
    #expect(progress.showsLoading(context: first, canRead: true, readInFlight: true),
            "Manual and periodic retries retain their loading state")
    #expect(progress.showsLoading(context: context(), canRead: true, readInFlight: false),
            "A changed owner or authority context needs its own read")
    #expect(!progress.showsLoading(context: context(), canRead: false, readInFlight: false),
            "An inadmissible read must not leave the panel loading forever")
    #expect(!progress.showsLoading(context: context(phase: .background), canRead: true, readInFlight: false))
    #expect(SessionForecastContent.ReadProgress().showsLoading(context: first, canRead: true, readInFlight: false),
            "Re-entering Horizon starts fresh even after an earlier unavailable result")
}
#endif

@Test func forecastTransportRetentionNeverUsesOpaqueTextOrTLSAuthenticationErrors() {
    for code: URLError.Code in [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost, .dnsLookupFailed] {
        #expect(DJConnectError.network(message: "typed fixture", code: code).isTransientConnectivityFailure)
    }
    for code: URLError.Code in [.userAuthenticationRequired, .userCancelledAuthentication, .serverCertificateUntrusted,
                                .serverCertificateHasBadDate, .secureConnectionFailed, .cancelled, .unknown] {
        #expect(!DJConnectError.network(message: "timed out", code: code).isTransientConnectivityFailure)
    }
    #expect(!DJConnectError.network(message: "The connection timed out").isTransientConnectivityFailure)
    #expect(!DJConnectError.authStale(statusCode: 401, message: nil).isTransientConnectivityFailure)
}

#if os(macOS)
@MainActor private final class ContributionLayoutFrames {
    var artwork: NSView?
    var detail: NSView?
}
private struct ContributionLayoutProbe: NSViewRepresentable {
    let frames: ContributionLayoutFrames
    let artwork: Bool
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        if artwork { frames.artwork = view } else { frames.detail = view }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}
@Test(.isolatedClientResources, arguments: [320.0, 768, 1024])
@MainActor func contributionArtworkAndTextUseSeparateColumns(_ width: Double) async throws {
    for type in ["music_announcement", "album", "artist", "music_origin"] {
        let frames = ContributionLayoutFrames()
        let content = SessionContributionColumns(horizontal: true) {
            Color.indigo.frame(width: 72, height: 72)
                .background(ContributionLayoutProbe(frames: frames, artwork: true))
        } detail: {
            Text(type + ": " + String(repeating: "Long contribution wraps naturally. ", count: 8))
                .font(.title3).fixedSize(horizontal: false, vertical: true)
                .background(ContributionLayoutProbe(frames: frames, artwork: false))
        }.frame(width: width).environment(\.dynamicTypeSize, .accessibility2)
        let host = NSHostingView(rootView: content)
        let height = max(100, ceil(host.fittingSize.height))
        let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: width, height: height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(30))
        host.layoutSubtreeIfNeeded()
        let art = try #require(frames.artwork), detail = try #require(frames.detail)
        let artRect = art.convert(art.bounds, to: host), textRect = detail.convert(detail.bounds, to: host)
        #expect(textRect.minX >= artRect.maxX + 15)
        #expect(textRect.width > 0 && textRect.maxX <= width + 1)
        let textTop = host.isFlipped ? textRect.minY : textRect.maxY
        let artTop = host.isFlipped ? artRect.minY : artRect.maxY
        #expect(abs(textTop - artTop) < 1)
    }
}
#endif

struct HorizonPreviewProducerFixture: Decodable {
    struct Case: Decodable {
        struct Context: Decodable {
            let original_source_wall: Double
            let session_id: String
            let playback: DJConnectSessionPlayback
        }
        struct Owner: Decodable { let horizon_moment: DJConnectHorizonMomentPreview }
        let locale: String
        let persona: String
        let context: Context
        let owner_payload: Owner
        func runtime() -> DJConnectSessionRuntime {
            var broadcast = DJConnectBroadcastState(session: .init(sessionID: context.session_id, runtimeState: "active", selectedMood: "groove", locale: locale),
                planner: .init(planningState: "fixture", planningHorizonMinutes: 10, currentDirection: "fixture"),
                sessionFlow: .init(flowID: "fixture-flow", planningHorizonMinutes: 10, createdAt: "fixture", items: []))
            broadcast.playback = context.playback; broadcast.horizonMoment = owner_payload.horizon_moment
            return .init(sessionID: context.session_id, room: "Fixture", selectedMood: "groove", musicBackend: "spotify", runtimeState: "active", startedAt: "fixture", planner: .init(planningHorizonMinutes: 10), broadcast: broadcast)
        }
    }
    let scope: String
    let cases: [Case]
}
func horizonPreviewProducerCases() throws -> [HorizonPreviewProducerFixture.Case] {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/horizon-preview-core-producer-v1.json")
    let data = try Data(contentsOf: url)
    #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == "f6514e4c6ed24c3b5bf434f18918ad4081e88644bb4dfe846657abe61815dc77")
    return try JSONDecoder().decode(HorizonPreviewProducerFixture.self, from: data).cases
}
@Test(.isolatedClientResources) func upNextPreviewKeepsActualProducerTextAndOriginalExpiryAcrossAllLocalesAndPersonas() throws {
    let cases = try horizonPreviewProducerCases()
    #expect(cases.count == 20 && Set(cases.map(\.locale)).count == 5 && Set(cases.map(\.persona)).count == 4)
    for item in cases {
        let preview = item.owner_payload.horizon_moment, runtime = item.runtime()
        let now = Date(timeIntervalSince1970: item.context.original_source_wall + 1)
        #expect(preview.structurallyValid && preview.isVisible(session: runtime, at: now))
        #expect(preview.expiry == Date(timeIntervalSince1970: 1_800_000_020))
        let originalExpiry = try #require(preview.expiry)
        #expect(!preview.isVisible(session: runtime, at: originalExpiry))
        var paused = runtime; paused.broadcast.playback?.state = "paused"
        #expect(!preview.isVisible(session: paused, at: now))
        var changed = runtime; changed.broadcast.playback?.itemID = "other-current-recording"
        #expect(!preview.isVisible(session: changed, at: now))
        var ended = runtime; ended.runtimeState = "ended"
        #expect(!preview.isVisible(session: ended, at: now))
        var other = runtime; other.sessionID = "other-session"
        #expect(!preview.isVisible(session: other, at: now))
        #expect(!preview.isVisible(session: runtime, positionMS: 100_000, at: now))
        #expect(!preview.isVisible(session: runtime, positionMS: 300_000, at: now))
        var cleared = runtime.broadcast; cleared.clearNativeAuthority()
        #expect(cleared.horizonMoment == nil)
        #expect(!runtime.broadcast.djMoments.contains { $0.id == preview.preview_id })
    }
}
#if os(macOS)
@Test(.isolatedClientResources) @MainActor func upNextActualNativeRendererWrapsProducerTextWithoutCreatingActions() async throws {
    // Standalone XCTest host lacks the application's asset catalogue. Load the
    // exact shipping mark; this does not replace provider artwork or metadata.
    let markURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Apps/Shared/Assets.xcassets/SpotifyAttribution.imageset/Spotify_Full_Logo_RGB_White.png")
    let needsMark = NSImage(named: "SpotifyAttribution") == nil
    let mark = try #require(NSImage(contentsOf: markURL))
    if needsMark { #expect(mark.setName("SpotifyAttribution")) }
    defer { if needsMark { mark.setName(nil) } }
    for item in try horizonPreviewProducerCases() {
        for width: CGFloat in [320, 768] {
            let view = SessionHorizonMomentContent(preview: item.owner_payload.horizon_moment, mood: "groove", language: item.locale, artworkURL: nil)
                .frame(width: width).environment(\.dynamicTypeSize, .accessibility2).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view.foregroundStyle(.white).background(Color(red: 0.08, green: 0.06, blue: 0.18)))
            let rendered = try #require(renderer.nsImage)
            #expect(rendered.size.width == width)
            #expect(rendered.size.height > 100 && rendered.size.height < 2000)
            let tiff = try #require(rendered.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            if let folder = ProcessInfo.processInfo.environment["DJCONNECT_HORIZON_PREVIEW_ARTIFACT_DIR"] {
                let directory = URL(fileURLWithPath: folder)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("up-next-\(item.locale)-\(item.persona)-\(Int(width)).png"))
            }
        }
    }
}
#endif
