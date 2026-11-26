import Foundation
import Testing
@testable import DJConnectCore

private func canvasFixture() throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fixtures/music-canvas-v1.json"))
}

@Test func musicCanvasConsumesThreeIndependentTargetsAndPortraitProfile() throws {
    let snapshot = try JSONDecoder().decode(DJConnectCanvasSnapshot.self, from: canvasFixture())
    #expect(snapshot.isValid && snapshot.targets.count == 3)
    let portrait = try #require(snapshot.targets.first { $0.adapter == "switchbot" })
    #expect(portrait.screen.orientation == "portrait" && portrait.screen.height == 1600)
    #expect(!portrait.remote_cleanup && !portrait.preview_available)
    #expect(snapshot.preferences.cadence == "1800")
}

@Test func musicCanvasScreenPresentationKeepsTheSwitchBotDefaultIndependent() throws {
    let snapshot = try JSONDecoder().decode(DJConnectCanvasSnapshot.self, from: canvasFixture())
    let frame = try #require(snapshot.targets.first { $0.adapter == "switchbot" })
    let tv = try #require(snapshot.targets.first { $0.adapter == "samsung" })
    var preferences = snapshot.preferences
    preferences.matte = "contrast"
    preferences.show_track_title = true
    preferences.presentation_overrides = [:]
    #expect(preferences.presentation(for: frame).matte == "off")
    #expect(!preferences.presentation(for: frame).show_track_title)
    #expect(preferences.presentation(for: tv).show_track_title)
    preferences.updatePresentation(for: tv) {
        $0.matte = "matching"
        $0.composition = "full"
        $0.cadence = "track"
        $0.matte_size = "large"
    }
    let data = try JSONEncoder().encode(preferences)
    let saved = try JSONDecoder().decode(DJConnectCanvasPreferences.self, from: data)
    #expect(saved.isValid)
    #expect(saved.presentation_overrides?.keys.contains(frame.id) == false)
    #expect(saved.presentation(for: tv).matte == "matching")
    #expect(saved.presentation(for: tv).show_track_title)
    #expect(saved.presentation(for: tv).composition == "full")
    #expect(saved.presentation(for: tv).cadence == "track")
    #expect(saved.presentation(for: tv).matte_size == "large")
    #expect(saved.presentation(for: frame).composition == nil)
    #expect(saved.presentation(for: frame).cadence == nil)
    #expect(snapshot.per_screen_composition_and_cadence == nil)
    #expect(snapshot.per_screen_matte_size == nil)
    #expect(snapshot.frame_matching_matte == nil)
    #expect(saved.presentation(for: frame).matte_size == nil)
    preferences.updatePresentation(for: tv) { $0.matte_size = "unknown" }
    #expect(!preferences.isValid)
}

@Test func musicCanvasFrameMatteRoundTripsAsAnAdditiveMatchingOption() throws {
    let snapshot = try JSONDecoder().decode(DJConnectCanvasSnapshot.self, from: canvasFixture())
    let tv = try #require(snapshot.targets.first { $0.adapter == "samsung" })
    var preferences = snapshot.preferences
    preferences.presentation_overrides = [:]
    preferences.updatePresentation(for: tv) {
        $0.selectMatte(DJConnectCanvasPresentation.frameMatte)
        $0.frame_finish = "walnut"
    }

    let data = try JSONEncoder().encode(preferences)
    var saved = try JSONDecoder().decode(DJConnectCanvasPreferences.self, from: data)
    #expect(saved.isValid)
    #expect(saved.presentation(for: tv).matte == "matching")
    #expect(saved.presentation(for: tv).matteChoice == DJConnectCanvasPresentation.frameMatte)
    #expect(saved.presentation(for: tv).match_frame == true)
    #expect(saved.presentation(for: tv).frame_finish == "walnut")

    saved.updatePresentation(for: tv) { $0.selectMatte("matching") }
    #expect(saved.presentation(for: tv).match_frame == false)
    #expect(saved.presentation(for: tv).matteChoice == "matching")
    #expect(saved.presentation(for: tv).frame_finish == "walnut")
    saved.updatePresentation(for: tv) { $0.frame_finish = "unknown" }
    #expect(!saved.isValid)
}

