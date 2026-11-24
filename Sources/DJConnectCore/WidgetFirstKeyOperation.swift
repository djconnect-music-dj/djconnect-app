import Foundation

/// Operational SDK custody only. A journal phase or successful return is never
/// a Widget issuer, native clock permission, or restored surface admission.
@MainActor enum WidgetFirstKeyOperation {
    enum Phase: String, Codable, Sendable {
        case generationStarted, keyGenerated, attestationStarted, proofReady, registrationStarted, registered
    }
    struct Record: Codable, Sendable {
        let challenge: DJConnectClient.WidgetFirstKeyChallenge
        var phase: Phase
        var keyIdentifier: String?
        var proof: Data?
        var receipt: Data? = nil // Comparison DATA only, never restored admission.
    }
    enum Failure: Error { case closed, sdkOutcomeUnknown, invalidRecord }
    struct Ports {
        let load: @MainActor () throws -> Record?
        let save: @MainActor (Record) throws -> Void
        let challenge: @MainActor () async throws -> DJConnectClient.WidgetFirstKeyChallenge
        let ownerCurrent: @MainActor () -> Bool
        let current: @MainActor (DJConnectClient.WidgetFirstKeyChallenge) -> Bool
        let generateKey: @MainActor () async throws -> String
        let attestKey: @MainActor (String, Data) async throws -> Data
        let register: @MainActor (DJConnectClient.WidgetFirstKeyChallenge, String, Data) async throws -> Data
        let status: @MainActor (DJConnectClient.WidgetFirstKeyChallenge) async throws -> Data
    }
    private static func check(_ record: Record, ports: Ports) throws {
        try Task.checkCancellation()
        guard ports.ownerCurrent(), ports.current(record.challenge) else { throw Failure.closed }
    }
    private static func validate(_ record: Record) throws {
        if record.phase == .generationStarted {
            guard record.keyIdentifier == nil, record.proof == nil else { throw Failure.invalidRecord }
            return
        }
        guard let key = record.keyIdentifier, let bytes = Data(base64Encoded: key), bytes.count == 32,
              bytes.base64EncodedString() == key else { throw Failure.invalidRecord }
        if [.proofReady, .registrationStarted].contains(record.phase) {
            guard let proof = record.proof, (1...16_384).contains(proof.count) else { throw Failure.invalidRecord }
        } else { guard record.proof == nil else { throw Failure.invalidRecord }; return }
    }
    private static func retainReceipt(_ data: Data, record: inout Record, ports: Ports) throws {
        guard (1...4096).contains(data.count) else { throw Failure.invalidRecord }
        record.phase = .registered; record.proof = nil; record.receipt = data
        // A late actual ACK is retained as comparison DATA even if its UI owner
        // was withdrawn during await. It cannot restore the old role/admission.
        try ports.save(record)
    }
    static func run(_ ports: Ports) async throws {
        try Task.checkCancellation()
        guard ports.ownerCurrent() else { throw Failure.closed }
        var record: Record
        if let existing = try ports.load() {
            try validate(existing); record = existing
            try check(record, ports: ports)
            // Serialized phase/key/proof data is not cold-restored SDK or
            // submission authority. Only a previously submitted original can
            // query its actual outcome, within that original deadline.
            guard [.registrationStarted, .registered].contains(record.phase) else {
                throw Failure.sdkOutcomeUnknown
            }
            let data = try await ports.status(record.challenge)
            try retainReceipt(data, record: &record, ports: ports)
            try check(record, ports: ports)
            return
        } else {
            let challenge = try await ports.challenge()
            record = .init(challenge: challenge, phase: .generationStarted)
            try check(record, ports: ports)
            // Durable original operation BEFORE the irreversible SDK call.
            try ports.save(record)
            let key = try await ports.generateKey()
            guard let bytes = Data(base64Encoded: key), bytes.count == 32,
                  bytes.base64EncodedString() == key else { throw Failure.invalidRecord }
            // Preserve the real returned reference even when its owner was
            // withdrawn during the SDK await. Never replace that key on retry.
            record.keyIdentifier = key; record.phase = .keyGenerated
            try ports.save(record)
        }
        try check(record, ports: ports)
        if [.generationStarted, .attestationStarted].contains(record.phase) {
            // The SDK may have committed without returning its result. A new
            // key/attestation would manufacture a replacement original effect.
            throw Failure.sdkOutcomeUnknown
        }
        if record.phase == .keyGenerated {
            let key = record.keyIdentifier!
            record.phase = .attestationStarted; try ports.save(record)
            let proof = try await ports.attestKey(key, record.challenge.clientDataHash)
            guard (1...16_384).contains(proof.count) else { throw Failure.invalidRecord }
            record.proof = proof; record.phase = .proofReady
            try ports.save(record)
            try check(record, ports: ports)
        }
        if record.phase == .proofReady {
            try check(record, ports: ports)
            record.phase = .registrationStarted; try ports.save(record)
            let data = try await ports.register(record.challenge, record.keyIdentifier!, record.proof!)
            try retainReceipt(data, record: &record, ports: ports)
        } else if [.registrationStarted, .registered].contains(record.phase) {
            // A persisted registered marker is metadata only. Recovery still
            // needs a genuine ACK for this exact still-current original flow.
            try check(record, ports: ports)
            let data = try await ports.status(record.challenge)
            try retainReceipt(data, record: &record, ports: ports)
        } else { throw Failure.invalidRecord }
        try check(record, ports: ports)
    }
}
