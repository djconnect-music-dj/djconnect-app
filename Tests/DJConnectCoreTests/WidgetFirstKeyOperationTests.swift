import Foundation
import CryptoKit
import Testing
@testable import DJConnectCore

// Modeled SDK/server callbacks, not Apple attestation, a signed installation,
// an enrolled principal or a positive native permission. The shipping driver
// is exercised through actual serialized journal reloads and suspended awaits.
@MainActor final class WidgetFirstKeyLatch {
    var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var finished = false
    func wait() async {
        entered = true; let callbacks = entryWaiters; entryWaiters = []; callbacks.forEach { $0.resume() }
        await withCheckedContinuation { continuation = $0 }
    }
    func awaitEntry() async {
        if entered || finished { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }
    func finish() {
        finished = true; let callbacks = entryWaiters; entryWaiters = []; callbacks.forEach { $0.resume() }
    }
    func release() { continuation?.resume(); continuation = nil }
}
@MainActor final class WidgetFirstKeyFixture {
    enum Stage: String, CaseIterable { case challenge, generate, attest, register, status }
    enum Injected: Error { case unavailable, write }
    var bytes: Data?
    var owner = true
    var currentWall: Int64 = 1_800_000_000_000
    var uptime: TimeInterval = 101
    var hold: Stage?
    var failure: Stage?
    var failedWrite: WidgetFirstKeyOperation.Phase?
    let latch = WidgetFirstKeyLatch()
    var events: [String] = []
    var key = Data(repeating: 7, count: 32).base64EncodedString()
    var proof = Data("explicit-model-sdk-proof-not-Apple-evidence".utf8)
    var records: [WidgetFirstKeyOperation.Phase] = []
    var calls: [Stage: Int] = [:]
    private func called(_ stage: Stage) async throws {
        calls[stage, default: 0] += 1; events.append("effect." + stage.rawValue)
        if hold == stage { await latch.wait() }
        if failure == stage { throw Injected.unavailable }
    }
    func record() throws -> WidgetFirstKeyOperation.Record? {
        try bytes.map { try JSONDecoder().decode(WidgetFirstKeyOperation.Record.self, from: $0) }
    }
    func challenge() throws -> DJConnectClient.WidgetFirstKeyChallenge {
        let op = "12345678-1234-4234-8234-123456789abc", audience = "djc-native-push/1"
        let nonce = String(repeating: "A", count: 43), expiry: Int64 = 1_800_000_060_000
        let ids = ["model-install", "model-credential", "model-challenge", "model-pair"]
        let digests = (1...4).map { String(repeating: String($0), count: 64) }
        let transcript: [Any] = ["djc-native-pair-witness/1", audience, "POST", "/v1/push/native/key/register", "widget-first-key", op,
            ids[0], ids[1], ids[2], nonce, expiry, 0, ids[3]] + digests
        let hash = Data(SHA256.hash(data: try JSONSerialization.data(withJSONObject: transcript, options: [.withoutEscapingSlashes])))
        let object: [String: Any] = ["contract_version": 1, "api_audience": audience, "operation_id": op,
            "challenge_nonce": nonce, "expires_at_ms": expiry, "expected_key_revision": 0, "client_data_hash_b64": hash.base64EncodedString(),
            "api_installation_id": ids[0], "install_credential_id": ids[1], "challenge_id": ids[2], "pairing_generation": ids[3],
            "pair_binding": digests[0], "owner_binding": digests[1], "device_binding": digests[2], "core_key_thumbprint": digests[3]]
        return try DJConnectClient.WidgetFirstKeyChallenge.parse(JSONSerialization.data(withJSONObject: object),
            nowMS: 1_800_000_000_000, requestedUptime: 100, uptime: 101, pairingBinding: Data(repeating: 2, count: 32))
    }
    func ports() -> WidgetFirstKeyOperation.Ports {
        .init(load: { try self.record() }, save: { record in
            if self.failedWrite == record.phase { throw Injected.write }
            self.bytes = try JSONEncoder().encode(record)
            self.records.append(record.phase); self.events.append("store." + record.phase.rawValue)
        }, challenge: { try await self.called(.challenge); return try self.challenge() }, ownerCurrent: { self.owner },
        current: { self.owner && $0.isCurrent(nowMS: self.currentWall, uptime: self.uptime) },
        generateKey: { try await self.called(.generate); return self.key },
        attestKey: { key, hash in
            #expect(key == self.key && hash.count == 32)
            try await self.called(.attest); return self.proof
        }, register: { challenge, key, proof in
            #expect(challenge.operationID == "12345678-1234-4234-8234-123456789abc" && key == self.key && proof == self.proof)
            try await self.called(.register)
        }, status: { challenge in
            #expect(challenge.operationID == "12345678-1234-4234-8234-123456789abc")
            try await self.called(.status)
        })
    }
}
@Test(.isolatedClientResources) @MainActor func widgetFirstKeyPersistsEachOriginalPhaseBeforeSDKOrRegistration() async throws {
    let fixture = WidgetFirstKeyFixture()
    try await WidgetFirstKeyOperation.run(fixture.ports())
    #expect(fixture.records == [.generationStarted, .keyGenerated, .attestationStarted, .proofReady, .registrationStarted, .registered])
    #expect(fixture.events.firstIndex(of: "store.generationStarted")! < fixture.events.firstIndex(of: "effect.generate")!)
    #expect(fixture.events.firstIndex(of: "store.attestationStarted")! < fixture.events.firstIndex(of: "effect.attest")!)
    #expect(fixture.events.firstIndex(of: "store.registrationStarted")! < fixture.events.firstIndex(of: "effect.register")!)
    let stored = try fixture.record()
    let final = try #require(stored)
    #expect(final.phase == .registered && final.keyIdentifier == fixture.key && final.proof == nil)
}
@Test(.isolatedClientResources, arguments: [WidgetFirstKeyFixture.Stage.challenge, .generate, .attest, .register])
@MainActor func widgetFirstKeyWithdrawalDuringAwaitCannotStartTheNextEffect(_ stage: WidgetFirstKeyFixture.Stage) async throws {
    let fixture = WidgetFirstKeyFixture(); fixture.hold = stage
    let task = Task { @MainActor in
        defer { fixture.latch.finish() }
        try await WidgetFirstKeyOperation.run(fixture.ports())
    }
    await fixture.latch.awaitEntry()
    #expect(fixture.latch.entered)
    guard fixture.latch.entered else { _ = await task.result; return }
    fixture.owner = false; fixture.latch.release()
    var accepted = false
    do { try await task.value; accepted = true } catch { }
    #expect(!accepted)
    if stage == .challenge { #expect(fixture.calls[.generate] == nil && fixture.bytes == nil) }
    if stage == .generate {
        let stored = try fixture.record()
        let record = try #require(stored)
        #expect(record.keyIdentifier == fixture.key && record.phase == .keyGenerated)
        #expect(fixture.calls[.attest] == nil)
    }
    if stage == .attest {
        let stored = try fixture.record()
        let record = try #require(stored)
        #expect(record.phase == .proofReady && record.proof == fixture.proof)
        #expect(fixture.calls[.register] == nil)
    }
    if stage == .register { #expect(try fixture.record()?.phase == .registrationStarted) }
}
@Test(.isolatedClientResources, arguments: [WidgetFirstKeyFixture.Stage.generate, .attest])
@MainActor func widgetFirstKeyUnknownSDKOutcomeNeverGeneratesOrAttestsAgain(_ stage: WidgetFirstKeyFixture.Stage) async throws {
    let fixture = WidgetFirstKeyFixture(); fixture.failure = stage
    do { try await WidgetFirstKeyOperation.run(fixture.ports()); Issue.record("Expected modeled SDK failure") } catch { }
    let restarted = WidgetFirstKeyFixture(); restarted.bytes = fixture.bytes
    do { try await WidgetFirstKeyOperation.run(restarted.ports()); Issue.record("Serialized phase must not restore SDK authority") } catch { }
    #expect(fixture.calls[.generate] == 1 && restarted.calls[.generate] == nil && restarted.calls[.attest] == nil)
    #expect(restarted.calls[.register] == nil && restarted.calls[.challenge] == nil)
    if stage == .attest { #expect(try restarted.record()?.keyIdentifier == fixture.key) }
}
@Test(.isolatedClientResources, arguments: [WidgetFirstKeyOperation.Phase.generationStarted, .attestationStarted, .proofReady, .registrationStarted])
@MainActor func widgetFirstKeyFailedDurablePhasePreventsItsFollowingEffect(_ phase: WidgetFirstKeyOperation.Phase) async throws {
    let fixture = WidgetFirstKeyFixture(); fixture.failedWrite = phase
    do { try await WidgetFirstKeyOperation.run(fixture.ports()); Issue.record("Expected modeled journal failure") } catch { }
    if phase == .generationStarted { #expect(fixture.calls[.generate] == nil) }
    if phase == .attestationStarted { #expect(fixture.calls[.attest] == nil) }
    if [.proofReady, .registrationStarted].contains(phase) { #expect(fixture.calls[.register] == nil) }
}
@Test(.isolatedClientResources) @MainActor func widgetFirstKeyLostRegistrationUsesOnlyOriginalStatusAndDeadline() async throws {
    let fixture = WidgetFirstKeyFixture(); fixture.failure = .register
    do { try await WidgetFirstKeyOperation.run(fixture.ports()); Issue.record("Expected modeled lost ACK") } catch { }
    #expect(try fixture.record()?.phase == .registrationStarted)
    let restarted = WidgetFirstKeyFixture(); restarted.bytes = fixture.bytes
    try await WidgetFirstKeyOperation.run(restarted.ports())
    #expect(restarted.calls[.status] == 1 && restarted.calls[.generate] == nil && restarted.calls[.attest] == nil && restarted.calls[.register] == nil)
    restarted.currentWall = 1_800_000_060_001
    do { try await WidgetFirstKeyOperation.run(restarted.ports()); Issue.record("Original expired challenge cannot restore an ACK") } catch { }
    #expect(restarted.calls[.status] == 1 && restarted.calls[.challenge] == nil)
}
@Test(.isolatedClientResources) @MainActor func widgetFirstKeyRegisteredMarkerNeedsFreshGenuineStatusNotColdRestoration() async throws {
    let fixture = WidgetFirstKeyFixture(); try await WidgetFirstKeyOperation.run(fixture.ports())
    let restarted = WidgetFirstKeyFixture(); restarted.bytes = fixture.bytes; restarted.failure = .status
    do { try await WidgetFirstKeyOperation.run(restarted.ports()); Issue.record("Stored registered is metadata, not a new ACK") } catch { }
    #expect(restarted.calls[.status] == 1 && restarted.calls[.generate] == nil && restarted.calls[.attest] == nil && restarted.calls[.register] == nil)
}
