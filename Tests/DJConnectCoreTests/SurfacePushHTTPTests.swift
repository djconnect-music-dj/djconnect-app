import Foundation
import CryptoKit
import Testing
@testable import DJConnectCore

private final class SurfacePushHTTPWire: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) static private var requests: [URLRequest] = []
    nonisolated(unsafe) static private var response = Data()
    nonisolated(unsafe) static private var code = 200
    nonisolated(unsafe) static private var headerPatch: [String:String] = [:]
    static func setup(_ data: Data, code: Int = 200, headers: [String:String] = [:]) {
        lock.withLock { requests = [];response = data;Self.code = code;headerPatch = headers }
    }
    static var captured: [URLRequest] { lock.withLock { requests } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open(); defer { stream.close() }; var bytes = Data(); var buffer = [UInt8](repeating:0,count:2048)
            while true {
                let count = stream.read(&buffer,maxLength:buffer.count)
                if count <= 0 { break }; bytes.append(contentsOf:buffer.prefix(count))
                if bytes.count > 16384 { break }
            }
            captured.httpBody = bytes
        }
        let (body,code,patch) = Self.lock.withLock { Self.requests.append(captured);return (Self.response,Self.code,Self.headerPatch) }
        var headers = ["Content-Type":"application/json; charset=utf-8","Cache-Control":"no-store","Referrer-Policy":"no-referrer","X-Content-Type-Options":"nosniff"]
        headers.merge(patch) { _, new in new }
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,headerFields:headers)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:body);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private func pushHTTPFixture(_ kind: String) throws -> [String:Any] {
    let url = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/surface-push-core-12675bc-http.json")
    let root = try #require(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
    return try #require((root["cases"] as? [[String:Any]])?.first { row in
        row["kind"] as? String == kind && row["status"] as? Int == 200
    })
}
private func pushHTTPConfig() -> URLSessionConfiguration {
    let c = URLSessionConfiguration.ephemeral;c.protocolClasses = [SurfacePushHTTPWire.self]
    c.httpAdditionalHeaders = ["Authorization":"Bearer forbidden-ambient-app-token","X-Ambient-Identity":"forbidden"]
    return c
}
@Suite(.serialized) @MainActor struct SurfacePushHTTPTests {
    private func client() -> DJConnectClient {
        let s = URLSession(configuration:pushHTTPConfig())
        return DJConnectClient(baseURL:URL(string:"http://127.0.0.1:18766")!,
            identity:.init(deviceID:"djconnect-ios-ABCDEF123456",deviceName:"Fixture",clientType:.ios,firmware:"4.0.0",platform:.ios),
            tokenStore:DJConnectInMemoryTokenStore(token:"paired-fixture-token"),session:s)
    }
    @Test(.isolatedClientResources) func retainedWidgetHTTPSeparatesPairedAndBackgroundAuthority() async throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/retained-widget-background-core-wire.json")
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let examples = try #require(fixture["examples"] as? [String: [String: Any]])
        var authorized = try #require(examples["authorized"])
        var read = try #require(examples["read"])
        var receipt = try #require(read["registration"] as? [String: Any])
        let projection = try #require(read["passive_session"] as? [String: Any])
        let session = try #require(projection["session_id"] as? String)
        let binding = try #require(projection["binding_id"] as? String)
        let generation = try #require(projection["generation"] as? String)
        let originalGrant = DJConnectRetainedWidgetGrant(id: "fixture-grant", sessionID: session,
            bindingID: binding, generation: generation)
        let asOf = try #require(projection["as_of"] as? String)
        let observed = try #require(DJConnectHistoryEntry.date(asOf))
        let expiry = Int64(Date().addingTimeInterval(60).timeIntervalSince1970 * 1000)
        authorized["expires_at_ms"] = expiry
        receipt["expires_at_ms"] = expiry
        read["registration"] = receipt
        let original = try JSONDecoder().decode(DJConnectSurfacePushReceipt.self,
            from: JSONSerialization.data(withJSONObject: receipt))
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))

        SurfacePushHTTPWire.setup(try JSONSerialization.data(withJSONObject: authorized))
        let grant = try await client().authorizeRetainedWidget(sessionID: session, grantID: "fixture-grant",
            original: original, originalDeadline: deadline, isCurrent: { true })
        let paired = try #require(SurfacePushHTTPWire.captured.first)
        #expect(paired.url?.lastPathComponent == "retained-authorize")
        #expect(paired.value(forHTTPHeaderField: "Authorization") == "Bearer paired-fixture-token")
        let pairedBytes = try #require(paired.httpBody)
        let pairedBody = try #require(JSONSerialization.jsonObject(with: pairedBytes) as? [String: Any])
        #expect(Set(pairedBody.keys) == ["contract_version", "device_id", "client_type", "session_id", "registration_id", "grant_id"])

        let transport = try DJConnectSurfaceBackgroundHTTP(baseURL: URL(string: "http://127.0.0.1:18766")!,
            configuration: pushHTTPConfig(), nowMS: { Int64(observed.timeIntervalSince1970 * 1000) + 1 })
        SurfacePushHTTPWire.setup(try JSONSerialization.data(withJSONObject: read))
        let accepted = try await transport.retainedWidgetRead(grant, original: original,
            grant: originalGrant, originalDeadline: deadline, isCurrent: { true })
        #expect(accepted.session_id == session)
        let background = try #require(SurfacePushHTTPWire.captured.first)
        #expect(background.url?.lastPathComponent == "retained-read")
        #expect(background.value(forHTTPHeaderField: "Authorization") == "Bearer " + grant.credential)
        #expect(background.value(forHTTPHeaderField: "X-DJConnect-Device-ID") == nil)
        let backgroundBytes = try #require(background.httpBody)
        let backgroundBody = try #require(JSONSerialization.jsonObject(with: backgroundBytes) as? [String: Any])
        #expect(Set(backgroundBody.keys) == ["contract_version", "registration_id"])

        let shortlyAfterObservation = Int64(observed.timeIntervalSince1970 * 1000) + 10
        var expiringReceipt = receipt
        expiringReceipt["expires_at_ms"] = shortlyAfterObservation
        var expiringRead = read
        expiringRead["registration"] = expiringReceipt
        let expiring = try JSONDecoder().decode(DJConnectRetainedWidgetRead.self,
            from: JSONSerialization.data(withJSONObject: expiringRead))
        let receiptDeadline = Date(timeIntervalSince1970: Double(shortlyAfterObservation) / 1000)
        #expect(expiring.matches(expiring.registration, grant: originalGrant, now: receiptDeadline.addingTimeInterval(-0.001)))
        #expect(expiring.passive_session.isCurrent(at: receiptDeadline))
        #expect(!expiring.matches(expiring.registration, grant: originalGrant, now: receiptDeadline))

        for field in ["binding_id", "generation"] {
            var substituted = read
            var wrongProjection = projection
            wrongProjection[field] = "different-grant-coordinate"
            substituted["passive_session"] = wrongProjection
            SurfacePushHTTPWire.setup(try JSONSerialization.data(withJSONObject: substituted))
            await #expect(throws: DJConnectError.self) {
                try await transport.retainedWidgetRead(grant, original: original,
                    grant: originalGrant, originalDeadline: deadline, isCurrent: { true })
            }
        }
        receipt["revision"] = original.revision + 1
        read["registration"] = receipt
        SurfacePushHTTPWire.setup(try JSONSerialization.data(withJSONObject: read))
        await #expect(throws: DJConnectError.self) {
            try await transport.retainedWidgetRead(grant, original: original,
                grant: originalGrant, originalDeadline: deadline, isCurrent: { true })
        }
        SurfacePushHTTPWire.setup(Data())
        await #expect(throws: DJConnectError.self) {
            try await transport.retainedWidgetRead(grant, original: original,
                grant: originalGrant, originalDeadline: ContinuousClock.now, isCurrent: { true })
        }
        #expect(SurfacePushHTTPWire.captured.isEmpty)
    }
    @Test(.isolatedClientResources) func backgroundReadUsesOnlyOriginalSeparateCredentialAndClosedRequest() async throws {
        let fixture = try pushHTTPFixture("read"), registered = try pushHTTPFixture("register")
        let registration = try JSONDecoder().decode(DJConnectSurfacePushResponse.self,from:JSONSerialization.data(withJSONObject:registered["response_body"]!))
        let read = try #require(registration.background_read)
        SurfacePushHTTPWire.setup(try JSONSerialization.data(withJSONObject:fixture["response_body"]!))
        let wire = try DJConnectSurfaceBackgroundHTTP(baseURL:URL(string:"http://127.0.0.1:18766")!,configuration:pushHTTPConfig(),nowMS:{0})
        let result = try await wire.read(read,isCurrent:{true})
        #expect(result.success && result.registration.registration_id == read.registration_id)
        let request = try #require(SurfacePushHTTPWire.captured.first)
        #expect(SurfacePushHTTPWire.captured.count == 1)
        #expect(request.url?.path == "/api/djconnect/v1/push/surface/read" && request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField:"Authorization") == "Bearer " + read.credential)
        #expect(request.value(forHTTPHeaderField:"X-Ambient-Identity") == nil)
        #expect(request.value(forHTTPHeaderField:"X-DJConnect-Device-ID") == nil)
        let requestBytes = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with:requestBytes) as? [String:Any])
        #expect(Set(object.keys) == ["contract_version","registration_id"])
    }
    @Test(.isolatedClientResources) func pairedRegistrationMatchesOriginalCoreRequestWithoutRetryOrRoleCoercion() async throws {
        let fixture = try pushHTTPFixture("register"), raw = try #require(fixture["request_json"] as? [String:Any])
        let c = client()
        let request = try #require(DJConnectSurfacePushRequest(identity:c.identity,sessionID:raw["session_id"] as! String,
            operationID:raw["operation_id"] as! String,platform:"ios",osVersion:"26.0",target:raw["target"] as! [String:String],
            token:Data(repeating:0xaa,count:32),environment:"sandbox",consent:raw["consent"] as! [String:Bool],expected:nil))
        let object = try #require(JSONSerialization.jsonObject(with:request.bytes) as? NSDictionary)
        #expect(object.isEqual(to:raw))
        SurfacePushHTTPWire.setup(try JSONSerialization.data(withJSONObject:fixture["response_body"]!))
        #expect(try await c.registerSurfacePush(request,isCurrent:{true}).success)
        #expect(SurfacePushHTTPWire.captured.count == 1)
        #expect(SurfacePushHTTPWire.captured[0].value(forHTTPHeaderField:"Authorization") == "Bearer paired-fixture-token")
        #expect(SurfacePushHTTPWire.captured[0].value(forHTTPHeaderField:"X-Ambient-Identity") == nil)
        SurfacePushHTTPWire.setup(Data("{}".utf8),code:503)
        await #expect(throws:(any Error).self) { _ = try await c.registerSurfacePush(request,isCurrent:{true}) }
        #expect(SurfacePushHTTPWire.captured.count == 1)
        SurfacePushHTTPWire.setup(Data("{}".utf8))
        await #expect(throws:(any Error).self) { _ = try await c.registerSurfacePush(request,isCurrent:{false}) }
        #expect(SurfacePushHTTPWire.captured.isEmpty)
    }
    @Test(.isolatedClientResources) func contextAndStatusAreMetadataOnlyAndDoNotRegister() async throws {
        let c = client()
        for kind in ["context","status"] {
            let fixture = try pushHTTPFixture(kind)
            SurfacePushHTTPWire.setup(try JSONSerialization.data(withJSONObject:fixture["response_body"]!))
            if kind == "context" { _ = try await c.surfacePushContext(sessionID:"synthetic-session",isCurrent:{true}) }
            else {
                let r = fixture["response_body"] as! [String:Any], registration = r["registration"] as! [String:Any]
                _ = try await c.surfacePushStatus(sessionID:"synthetic-session",registrationID:registration["registration_id"] as! String,isCurrent:{true})
            }
            #expect(SurfacePushHTTPWire.captured.count == 1 && SurfacePushHTTPWire.captured[0].url?.lastPathComponent == kind)
        }
    }
    @Test(.isolatedClientResources) func responsePrivacyEncodingAndSizeFailuresNeverRetry() async throws {
        let c = client()
        for patch in [["Cache-Control":"public"],["Content-Encoding":"gzip"],["Content-Type":"text/html"],["Referrer-Policy":"unsafe-url"]] {
            SurfacePushHTTPWire.setup(Data("{}".utf8),headers:patch)
            await #expect(throws:(any Error).self) { _ = try await c.surfacePushContext(sessionID:"synthetic-session",isCurrent:{true}) }
            #expect(SurfacePushHTTPWire.captured.count == 1)
        }
        SurfacePushHTTPWire.setup(Data(repeating:32,count:65537))
        await #expect(throws:(any Error).self) { _ = try await c.surfacePushContext(sessionID:"synthetic-session",isCurrent:{true}) }
        #expect(SurfacePushHTTPWire.captured.count == 1)
    }
    @Test(.isolatedClientResources) func strictWireRejectsDecodedDuplicateKeysAmbiguousNumbersAndDeepObjects() throws {
        for body in [#"{"success":true,"\u0073uccess":false}"#, #"{"x":{"id":1,"id":2}}"#, #"{"x":[{"id":1,"id":2}]}"#,
                     #"{"x":9007199254740992}"#, #"{"x":1.0}"#, #"{"x":1e2}"#, #"{"x":01}"#, #"{"x":"\ud800"}"#,
                     String(repeating:"{\"x\":",count:18)+"null"+String(repeating:"}",count:18)] {
            #expect(throws:(any Error).self) { try DJConnectSurfacePushJSON.validate(Data(body.utf8)) }
        }
        for kind in ["register","context","status","read","revoke"] {
            try DJConnectSurfacePushJSON.validate(JSONSerialization.data(withJSONObject:pushHTTPFixture(kind)["response_body"]!))
        }
    }
}

