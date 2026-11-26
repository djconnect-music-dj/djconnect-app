import Foundation
import Testing
@testable import DJConnectCore

private func ownerContext(_ url: String, trust: String = "paired_owner_response", epoch: String = String(repeating: "A", count: 43)) throws -> DJConnectDisplayOwnerContext {
    let data = try JSONSerialization.data(withJSONObject: ["success": true, "contract_version": 1,
        "display_entry_url": url, "route_trust": trust, "issuer_epoch": epoch,
        "session_id": NSNull(), "limits": ["claim_seconds": 120]])
    return try JSONDecoder().decode(DJConnectDisplayOwnerContext.self, from: data)
}
@Test func rendezvousOwnerRouteRequiresFreshPairedOwnerContract() throws {
    #expect(try ownerContext("https://ha.example.com/djconnect/vibecast/display").isAdmissible)
    #expect(try !ownerContext("https://ha.example.com/djconnect/vibecast/display", trust: "qr").isAdmissible)
    #expect(try !ownerContext("https://ha.example.com/djconnect/vibecast/display", epoch: "old").isAdmissible)
}
@Test(arguments: ["http://ha.example.com/djconnect/vibecast/display", "https://ha.example.com:443/djconnect/vibecast/display",
    "https://user:password@ha.example.com/djconnect/vibecast/display", "https://127.0.0.1/djconnect/vibecast/display",
    "https://ha.local/djconnect/vibecast/display", "https://ha.example.com/djconnect/vibecast/display?token=x",
    "https://ha.example.com/djconnect/vibecast/display#x", "https://ha.example.com/djconnect/vibecast/%64isplay",
    "https://ha.example.com/djconnect/vibecast/display/", "https://xn--ha-9ia.example/djconnect/vibecast/display"])
func rendezvousOwnerRouteRejectsUntrustedDestinations(url: String) throws {
    #expect(try !ownerContext(url).isAdmissible)
}

@Test func displayShareCountdownUsesOriginalClocksAndShorterServerDeadline() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let formatter = ISO8601DateFormatter()
    let body: [String: Any] = ["success": true, "contract_version": 1,
        "display_entry_url": "https://ha.example.com/djconnect/vibecast/display",
        "route_trust": "paired_owner_response", "issuer_epoch": String(repeating: "A", count: 43),
        "share_id": String(repeating: "A", count: 43), "share_generation": 1,
        "expires_at": formatter.string(from: now.addingTimeInterval(14400)), "expires_in": 600.0]
    let context = try JSONDecoder().decode(DJConnectDisplayOwnerContext.self, from: JSONSerialization.data(withJSONObject: body))
    let lifetime = try #require(DJConnectDisplayShareLifetime(context: context, requestedAt: now, requestedUptime: 100))
    #expect(lifetime.remainingSeconds(now: now.addingTimeInterval(10), uptime: 110) == 590)
    // A wall-clock step back cannot grant extra monotonic lifetime.
    #expect(lifetime.remainingSeconds(now: now.addingTimeInterval(1), uptime: 120) == 580)
    #expect(lifetime.remainingSeconds(now: now.addingTimeInterval(1), uptime: 700) == nil)
    #expect(lifetime.remainingSeconds(now: now.addingTimeInterval(600), uptime: 101) == nil)
    #expect(lifetime.remainingSeconds(now: now.addingTimeInterval(-1), uptime: 101) == nil)
    #expect(lifetime.remainingSeconds(now: now, uptime: 99) == nil)
}

@Test func nativeGuestInvitationIsClosedAndDoesNotCarryAnOwnerBearer() throws {
    let epoch = String(repeating: "A", count: 43), id = String(repeating: "B", count: 32)
    let secret = String(repeating: "C", count: 43)
    let link = "djconnect://join#v=1&ha_url=https%3A%2F%2Fha.example.com&issuer_epoch=\(epoch)&invitation_id=\(id)&invitation_secret=\(secret)"
    let invitation = try DJConnectGuestInvitation.parse(link)
    #expect(invitation.origin.absoluteString == "https://ha.example.com")
    let publicQR = link.replacingOccurrences(of: "djconnect://join#", with: "https://vibecast.tv/join#")
    #expect(try DJConnectGuestInvitation.parse(publicQR) == invitation)
    let body = try #require(JSONSerialization.jsonObject(with: invitation.redemptionBody()) as? [String: Any])
    #expect(Set(body.keys) == ["contract_version", "issuer_epoch", "invitation_id", "invitation_secret"])
    for invalid in [link + "&v=1", link + "&guest_token=forbidden", link.replacingOccurrences(of: "https%3A", with: "http%3A"),
                    link.replacingOccurrences(of: "ha.example.com", with: "user%3Apassword%40ha.example.com"),
                    link.replacingOccurrences(of: "ha.example.com", with: "ha.example.com%2Fprivate"),
                    link.replacingOccurrences(of: "v=1", with: "v=2"), link + "%XX",
                    link.replacingOccurrences(of: "invitation_id=\(id)", with: "invitation_id=short"),
                    link.replacingOccurrences(of: "join#", with: "join?source=owner#")] {
        #expect(throws: (any Error).self) { try DJConnectGuestInvitation.parse(invalid) }
    }
}
