import Foundation
import Testing
@testable import DJConnectUI
@testable import DJConnectCore

private func status(_ sequence: UInt64 = 1, _ state: String = "presenting", id: UUID,
                    session: String = "actual-fixture-session", presentation: String? = "silence",
                    lease: Int = 15000, extras: [String: Any] = [:]) throws -> Data {
    var object: [String: Any] = ["kind":"vibecast_status","version":1,
        "handoff_id":id.uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
        "session_id":session,"sequence":sequence,"state":state,"lease_ms":lease]
    if let presentation { object["presentation"] = presentation }
    for (key, value) in extras { object[key] = value }
    return try JSONSerialization.data(withJSONObject: object)
}

@Test func legacyCastConnectIsNeverPresentationAndOnlyCorrelatedSoftwareStatusQualifies() throws {
    let id = UUID(), channel = UUID()
    var lease = DJConnectLegacyCastStatusLease(handoffID:id,sessionID:"actual-fixture-session",channelID:channel,now:100)
    #expect(!lease.state.softwarePresentationConfirmed)
    let accepted1 = lease.receive(try status(id:id),channel:UUID(),now:101)
    #expect(!accepted1)
    let accepted2 = lease.receive(try status(id:UUID()),channel:channel,now:101)
    #expect(!accepted2)
    let accepted3 = lease.receive(try status(id:id,session:"another-session"),channel:channel,now:101)
    #expect(!accepted3)
    let accepted4 = lease.receive(try status(1,"receiver_ready",id:id,presentation:nil),channel:channel,now:102)
    #expect(accepted4)
    #expect(!lease.state.softwarePresentationConfirmed)
    let accepted5 = lease.receive(try status(2,"snapshot_accepted",id:id,presentation:nil),channel:channel,now:103)
    #expect(accepted5)
    #expect(!lease.state.softwarePresentationConfirmed)
    let accepted6 = lease.receive(try status(3,id:id),channel:channel,now:104)
    #expect(accepted6)
    #expect(lease.state == .presentingSilence)
}

@Test func legacyCastIncreasingSequenceAndExactOriginalHandshakeDeadline() throws {
    let id = UUID(), channel = UUID()
    var lease = DJConnectLegacyCastStatusLease(handoffID:id,sessionID:"actual-fixture-session",channelID:channel,now:100)
    let accepted7 = lease.receive(try status(1,"connecting",id:id,presentation:nil),channel:channel,now:110)
    #expect(accepted7)
    let accepted8 = lease.receive(try status(1,id:id),channel:channel,now:111)
    #expect(!accepted8)
    let accepted9 = lease.receive(try status(2,id:id),channel:channel,now:115)
    #expect(!accepted9)
    #expect(lease.state == .failed)
    let accepted10 = lease.receive(try status(3,id:id),channel:channel,now:116)
    #expect(!accepted10)
}

@Test func legacyCastHeartbeatExpiresAndLateStatusCannotRestoreIt() throws {
    let id = UUID(), channel = UUID()
    var lease = DJConnectLegacyCastStatusLease(handoffID:id,sessionID:"actual-fixture-session",channelID:channel,now:100)
    let accepted11 = lease.receive(try status(id:id),channel:channel,now:101)
    #expect(accepted11)
    let accepted12 = lease.tick(now:115.999)
    #expect(accepted12)
    let accepted13 = lease.tick(now:116)
    #expect(!accepted13)
    let accepted14 = lease.receive(try status(2,id:id),channel:channel,now:116.001)
    #expect(!accepted14)
    #expect(!lease.state.softwarePresentationConfirmed)
}