@MainActor private final class SurfaceHTTPAuthority { var current = true }
extension SurfacePushHTTPTests {
    @Test(.isolatedClientResources) func closedRequestRejectsUnconsentedRolesStartAndInvalidNativeTargets() throws {
        let raw = try #require(pushHTTPFixture("register")["request_json"] as? [String:Any])
        let identity = DJConnectIdentity(deviceID:"djconnect-ios-ABCDEF123456",deviceName:"Fixture",clientType:.ios,firmware:"4.0.0",platform:.ios)
        let target = raw["target"] as! [String:String], consent = raw["consent"] as! [String:Bool]
        func request(_ t: [String:String], _ c: [String:Bool], platform: String = "ios", version: String = "26.0", token: Data = Data(repeating:1,count:32)) -> DJConnectSurfacePushRequest? {
            .init(identity:identity,sessionID:raw["session_id"] as! String,operationID:raw["operation_id"] as! String,
                  platform:platform,osVersion:version,target:t,token:token,environment:"sandbox",consent:c,expected:nil)
        }
        #expect(request(target,consent) != nil)
        #expect(request(target,consent,version:"25.0") == nil)
        #expect(request(target,consent,platform:"watchos") == nil)
        #expect(request(target,consent,token:Data([1])) == nil)
        for (flag,value) in [("external_push_content",true),("allow_remote_start",true),("background_read",false),("os_snapshot_cache",false)] {
            var c = consent;c[flag] = value;#expect(request(target,c) == nil)
        }
        let activity = ["instance_id":"original-presentation","app_bundle_id":"dev.djconnect.ios","activity_id":"original-activity","attributes_type":"DJConnectSessionLiveActivityAttributes"]
        #expect(request(activity,consent) == nil) // Widget consent never becomes Activity export consent.
        var export = consent; export["locked_display"] = true;export["external_push_content"] = true
        #expect(request(activity,export) != nil) // Wire support only, not admitted operator rights.
        var start = activity;start.removeValue(forKey:"activity_id")
        #expect(request(start,export) == nil)
    }
    @Test(.isolatedClientResources) func backgroundReadCannotDispatchAfterWithdrawalOrOriginalExpiry() async throws {
        let raw = try pushHTTPFixture("register")
        let registration = try JSONDecoder().decode(DJConnectSurfacePushResponse.self,from:JSONSerialization.data(withJSONObject:raw["response_body"]!))
        let read = try #require(registration.background_read)
        SurfacePushHTTPWire.setup(Data("{}".utf8))
        let expired = try DJConnectSurfaceBackgroundHTTP(baseURL:URL(string:"http://127.0.0.1:18766")!,configuration:pushHTTPConfig(),nowMS:{read.expires_at_ms})
        await #expect(throws:(any Error).self) { _ = try await expired.read(read,isCurrent:{true}) }
        #expect(SurfacePushHTTPWire.captured.isEmpty)
        let wire = try DJConnectSurfaceBackgroundHTTP(baseURL:URL(string:"http://127.0.0.1:18766")!,configuration:pushHTTPConfig(),nowMS:{0})
        let authority = SurfaceHTTPAuthority()
        await #expect(throws:(any Error).self) {
            _ = try await wire.read(read,isCurrent:{ let captured = authority.current;authority.current = false;return captured })
        }
        #expect(SurfacePushHTTPWire.captured.isEmpty)
    }
    @Test(.isolatedClientResources) func actualIOSActivityDefaultCodecKeepsOriginalDatesAndOmitsUnadmittedRichContent() throws {
        let file = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/activity-surface-default-ios-20261023.json")
        let root = try #require(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
        #expect(root["native_effects"] as? Bool == false)
        let rows = try #require(root["rows"] as? [[String:Any]])
        #expect(rows.count == 3)
        var originalExpiry: Date?
        for row in rows {
            let bytes = Data((try #require(row["default_encoded_utf8"] as? String)).utf8)
            let snapshot = try JSONDecoder().decode(DJConnectSessionSurfaceSnapshot.self,from:bytes)
            #expect(snapshot.rich == nil && row["external_content_admitted"] as? Bool == false)
            #expect(snapshot.expiresAt.timeIntervalSince(snapshot.observedAt) == 120)
            if let originalExpiry { #expect(snapshot.expiresAt == originalExpiry) } else { originalExpiry = snapshot.expiresAt }
            #expect(Int64(floor(snapshot.expiresAt.timeIntervalSince1970 * 1000)) == row["expires_at_ms"] as? Int64)
        }
    }
    @Test(.isolatedClientResources) func v2HTTPJoinsOriginalContextAndRegistrationWithoutLegacyFallback() async throws {
        let fixture = try pushHTTPFixture("register")
        let raw = try #require(fixture["request_json"] as? [String:Any])
        let sessionID = try #require(raw["session_id"] as? String)
        let operationID = try #require(raw["operation_id"] as? String)
        let target = try #require(raw["target"] as? [String:String])
        let consent = try #require(raw["consent"] as? [String:Bool])
        let request = try #require(DJConnectSurfacePushRequest(
            identity:.init(deviceID:"djconnect-ios-ABCDEF123456",deviceName:"Fixture",clientType:.ios,firmware:"4.0.0",platform:.ios),
            sessionID:sessionID, operationID:operationID, platform:"ios",osVersion:"26.0",target:target,
            token:Data(repeating:1,count:32),environment:"sandbox",consent:consent,expected:nil))
        let attempt = try #require(DJConnectSurfacePushContextAttempt(original:request,installation:"http://127.0.0.1:18766",ownerEpoch:UUID()))
        let expiry = Int64(Date().timeIntervalSince1970 * 1000) + 3_600_000
        let handle = "djcctx_" + String(repeating:"A",count:43), purpose = "djcpref_" + String(repeating:"A",count:43)
        let context: [String:Any] = ["success":true,"contract_version":2,"available":true,"context_handle":handle,
            "operation_id":attempt.operationID,"purpose_ref":purpose,"expires_at_ms":expiry,
            "context_expires_at_ms":attempt.startedMS+30_000,"cache_policy":"private,no-store"]
        SurfacePushHTTPWire.setup(try JSONSerialization.data(withJSONObject:context))
        let c = client(), continuation = try await c.prepareSurfacePush(attempt,isCurrent:{true})
        let originalContextRequest = try #require(SurfacePushHTTPWire.captured.first)
        #expect(originalContextRequest.url?.path == "/api/djconnect/v1/push/surface/context")
        #expect(originalContextRequest.httpBody == attempt.contextBytes)
        var response = try #require(fixture["response_body"] as? [String:Any])
        response["contract_version"] = 2; response["context_handle"] = handle
        response["operation_id"] = attempt.operationID; response["purpose_ref"] = purpose
        var registration = try #require(response["registration"] as? [String:Any])
        registration["expires_at_ms"] = expiry; response["registration"] = registration
        var read = try #require(response["background_read"] as? [String:Any])
        read["expires_at_ms"] = expiry; response["background_read"] = read
        SurfacePushHTTPWire.setup(try JSONSerialization.data(withJSONObject:response))
        let ack = try await c.registerSurfacePush(continuation,isCurrent:{true})
        #expect(ack.success && ack.background_read?.expires_at_ms == expiry)
        #expect(SurfacePushHTTPWire.captured.count == 1)
        let registerRequest = try #require(SurfacePushHTTPWire.captured.first)
        #expect(registerRequest.url?.path == "/api/djconnect/v1/push/surface/register")
        #expect(registerRequest.httpBody == continuation.registerBytes)
        do { _ = try await c.registerSurfacePush(continuation,isCurrent:{false}); Issue.record("Withdrawn continuation dispatched") }
        catch {}
        #expect(SurfacePushHTTPWire.captured.count == 1)
        let expiredAttempt = try #require(DJConnectSurfacePushContextAttempt(original:request,
            installation:"http://127.0.0.1:18766",ownerEpoch:UUID(),previousPurpose:nil,
            nowMS:Int64(Date().timeIntervalSince1970 * 1000)-31_000,
            monotonicNow:ContinuousClock.now.advanced(by:.seconds(-31))))
        do { _ = try await c.prepareSurfacePush(expiredAttempt,isCurrent:{true}); Issue.record("Expired original context attempt dispatched") }
        catch {}
        #expect(SurfacePushHTTPWire.captured.count == 1)
    }

}