@Test func musicCanvasReplacementPreviewRevisionIsOptionalAndBounded() throws {
    var raw = try #require(JSONSerialization.jsonObject(with: canvasFixture()) as? [String: Any])
    var targets = try #require(raw["targets"] as? [[String: Any]])
    let revision = String(repeating: "a", count: 64)
    targets[0]["artwork_request_pending"] = true
    targets[0]["artwork_preview_revision"] = revision
    raw["targets"] = targets
    let snapshot = try JSONDecoder().decode(DJConnectCanvasSnapshot.self,
        from: JSONSerialization.data(withJSONObject: raw))
    #expect(snapshot.isValid)
    #expect(snapshot.targets[0].artwork_request_pending == true)
    #expect(snapshot.targets[0].artwork_preview_revision == revision)
    #expect(snapshot.targets[1].artwork_request_pending == nil)
    var request = DJConnectCanvasRequest(device_id: "djconnect-ios-SYNTHETIC", client_type: "ios")
    request.target_id = snapshot.targets[0].id
    request.preview_revision = revision
    let body = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    #expect(Set(body.keys) == ["contract_version", "device_id", "client_type", "target_id", "preview_revision"])
    #expect(body["preview_revision"] as? String == revision)
}

@Test func musicCanvasPreviewRevisionIsOptionalAndRequiresAnAvailablePreview() throws {
    var raw = try #require(JSONSerialization.jsonObject(with: canvasFixture()) as? [String: Any])
    var targets = try #require(raw["targets"] as? [[String: Any]])
    let revision = String(repeating: "a", count: 64)
    targets[0]["preview_revision"] = revision
    for available in [true, false] {
        targets[0]["preview_available"] = available
        raw["targets"] = targets
        let snapshot = try JSONDecoder().decode(DJConnectCanvasSnapshot.self,
            from: JSONSerialization.data(withJSONObject: raw))
        #expect(snapshot.targets[0].preview_revision == revision)
        #expect(snapshot.targets[1].preview_revision == nil)
        #expect(snapshot.isValid == available)
    }
}

@Test(arguments: ["cadence", "composition", "matte", "cadence_overrides"])
func musicCanvasRejectsMalformedPreferences(field: String) throws {
    var raw = try #require(JSONSerialization.jsonObject(with: canvasFixture()) as? [String: Any])
    var prefs = try #require(raw["preferences"] as? [String: Any])
    prefs[field] = field == "cadence_overrides" ? ["foreign-target": "900"] : "unknown"
    raw["preferences"] = prefs
    let snapshot = try JSONDecoder().decode(DJConnectCanvasSnapshot.self,
        from: JSONSerialization.data(withJSONObject: raw))
    #expect(!snapshot.isValid)
}

@Test func musicCanvasClosedRequestOmitsProfileProviderAndUnrelatedFields() throws {
    let request = DJConnectCanvasRequest(device_id: "djconnect-ios-SYNTHETIC", client_type: "ios")
    let body = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    #expect(Set(body.keys) == ["contract_version", "device_id", "client_type"])
    var setup = request
    setup.binding = String(repeating: "a", count: 64)
    setup.operation_id = "00000000-0000-4000-8000-000000000001"
    setup.target_id = "switchbot:synthetic-p"
    setup.screen = .init(orientation: "portrait")
    let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(setup)) as? [String: Any])
    let screen = try #require(encoded["screen"] as? [String: Any])
    #expect(Set(screen.keys) == ["orientation"])
    #expect(encoded["patch"] == nil && encoded["cleanup_remote"] == nil)
}

@Test(arguments: ["nl", "en", "de", "fr", "es"])
func musicCanvasLocalizesTheEntirePanel(language: String) {
    for key in ["open", "description", "enabled", "screens", "provider_required",
                "composition", "matte", "frame", "cadence", "cadence.track", "cadence.900",
                "cadence.1800", "cadence.3600", "forget", "cleanup_remote",
                "state.delivered_unknown", "uncertain", "tv_permission", "not_offered",
                "new_artwork", "state.alternative_unchanged", "frame_finish"]
                + DJConnectCanvasPresentation.frameFinishes.map({ "frame_finish." + $0 }) {
        let full = "ui.canvas." + key
        let value = DJConnectLocalization.localized(key: full, language: language)
        #expect(!value.isEmpty && value != full)
    }
}