@Test func legacyCastRecoveringWithdrawsSuccessWithoutDeadlineRenewal() throws {
    let id = UUID(), channel = UUID()
    var lease = DJConnectLegacyCastStatusLease(handoffID:id,sessionID:"actual-fixture-session",channelID:channel,now:100)
    let accepted15 = lease.receive(try status(id:id),channel:channel,now:101)
    #expect(accepted15)
    let accepted16 = lease.receive(try status(2,"recovering",id:id,presentation:nil),channel:channel,now:105)
    #expect(accepted16)
    #expect(!lease.state.softwarePresentationConfirmed)
    let accepted17 = lease.receive(try status(3,"recovering",id:id,presentation:nil),channel:channel,now:119)
    #expect(accepted17)
    let accepted18 = lease.receive(try status(4,id:id),channel:channel,now:120)
    #expect(!accepted18)
    #expect(lease.state == .failed)
}

@Test func legacyCastUnknownFieldsVersionsLeasesAndPresentationAreRejected() throws {
    let id = UUID(), channel = UUID()
    let bad: [[String: Any]] = [["version":2],["broadcast_token":"never-accepted"],["lease_ms":15001],["lease_ms":14999],
        ["lease_ms":0],["presentation":"invented"],["reason":"raw provider message"],["sequence":true]]
    for mutation in bad {
        var lease = DJConnectLegacyCastStatusLease(handoffID:id,sessionID:"actual-fixture-session",channelID:channel,now:100)
        let accepted19 = lease.receive(try status(id:id,extras:mutation),channel:channel,now:101)
        #expect(!accepted19)
        #expect(!lease.state.softwarePresentationConfirmed)
    }
}

@Test func legacyCastEndStopInvalidationAndClockRollbackAreTerminal() throws {
    for state in ["ended","stopped","error"] {
        let id = UUID(), channel = UUID()
        var lease = DJConnectLegacyCastStatusLease(handoffID:id,sessionID:"actual-fixture-session",channelID:channel,now:100)
        let accepted20 = lease.receive(try status(1,state,id:id,presentation:nil),channel:channel,now:101)
        #expect(accepted20)
        let accepted21 = lease.receive(try status(2,id:id),channel:channel,now:102)
        #expect(!accepted21)
    }
    let id = UUID(), channel = UUID()
    var lease = DJConnectLegacyCastStatusLease(handoffID:id,sessionID:"actual-fixture-session",channelID:channel,now:100)
    lease.invalidate()
    let accepted22 = lease.receive(try status(id:id),channel:channel,now:101)
    #expect(!accepted22)
    var rolled = DJConnectLegacyCastStatusLease(handoffID:id,sessionID:"actual-fixture-session",channelID:channel,now:100)
    let accepted23 = rolled.tick(now:99)
    #expect(!accepted23)
    let accepted24 = rolled.receive(try status(id:id),channel:channel,now:101)
    #expect(!accepted24)
}

@Test func legacyCastStrictHTTPSOriginDoesNotAcceptBootstrapOrGuestLocators() {
    for bad in ["http://ha.example","https://user:password@ha.example","https://ha.example/path",
                "https://ha.example?x=1","https://ha.example#invitation_secret=private",
                "https://ha.example\\@other.example","https://ha.example /", "https://"] {
        #expect(DJConnectLegacyCastContract.origin(bad) == nil)
    }
    #expect(DJConnectLegacyCastContract.origin("https://ha.example:8443/") == "https://ha.example:8443")
}