extension SurfacePushHTTPTests {
    @Test(.isolatedClientResources) func selectedWatchWidgetRequestKeepsOwnIdentityAndClosedCanonicalTarget() throws {
        let raw = try #require(pushHTTPFixture("register")["request_json"] as? [String: Any])
        let consent = try #require(raw["consent"] as? [String: Bool])
        let identity = DJConnectIdentity(deviceID: "djconnect-watchos-ABCDEF123456", deviceName: "Watch fixture", clientType: .watchos, firmware: "4.1.0", platform: .watchos)
        let target = ["instance_id": "watch-own-instance", "app_bundle_id": "dev.djconnect.ios.watch",
            "extension_bundle_id": "dev.djconnect.ios.watch.complications", "widget_kind": "DJConnectComplication"]
        func request(_ target: [String: String], version: String = "26.0") -> DJConnectSurfacePushRequest? {
            .init(identity: identity, sessionID: raw["session_id"] as! String, operationID: raw["operation_id"] as! String,
                platform: "watchos", osVersion: version, target: target, token: Data(repeating: 1, count: 32),
                environment: "sandbox", consent: consent, expected: nil)
        }
        let selected = try #require(request(target))
        let body = try #require(JSONSerialization.jsonObject(with: selected.bytes) as? [String: Any])
        #expect(body["client_type"] as? String == "watchos" && body["platform"] as? String == "watchos")
        #expect(body["target"] as? [String: String] == target)
        #expect(request(target, version: "25.0") == nil)
        var phone = target; phone["app_bundle_id"] = "dev.djconnect.ios"
        #expect(request(phone) == nil)
        var alias = target; alias["widget_kind"] = "DJConnectNowPlayingComplication"
        #expect(request(alias) == nil)
    }
}

