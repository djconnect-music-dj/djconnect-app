import Foundation
import Testing
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
