import Foundation
import CoreFoundation
import CryptoKit

/// Original SDK assertion custody and comparison DATA. None of these values is
/// a surface admission, clock witness, native target or restored read grant.
@MainActor enum WidgetReauthorizationOperation {
    struct Challenge: Codable, Sendable {
        let operationID: String
        let hash: Data
        let expiresAtMS: Int64
        let admittedAtMS: Int64
        let requestedUptime: TimeInterval
        let deadline: TimeInterval
        let originalResponse: Data
        func isCurrent(nowMS: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
                       uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
            nowMS >= admittedAtMS && nowMS < expiresAtMS && uptime >= requestedUptime && uptime < deadline
        }
        static func parse(_ data: Data, operationID: String, receipt: Data, nowMS: Int64,
                          requestedUptime: TimeInterval, uptime: TimeInterval) throws -> Self {
            try DJConnectSurfacePushJSON.validate(data)
            guard let object = try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  Set(object.keys) == ["contract_version","api_audience","operation_id","challenge","first_key_receipt","delegation","client_data_hash_b64"],
                  integer(object["contract_version"]) == 1, object["api_audience"] as? String == "djc-native-push/1",
                  object["operation_id"] as? String == operationID, uuidV7(operationID),
                  let challenge = object["challenge"] as? [String:Any],
                  Set(challenge.keys) == ["contract_version","api_audience","challenge_id","challenge_nonce","expires_at_ms","publication_operation_id","first_key_receipt_sha256","delegation_sha256"],
                  integer(challenge["contract_version"]) == 1, challenge["api_audience"] as? String == "djc-native-push/1",
                  let challengeID = challenge["challenge_id"] as? String,
                  challengeID.range(of:#"\A[A-Za-z0-9_-]{1,128}\z"#,options:.regularExpression) != nil,
                  let nonce = challenge["challenge_nonce"] as? String, DJConnectRendezvousQR.canonicalToken(nonce),
                  let publication = challenge["publication_operation_id"] as? String, uuidV7(publication),
                  let expiry = integer(challenge["expires_at_ms"]), nowMS >= 0, expiry > nowMS, expiry-nowMS <= 120_000,
                  requestedUptime.isFinite, requestedUptime >= 0, uptime.isFinite, uptime >= requestedUptime,
                  let returnedReceipt = object["first_key_receipt"] as? [String:Any],
                  let delegation = object["delegation"] as? [String:Any],
                  let encodedHash = object["client_data_hash_b64"] as? String,
                  let hash = Data(base64Encoded:encodedHash), hash.count == 32, hash.base64EncodedString() == encodedHash else {
                throw DJConnectError.invalidResponse
            }
            let returnedBytes = try canonical(returnedReceipt)
            let fields = try RendezvousFlatJSON.parse(receipt,maximumBytes:4096)
            guard Set(fields.keys) == ["contract_version","api_installation_id","install_credential_id","operation_id","pairing_generation","core_key_thumbprint","registry_generation","expires_at_ms","key_revision","state","transcript_sha256","apple_evidence_expires_at_ms","apple_status_expires_at_ms"],
                  try RendezvousFlatJSON.parse(returnedBytes,maximumBytes:4096) == fields,
                  challenge["first_key_receipt_sha256"] as? String == digest(returnedBytes),
                  challenge["delegation_sha256"] as? String == digest(try canonical(delegation)) else { throw DJConnectError.invalidResponse }
            guard fields["contract_version"] == .integer(1),fields["key_revision"] == .integer(1),fields["state"] == .string("registered"),
                  case let .integer(evidence)? = fields["apple_evidence_expires_at_ms"],
                  case let .integer(status)? = fields["apple_status_expires_at_ms"],
                  let policy = delegation["policy"] as? [String:Any],let policyEnd = integer(policy["original_grant_expires_at_ms"]),
                  expiry <= min(evidence,status,policyEnd) else { throw DJConnectError.invalidResponse }
            let transcript: [Any] = ["djc-installation-widget-reauthorization/1","POST",
                "/v1/push/native/installation/issuer/reauthorize/register",challenge,returnedReceipt,delegation]
            guard Data(SHA256.hash(data:try canonical(transcript))) == hash else { throw DJConnectError.invalidResponse }
            let deadline = min(requestedUptime+120,uptime+Double(expiry-nowMS)/1000)
            guard uptime < deadline else { throw DJConnectError.invalidResponse }
            return .init(operationID:operationID,hash:hash,expiresAtMS:expiry,admittedAtMS:nowMS,
                         requestedUptime:requestedUptime,deadline:deadline,originalResponse:data)
        }
    }
    enum Phase: String, Codable, Sendable { case challengeStarted, challengeReceived, assertionStarted, assertionReady, registrationStarted, ready }
    struct Record: Codable, Sendable {
        let operationID: String
        let keyIdentifier: String
        let receipt: Data
        var phase: Phase
        var challenge: Challenge?
        var proof: Data?
    }
    struct Ports {
        let load: () throws -> Record?
        let save: (Record) throws -> Void
        let ownerCurrent: () -> Bool
        let current: (Challenge) -> Bool
        let challenge: () async throws -> Challenge
        let assertion: (String, Data) async throws -> Data
        let register: (Challenge, String, Data) async throws -> Void
        let status: (Challenge) async throws -> Void
    }
    enum Failure: Error { case closed, unknown, invalidRecord }
    private static func check(_ ports: Ports, _ challenge: Challenge? = nil) throws {
        try Task.checkCancellation()
        guard ports.ownerCurrent(), challenge.map(ports.current) ?? true else { throw Failure.closed }
    }
    static func run(operationID: String, key: String, receipt: Data, ports: Ports) async throws {
        try check(ports)
        guard uuidV7(operationID), let bytes = Data(base64Encoded:key), bytes.count == 32,
              bytes.base64EncodedString() == key, (1...4096).contains(receipt.count) else { throw Failure.invalidRecord }
        var record: Record
        if let old = try ports.load() {
            guard old.operationID == operationID, old.keyIdentifier == key, old.receipt == receipt,
                  let challenge = old.challenge, challenge.operationID == operationID,
                  [.registrationStarted,.ready].contains(old.phase) else { throw Failure.unknown }
            try check(ports,challenge)
            try await ports.status(challenge)
            try check(ports,challenge)
            record = old; record.phase = .ready; record.proof = nil; try ports.save(record)
            return
        }
        record = .init(operationID:operationID,keyIdentifier:key,receipt:receipt,phase:.challengeStarted)
        try ports.save(record) // Before a remote nonce/publication may commit.
        let challenge = try await ports.challenge()
        guard challenge.operationID == operationID else { throw Failure.invalidRecord }
        record.challenge = challenge; record.phase = .challengeReceived; try ports.save(record)
        try check(ports,challenge)
        record.phase = .assertionStarted; try ports.save(record)
        let proof = try await ports.assertion(key,challenge.hash)
        guard (1...16384).contains(proof.count) else { throw Failure.invalidRecord }
        record.proof = proof; record.phase = .assertionReady; try ports.save(record)
        try check(ports,challenge)
        record.phase = .registrationStarted; try ports.save(record)
        try await ports.register(challenge,key,proof)
        try check(ports,challenge)
        record.phase = .ready; record.proof = nil; try ports.save(record)
    }
    nonisolated static func uuidV7(_ value: String) -> Bool {
        UUID(uuidString:value)?.uuidString.lowercased() == value && value.dropFirst(14).first == "7" &&
            value.dropFirst(19).first.map({ "89ab".contains($0) }) == true
    }
    nonisolated static func canonical(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.withoutEscapingSlashes])
    }
    nonisolated static func digest(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }
    nonisolated private static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.int64Value
    }
}