// Synthetic paired HTTP only: these cases qualify consent sequencing, not
// App Attest, an issuer/clock grant, native SDK enrollment or provider delivery.
private final class OrdinaryWidgetConsentWire: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fixtures: [String: OrdinaryWidgetConsentFixture] = [:]
    static func install(_ fixture: OrdinaryWidgetConsentFixture) { lock.withLock { fixtures[fixture.host] = fixture } }
    static func remove(_ fixture: OrdinaryWidgetConsentFixture) { _ = lock.withLock { fixtures.removeValue(forKey: fixture.host) } }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".ordinary-widget.test") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let host = request.url?.host, let fixture = Self.lock.withLock({ Self.fixtures[host] }) else { return }
        do {
            let reply = try fixture.reply(request)
            let headers = ["Content-Type": "application/json", "Cache-Control": "no-store", "Referrer-Policy": "no-referrer", "X-Content-Type-Options": "nosniff"]
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: reply.0, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.1); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
private final class OrdinaryWidgetConsentFixture: @unchecked Sendable {
    let host = UUID().uuidString.lowercased()+".ordinary-widget.test"
    let scenario: String
    let operation = UUID()
    private let lock = NSLock()
    private var calls: [URLRequest] = []
    private var live = true
    init(_ scenario: String) { self.scenario = scenario }
    var current: Bool { lock.withLock { live } }
    var requests: [URLRequest] { lock.withLock { calls } }
    func reply(_ request: URLRequest) throws -> (Int, Data) {
        var request = request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }; var bytes = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
            while true { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; bytes.append(buffer, count: count); if bytes.count > 4096 { throw DJConnectError.invalidResponse } }
            request.httpBody = bytes
        }
        let count = lock.withLock { calls.append(request); return calls.count }
        if scenario == "owner", request.httpMethod == "POST" { lock.withLock { live = false } }
        if scenario == "lost", count == 2 { throw URLError(.networkConnectionLost) }
        if scenario == "auth", request.httpMethod == "POST" { return (401, Data()) }
        if scenario == "conflict", request.httpMethod == "POST" { return (409, Data()) }
        let post = request.httpMethod == "POST"
        let readback = !post && count > 1
        var payload: [String: Any] = ["contract_version": 1, "enabled": count > 1, "revision": count == 1 ? 0 : 1]
        if post { payload["operation_id"] = operation.uuidString.lowercased() }
        if readback && ["withdrawn", "conflict"].contains(scenario) { payload["enabled"] = false; payload["revision"] = 2 }
        if readback && scenario == "mismatch" { payload["enabled"] = false }
        return (200, try JSONSerialization.data(withJSONObject: payload))
    }
    func client() -> DJConnectClient {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [OrdinaryWidgetConsentWire.self]
        return DJConnectClient(baseURL: URL(string: "https://"+host)!,
            identity: .init(deviceID: "djconnect-ios-ABCDEF123456", deviceName: "Synthetic fixture", clientType: .ios, firmware: "4.1.0", platform: .ios),
            tokenStore: DJConnectInMemoryTokenStore(token: "synthetic-ordinary-device-token"), session: URLSession(configuration: configuration))
    }
}
@Test(.isolatedClientResources, arguments: ["committed", "withdrawn", "mismatch", "conflict", "auth", "owner", "lost"])
@MainActor func ordinaryWidgetConsentRequiresIndependentCurrentReadback(_ scenario: String) async throws {
    let fixture = OrdinaryWidgetConsentFixture(scenario)
    OrdinaryWidgetConsentWire.install(fixture); defer { OrdinaryWidgetConsentWire.remove(fixture) }
    let client = fixture.client()
    let current: @MainActor @Sendable () -> Bool = { fixture.current }
    let initial = try await client.readWidgetPushConsent(isCurrent: current)
    #expect(!initial.enabled && initial.revision == 0)
    var confirmed = false
    do {
        let ack = try await client.confirmWidgetPushConsent(enabled: true, operationID: fixture.operation,
            expectedRevision: initial.revision, isCurrent: current)
        confirmed = ack.enabled && ack.revision == 1
    } catch { }
    #expect(confirmed == (scenario == "committed"))
    if scenario == "lost" {
        // A lost write reply cannot mint a new operation or effect. Explicit
        // recovery resubmits the original idempotent intent and verifies GET.
        let recovered = try await client.confirmWidgetPushConsent(enabled: true, operationID: fixture.operation,
            expectedRevision: initial.revision, isCurrent: current)
        #expect(recovered.enabled && recovered.revision == 1)
    }
    let calls = fixture.requests
    #expect(calls.allSatisfy { $0.url?.path == "/api/djconnect/v1/push/native/consent/widgetkit" })
    #expect(calls.first?.httpMethod == "GET")
    for call in calls where call.httpMethod == "POST" {
        let data: Data
        if let body = call.httpBody { data = body }
        else if let stream = call.httpBodyStream {
            stream.open(); defer { stream.close() }; var bytes = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
            while true { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; bytes.append(buffer, count: count) }
            data = bytes
        } else { throw DJConnectError.invalidResponse }
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["operation_id"] as? String == fixture.operation.uuidString.lowercased())
        #expect(body["expected_revision"] as? Int == 0)
    }
    if scenario == "committed" { #expect(calls.map(\.httpMethod) == ["GET", "POST", "GET"]) }
}

