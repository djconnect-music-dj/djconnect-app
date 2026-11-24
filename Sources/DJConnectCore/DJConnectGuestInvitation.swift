import Foundation

/// Untrusted, single-use locator. Parsing does not join or confer owner authority.
/// Keep only in RAM; never encode into preferences, diagnostics or navigation history.
public struct DJConnectGuestInvitation: Sendable, Equatable {
    public let origin: URL
    public let issuerEpoch: String
    public let invitationID: String
    private let invitationSecret: String

    public static func parse(_ raw: String) throws -> Self {
        guard raw.utf8.count <= 4096, raw.utf8.allSatisfy({ $0 > 32 && $0 < 127 }),
              validPercentEscapes(raw), let parts = URLComponents(string: raw),
              parts.scheme == "djconnect", parts.host == "join", parts.path.isEmpty,
              parts.user == nil, parts.password == nil, parts.port == nil, parts.query == nil,
              let fragment = parts.percentEncodedFragment, !fragment.isEmpty, fragment.utf8.count <= 2048 else {
            throw DJConnectError.invalidResponse
        }
        var query = URLComponents(); query.percentEncodedQuery = fragment
        let items = query.queryItems ?? []
        let expected: Set<String> = ["v", "ha_url", "issuer_epoch", "invitation_id", "invitation_secret"]
        guard items.count == expected.count, Set(items.map(\.name)) == expected,
              items.allSatisfy({ $0.value != nil }) else { throw DJConnectError.invalidResponse }
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
        guard values["v"] == "1", let originText = values["ha_url"], originText.utf8.count <= 1024,
              originText.utf8.allSatisfy({ $0 > 32 && $0 < 127 && $0 != 92 }),
              let originParts = URLComponents(string: originText), originParts.scheme == "https",
              let host = originParts.host, !host.isEmpty, originParts.user == nil, originParts.password == nil,
              originParts.path.isEmpty || originParts.path == "/", originParts.query == nil, originParts.fragment == nil,
              let origin = originParts.url,
              let epoch = values["issuer_epoch"], token(epoch, count: 43),
              let id = values["invitation_id"], token(id, count: 32),
              let secret = values["invitation_secret"], token(secret, count: 43) else { throw DJConnectError.invalidResponse }
        var canonical = originParts
        canonical.host = host.lowercased(); canonical.path = ""
        if canonical.port == 443 { canonical.port = nil }
        guard let canonicalText = canonical.string,
              originText == canonicalText || originText == canonicalText + "/" else { throw DJConnectError.invalidResponse }
        return Self(origin: origin, issuerEpoch: epoch, invitationID: id, invitationSecret: secret)
    }

    /// Redeem at most once after explicit confirmation, through the guest-only transport.
    public func redemptionBody() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["contract_version": 1,
            "issuer_epoch": issuerEpoch, "invitation_id": invitationID, "invitation_secret": invitationSecret])
    }

    private static func token(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
    private static func validPercentEscapes(_ raw: String) -> Bool {
        let bytes = Array(raw.utf8)
        func hex(_ value: UInt8) -> Bool { (48...57).contains(value) || (65...70).contains(value) || (97...102).contains(value) }
        for index in bytes.indices where bytes[index] == 37 {
            guard index + 2 < bytes.count, hex(bytes[index + 1]), hex(bytes[index + 2]) else { return false }
        }
        return true
    }
}
