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
    preferences.updatePresentation(for: tv) { $0.matte = "matching" }
    let data = try JSONEncoder().encode(preferences)
    let saved = try JSONDecoder().decode(DJConnectCanvasPreferences.self, from: data)
    #expect(saved.isValid)
    #expect(saved.presentation_overrides?.keys.contains(frame.id) == false)
    #expect(saved.presentation(for: tv).matte == "matching")
    #expect(saved.presentation(for: tv).show_track_title)
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
                "composition", "matte", "cadence", "cadence.track", "cadence.900",
                "cadence.1800", "cadence.3600", "forget", "cleanup_remote",
                "state.delivered_unknown", "uncertain", "tv_permission", "not_offered"] {
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