@Test func legacyCastCapabilityAndHandoffForwardOnlyExistingReadOnlyFields() throws {
    let raw: [String: Any] = ["success":true,"session_id":"actual-fixture-session",
        "broadcast_token":"nonredeemable-synthetic-token",
        "capabilities":["view_broadcast":true,"owner_controls":false,"audience_signals":true]]
    let cap = try JSONDecoder().decode(DJConnectLegacyCastContract.Capability.self,from:JSONSerialization.data(withJSONObject:raw))
    let id = UUID()
    let data = try cap.handoff(origin:"https://ha.example",sessionID:"actual-fixture-session",id:id)
    let message = try #require(JSONSerialization.jsonObject(with:data) as? [String: Any])
    #expect(Set(message.keys) == ["kind","version","ha_url","session_id","broadcast_token","status_version","handoff_id"])
    #expect(message["status_version"] as? Int == 1)
    #expect((message["handoff_id"] as? String)?.count == 32)
    #expect(throws: DJConnectLegacyCastContract.Error.self) {
        try cap.handoff(origin:"https://ha.example",sessionID:"different-session",id:id)
    }
    let invalidCapabilities: [[String: Any]] = [["view_broadcast":false,"owner_controls":false],
        ["view_broadcast":true,"owner_controls":true],["view_broadcast":true]]
    #expect(!String(reflecting: cap).contains("nonredeemable-synthetic-token"))
    for capabilities in invalidCapabilities {
        var bad = raw; bad["capabilities"] = capabilities
        #expect(throws: (any Swift.Error).self) {
            try JSONDecoder().decode(DJConnectLegacyCastContract.Capability.self,from:JSONSerialization.data(withJSONObject:bad))
        }
    }
}

@Test @MainActor func legacyCastOwnerFenceIsCallerOriginalNotGoogleDeviceIdentity() throws {
    var allowed = true
    let owner = try DJConnectLegacyCastOwner(sessionID:"actual-fixture-session",haOrigin:"https://ha.example",
        isCurrent:{ allowed },capability:{ throw DJConnectLegacyCastContract.Error.unavailable })
    #expect(owner.isCurrent())
    allowed = false
    #expect(!owner.isCurrent())
    #expect(throws: DJConnectLegacyCastContract.Error.self) {
        try DJConnectLegacyCastOwner(sessionID:"actual-fixture-session",haOrigin:"https://ha.example",
            isCurrent:{false},capability:{ throw DJConnectLegacyCastContract.Error.unavailable })
    }
}


@Test func legacyCastDuplicateAndEscapedAliasStatusKeysFailLosslessly() throws {
    let id = UUID(), channel = UUID()
    let valid = try #require(String(data: status(id:id), encoding: .utf8))
    for duplicate in [#""state":"presenting""#, #""sequence":2"#,
                      #""handoff_id":"00000000000000000000000000000000""#,
                      #""st\u0061te":"presenting""#] {
        var lease = DJConnectLegacyCastStatusLease(handoffID:id,sessionID:"actual-fixture-session",channelID:channel,now:100)
        let duplicateBody = Data((String(valid.dropLast()) + "," + duplicate + "}").utf8)
        let accepted = lease.receive(duplicateBody,channel:channel,now:101)
        #expect(!accepted)
        #expect(!lease.state.softwarePresentationConfirmed)
    }
}

@Test func legacyCastCancelledLaunchWaitsForExactSDKObject() {
    final class SDKObject {}
    let manager = SDKObject(), otherManager = SDKObject(), started = SDKObject(), unrelated = SDKObject()
    var fence = DJConnectLegacyCastLaunchFence()
    let reserved = fence.reserve(manager: manager, deviceID: "actual-sdk-device-id")
    #expect(reserved)
    fence.cancel()
    let successor = fence.reserve(manager: manager, deviceID: "next-sdk-device-id")
    #expect(!successor)
    #expect(!fence.shouldEnd(manager: manager, currentSession: unrelated))
    let wrongManager = fence.willStart(manager: otherManager, deviceID: "actual-sdk-device-id", session: started)
    #expect(!wrongManager)
    let wrongDevice = fence.willStart(manager: manager, deviceID: "Bonjour-friendly-name", session: started)
    #expect(!wrongDevice)
    let actual = fence.willStart(manager: manager, deviceID: "actual-sdk-device-id", session: started)
    #expect(actual)
    #expect(fence.shouldEnd(manager: manager, currentSession: started))
    #expect(!fence.shouldEnd(manager: manager, currentSession: unrelated))
    #expect(!fence.shouldEnd(manager: otherManager, currentSession: started))
    fence.terminal(manager: manager, session: unrelated)
    #expect(fence.reserved)
    fence.terminal(manager: manager, session: started)
    #expect(!fence.reserved)
    let next = fence.reserve(manager: manager, deviceID: "next-sdk-device-id")
    #expect(next)
    fence.terminal(manager: manager, session: started)
    #expect(fence.reserved)
    #expect(!fence.shouldEnd(manager: manager, currentSession: started))
}