@Test(.isolatedClientResources, arguments: ["production", "ha-dev", "hash", "extra", "expired"])
func ordinaryWidgetChallengeBindsExactProductionAudienceAndTranscript(_ mutation: String) throws {
    // Deliberately synthetic API challenge. A decoder pass is DATA, never an
    // Apple attestation, enrolled key, signed app tuple or native permission.
    let now: Int64 = 1_800_000_000_000
    let operation = "12345678-1234-4234-8234-123456789abc"
    let audience = mutation == "ha-dev" ? "djc-native-push-ha-dev/1" : "djc-native-push/1"
    let nonce = String(repeating: "A", count: 43)
    let expiry = now + (mutation == "expired" ? -1 : 60_000)
    let identifiers = ["api-installation", "credential", "challenge", "pair-generation"]
    let digests = (1...4).map { String(repeating: String($0), count: 64) }
    let transcript: [Any] = ["djc-native-pair-witness/1", audience, "POST", "/v1/push/native/key/register",
        "widget-first-key", operation, identifiers[0], identifiers[1], identifiers[2], nonce, expiry, 0, identifiers[3]] + digests
    let hash = Data(SHA256.hash(data: try JSONSerialization.data(withJSONObject: transcript, options: [.withoutEscapingSlashes])))
    var object: [String: Any] = ["contract_version": 1, "api_audience": audience, "operation_id": operation,
        "challenge_nonce": nonce, "expires_at_ms": expiry, "expected_key_revision": 0,
        "client_data_hash_b64": mutation == "hash" ? Data(repeating: 0, count: 32).base64EncodedString() : hash.base64EncodedString(),
        "api_installation_id": identifiers[0], "install_credential_id": identifiers[1], "challenge_id": identifiers[2], "pairing_generation": identifiers[3],
        "pair_binding": digests[0], "owner_binding": digests[1], "device_binding": digests[2], "core_key_thumbprint": digests[3]]
    if mutation == "extra" { object["approved"] = true }
    var accepted = false
    do {
        let challenge = try DJConnectClient.WidgetFirstKeyChallenge.parse(JSONSerialization.data(withJSONObject: object),
            nowMS: now, requestedUptime: 100, uptime: 101, pairingBinding: Data(repeating: 1, count: 32))
        #expect(challenge.clientDataHash == hash && challenge.isCurrent(nowMS: now + 1, uptime: 102))
        accepted = true
    } catch { }
    #expect(accepted == (mutation == "production"))
}