private final class CanvasWire: @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var wires: [String: CanvasWire] = [:]
    let host = UUID().uuidString.lowercased() + ".invalid"
    let fixture: Data
    let capability: Bool
    var requests: [(String, [String: Any])] = []
    init(fixture: Data, capability: Bool = true) {
        self.fixture = fixture; self.capability = capability
        Self.lock.withLock { Self.wires[host] = self }
    }
    func close() { Self.lock.withLock { _ = Self.wires.removeValue(forKey: host) } }
    func client() -> DJConnectClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CanvasURLProtocol.self]
        return DJConnectClient(baseURL: URL(string: "https://" + host)!,
            identity: .init(deviceID: "djconnect-ios-ABCDEF123456", deviceName: "Canvas fixture",
                            clientType: .ios, firmware: "4.1.0", platform: .ios),
            tokenStore: DJConnectInMemoryTokenStore(token: "synthetic-canvas-token"),
            session: URLSession(configuration: configuration))
    }
}
private final class CanvasURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        CanvasWire.lock.withLock { CanvasWire.wires[request.url?.host ?? ""] != nil }
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let wire = CanvasWire.lock.withLock({ CanvasWire.wires[request.url?.host ?? ""] }) else { return }
        let path = request.url!.path
        var bytes = request.httpBody ?? Data()
        if bytes.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 2048)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                bytes.append(contentsOf: buffer.prefix(count))
            }
        }
        let body = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] ?? [:]
        CanvasWire.lock.withLock { wire.requests.append((path, body)) }
        let data: Data
        if path.hasSuffix("/capabilities") {
            data = Data("{\"success\":true,\"capabilities\":{\"music_canvas\":\(wire.capability)},\"contract_versions\":{\"music_canvas\":1}}".utf8)
        } else if path.hasSuffix("/read") {
            data = wire.fixture
        } else if path.hasSuffix("/new_artwork") {
            data = (try? JSONSerialization.data(withJSONObject: [
                "success": true, "contract_version": 1, "state": "confirmed",
                "binding": body["binding"] ?? NSNull(), "operation_id": body["operation_id"] ?? NSNull(),
                "revision": body["expected_revision"] ?? NSNull(),
            ])) ?? Data()
        } else {
            data = Data(#"{"success":false,"error":"synthetic_failure"}"#.utf8)
        }
        let code = path.hasSuffix("/update") ? 503 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json", "Content-Length": String(data.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test(.isolatedClientResources) @MainActor
func musicCanvasWireReadsOnlyWithCapabilityAndDoesNotRetryAnUnknownWrite() async throws {
    let wire = CanvasWire(fixture: try canvasFixture())
    defer { wire.close() }
    let client = wire.client()
    let snapshot = try await client.musicCanvas()
    #expect(snapshot.isValid)
    var preferences = snapshot.preferences
    preferences.enabled = false
    do {
        _ = try await client.updateMusicCanvas(snapshot, preferences: preferences, operationID: UUID())
        Issue.record("Synthetic failed write accepted")
    } catch {}
    let requests = CanvasWire.lock.withLock { wire.requests }
    #expect(requests.map(\.0) == ["/api/djconnect/v1/capabilities",
        "/api/djconnect/v1/music_canvas/read", "/api/djconnect/v1/music_canvas/update"])
    #expect(Set(requests[1].1.keys) == ["contract_version", "device_id", "client_type"])
    #expect(requests[2].1["expected_revision"] as? Int == snapshot.revision)
    #expect(requests[2].1["binding"] as? String == snapshot.binding)
}

@Test(.isolatedClientResources) @MainActor
func musicCanvasMissingCapabilityCannotStartAnUnqualifiedRead() async throws {
    let wire = CanvasWire(fixture: try canvasFixture(), capability: false)
    defer { wire.close() }
    do {
        _ = try await wire.client().musicCanvas()
        Issue.record("Missing capability accepted")
    } catch {
        #expect((error as? DJConnectCanvasReadFailure) == .notOffered)
    }
    #expect(CanvasWire.lock.withLock { wire.requests.count } == 1)
}

@Test(.isolatedClientResources) @MainActor
func musicCanvasNewArtworkSendsOnlyTheSupportedScreenAndOperation() async throws {
    let rawFixture = try canvasFixture()
    let older = try JSONDecoder().decode(DJConnectCanvasSnapshot.self, from: rawFixture)
    var json = try #require(JSONSerialization.jsonObject(with: rawFixture) as? [String: Any])
    var targets = try #require(json["targets"] as? [[String: Any]])
    targets[0]["can_request_artwork"] = true
    json["targets"] = targets
    json["manual_artwork_refresh"] = true
    let wire = CanvasWire(fixture: try JSONSerialization.data(withJSONObject: json))
    defer { wire.close() }
    let client = wire.client()
    let snapshot = try await client.musicCanvas()
    let target = snapshot.targets[0].id
    let operation = UUID()
    await #expect(throws: DJConnectError.self) {
        try await client.requestNewMusicCanvasArtwork(older, targetID: target, operationID: operation)
    }
    let receipt = try await client.requestNewMusicCanvasArtwork(snapshot, targetID: target, operationID: operation)
    #expect(receipt.revision == snapshot.revision)
    let requests = CanvasWire.lock.withLock { wire.requests }
    let request = try #require(requests.last)
    #expect(requests.count == 3 && request.0.hasSuffix("/music_canvas/new_artwork"))
    #expect(Set(request.1.keys) == ["contract_version", "device_id", "client_type", "binding",
        "target_id", "operation_id", "expected_revision"])
    #expect(request.1["target_id"] as? String == target)
    #expect(request.1["operation_id"] as? String == operation.uuidString.lowercased())
}