private final class CastOwnerWire: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: Data] = [:]
    nonisolated(unsafe) private static var requests: [URLRequest] = []
    static func configure(_ value: [String: Data]) { lock.withLock { responses = value; requests = [] } }
    static var calls: [URLRequest] { lock.withLock { requests } }
    static func replace(_ path: String, _ data: Data) { lock.withLock { responses[path] = data } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Self.lock.withLock { Self.requests.append(request); return Self.responses[request.url!.path] }
        if let data {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type":"application/json","Cache-Control":"no-store"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } else { client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)) }
    }
    override func stopLoading() {}
}
private final class CastFixtureBundle: NSObject {}
@MainActor private final class CastModelSender: DJConnectLegacyCastSending {
    var devices = [DJConnectLegacyCastDevice(id: "actual-sdk-identifier", name: "Screen")]
    var state: DJConnectLegacyCastState = .idle
    var onChange: (@MainActor () -> Void)?
    var stops = 0, suspends = 0, capabilityCalls = 0, completed = false
    var owner: DJConnectLegacyCastOwner?
    var hold = false
    func startDiscovery() { onChange?() }
    func stopDiscovery() {}
    func connect(to deviceID: String, owner: DJConnectLegacyCastOwner) async throws {
        self.owner = owner; state = .connecting; onChange?()
        while hold { try await Task.sleep(for: .milliseconds(1)) }
        _ = try await owner.capability(); capabilityCalls += 1
        state = .receiverReady; completed = true; onChange?()
    }
    func suspendObservation() { suspends += 1; state = .recovering; onChange?() }
    func stopView() { stops += 1; state = .stopped; onChange?() }
    func invalidate() { stopView() }
}