extension SurfacePushHTTPTests {
    @Test(.isolatedClientResources, arguments: ["prepared", "operation", "session", "extra", "version", "state", "duplicate", "bad-uuid", "cancelled"])
    func widgetPurposePreparationACKIsClosedMetadataAndNeverStartsContext(_ scenario: String) async throws {
        let operation = scenario == "bad-uuid" ? "12345678-1234-4234-8234-123456789abc" : "12345678-1234-7234-8234-123456789abc"
        var reply: [String: Any] = ["contract_version": 1, "state": "prepared", "operation_id": operation, "session_id": "model-original-session"]
        if scenario == "operation" { reply["operation_id"] = "12345678-1234-7234-8234-123456789abd" }
        if scenario == "session" { reply["session_id"] = "different-session" }
        if scenario == "extra" { reply["native_clock_permission"] = true }
        if scenario == "version" { reply["contract_version"] = 3 }
        if scenario == "state" { reply["state"] = "registered" }
        var bytes = try JSONSerialization.data(withJSONObject: reply)
        if scenario == "duplicate" { bytes = Data(("{\"state\":\"prepared\"," + String(decoding: bytes.dropFirst(), as: UTF8.self)).utf8) }
        SurfacePushHTTPWire.setup(bytes)
        var accepted = false
        do {
            try await client().prepareNativeWidgetSurface(sessionID: "model-original-session", operationID: operation,
                isCurrent: { scenario != "cancelled" })
            accepted = true
        } catch { }
        #expect(accepted == (scenario == "prepared"))
        let calls = SurfacePushHTTPWire.captured
        #expect(calls.count == (["bad-uuid", "cancelled"].contains(scenario) ? 0 : 1))
        #expect(calls.allSatisfy { $0.url?.path == "/api/djconnect/v1/push/surface/widget/prepare" && $0.httpMethod == "POST" })
        if let call = calls.first {
            let requestBytes = try #require(call.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: requestBytes) as? [String: Any])
            #expect(Set(body.keys) == ["contract_version", "operation_id", "device_id", "client_type", "session_id"])
            #expect(body["contract_version"] as? Int == 1 && body["operation_id"] as? String == operation)
            #expect(body["client_type"] as? String == "ios")
            #expect(call.value(forHTTPHeaderField: "Authorization") == "Bearer paired-fixture-token")
            #expect(call.value(forHTTPHeaderField: "X-Ambient-Identity") == nil)
        }
        // No response path here constructs a context clock, role owner,
        // registration, native SDK candidate or background-read credential.
    }
}