@Test(.isolatedClientResources, arguments: ["background-before-read", "background-after-read", "history", "authority", "session", "demo", "stop", "pairing", "origin", "token"])
@MainActor func legacyCastActualModelIngressSeparatesSuspensionFromOriginalWithdrawal(_ mode: String) async throws {
    func fixture(_ name: String) throws -> [String: Any] {
        let url = Bundle(for: CastFixtureBundle.self).url(forResource: name, withExtension: "json") ??
            URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Fixtures/" + name + ".json")
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    // Existing real producer Session/history bytes wrapped in a synthetic HTTPS
    // URLProtocol boundary. The SDK sender is modeled: no physical CAF claim.
    let session = try #require(fixture("session-history-active-session-before-auth-failure")["response"])
    let history = try #require(fixture("session-history-producer-receipt")["later_historical_answer"])
    let sessionObject = try #require(session as? [String: Any])
    let sourceSession = try #require((sessionObject["session"] ?? sessionObject["active_session"]) as? [String: Any])
    let sid = try #require((sourceSession["session_id"] ?? sourceSession["id"]) as? String)
    let cap: [String: Any] = ["success":true,"session_id":sid,"broadcast_token":String(repeating:"x",count:32),
        "capabilities":["view_broadcast":true,"owner_controls":false]]
    let caps: [String: Any] = ["capabilities":["session_conversation_history":true,"session_flow_text_search":true],
        "contract_versions":["session_conversation_history":1,"session_flow_text_search":1]]
    CastOwnerWire.configure(try ["/api/djconnect/v1/session/active":JSONSerialization.data(withJSONObject:session),
        "/api/djconnect/v1/ask_dj/history":JSONSerialization.data(withJSONObject:history),
        "/api/djconnect/v1/capabilities":JSONSerialization.data(withJSONObject:caps),
        "/api/djconnect/v1/transport/context":JSONSerialization.data(withJSONObject:[
            "success":true,"contract_version":1,"ha_install_id":"synthetic-install",
            "requires_authenticated_tls":true,"operation_lifetime_ms":300000,
            "operation_epoch":"synthetic-transport-epoch","server_time_ms":1000,
            "transport_security":["mode":"authenticated_tls"]]),
        "/api/djconnect/v1/session/broadcast/token":JSONSerialization.data(withJSONObject:cap)])
    let suite = "cast-owner-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName:suite))
    defaults.set("https://ha.example",forKey:"DJConnectHomeAssistantURL")
    defaults.set("https://ha.example",forKey:"DJConnectHALocalURL")
    let store = DJConnectInMemoryTokenStore(token:"synthetic-original-pair")
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CastOwnerWire.self]
    let model = DJConnectAppModel(defaults:defaults,tokenStore:store,urlSession:URLSession(configuration:config),startBackgroundTasks:false)
    defer { model.stopLegacyCast(); model.markInactiveSession(); defaults.removePersistentDomain(forName:suite) }
    model.pairingStatus = .paired
    #expect(await model.refreshActiveDJSession())
    model.stopSessionBroadcast()
    await model.sessionHistory.prepare()
    defaults.set("synthetic-install",forKey:"DJConnectHAInstallID")
    let sender = CastModelSender(); sender.hold = mode == "background-before-read"
    model.attachLegacyCastSender(sender)
    #expect(model.canConnectLegacyCast)
    model.connectLegacyCast(deviceID:"bonjour-unqualified")
    #expect(sender.owner == nil)
    model.connectLegacyCast(deviceID:"actual-sdk-identifier")
    for _ in 0..<500 {
        if sender.owner != nil && (sender.hold || sender.completed) { break }
        try await Task.sleep(for:.milliseconds(1))
    }
    let owner = try #require(sender.owner)
    if mode.hasPrefix("background") || mode == "history" {
        let reads = CastOwnerWire.calls.filter { $0.url?.path.hasSuffix("/broadcast/token") == true }.count
        if mode == "history" { model.sessionHistory.suspend(preservingVoicePreference:true) }
        else { model.markInactiveSession() }
        sender.hold = false
        try await Task.sleep(for:.milliseconds(5))
        #expect(sender.suspends >= 1 && sender.stops == 0)
        #expect(model.legacyCastNeedsConfirmation)
        #expect(CastOwnerWire.calls.filter { $0.url?.path.hasSuffix("/broadcast/token") == true }.count == reads)
        #expect(!owner.isCurrent())
    } else {
        let calls = CastOwnerWire.calls.filter { $0.url?.path.hasSuffix("/broadcast/token") == true }
        #expect(calls.count == 1 && calls.first?.httpMethod == "POST")
        #expect(calls.first?.value(forHTTPHeaderField:"Authorization") == "Bearer synthetic-original-pair")
        // Reusing the same original owner closure cannot fetch a second token.
        do { _ = try await owner.capability(); Issue.record("original token read replayed") } catch {}
        #expect(CastOwnerWire.calls.filter { $0.url?.path.hasSuffix("/broadcast/token") == true }.count == 1)
        switch mode {
        case "pairing": model.pairingStatus = .unpaired
        case "demo": model.isDemoMode = true
        case "origin": model.homeAssistantURL = "https://other.example"
        case "token": try store.saveToken("different-actual-pair"); model.bindProfileDJSettings(active:true)
        case "authority": #expect(model.sessionHistory.withdrawAuthority(for:DJConnectError.authStale(statusCode:401,message:nil)))
        case "session":
            CastOwnerWire.replace("/api/djconnect/v1/session/active",try JSONSerialization.data(withJSONObject:["success":true,"active_session":NSNull(),"session":NSNull()]))
            #expect(!model.isLoadingDJSession)
            #expect(model.canRefreshSessionHistory)
            let accepted = await model.refreshActiveDJSession()
            #expect(accepted)
            #expect(model.activeDJSession == nil)
        default: model.stopLegacyCast()
        }
        #expect(sender.stops >= 1 && !owner.isCurrent())
    }
}
