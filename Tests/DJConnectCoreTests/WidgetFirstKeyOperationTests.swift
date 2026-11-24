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
    let receipt = Data("modeled-original-receipt-DATA-not-authority".utf8)
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
            try await self.called(.register); return self.receipt
        }, status: { challenge in
            #expect(challenge.operationID == "12345678-1234-4234-8234-123456789abc")
            try await self.called(.status); return self.receipt
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
    if stage == .register {
        #expect(try fixture.record()?.phase == .registered)
        #expect(try fixture.record()?.receipt == fixture.receipt)
    }
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

@Test(.isolatedClientResources, arguments: ["actual-shape", "missing-evidence", "missing-status", "bool", "unsafe", "zero", "extra", "original-expiry"])
@MainActor func widgetProductionReceiptRequiresBothOriginalAppleEvidenceDataBounds(_ mutation: String) throws {
    let fixture = WidgetFirstKeyFixture()
    let challenge = try fixture.challenge()
    var value: [String: Any] = ["contract_version":1,"operation_id":challenge.operationID,
        "api_installation_id":"model-install","install_credential_id":"model-credential",
        "pairing_generation":"model-pair","core_key_thumbprint":String(repeating:"4",count:64),
        "registry_generation":"model-registry","expires_at_ms":challenge.expiresAtMS,"key_revision":1,
        "state":"registered","transcript_sha256":challenge.clientDataHash.map { String(format:"%02x",$0) }.joined(),
        "apple_evidence_expires_at_ms":1_900_000_000_000 as Int64,
        "apple_status_expires_at_ms":1_850_000_000_000 as Int64]
    switch mutation {
    case "missing-evidence": value.removeValue(forKey:"apple_evidence_expires_at_ms")
    case "missing-status": value.removeValue(forKey:"apple_status_expires_at_ms")
    case "bool": value["apple_evidence_expires_at_ms"] = true
    case "unsafe": value["apple_status_expires_at_ms"] = 9_007_199_254_740_992 as Int64
    case "zero": value["apple_status_expires_at_ms"] = 0
    case "extra": value["native_clock_permission"] = true
    case "original-expiry": value["expires_at_ms"] = challenge.expiresAtMS + 1
    default: break
    }
    var accepted = false
    do { try challenge.validateReceipt(JSONSerialization.data(withJSONObject:value)); accepted = true } catch {}
    #expect(accepted == (mutation == "actual-shape"))
    #expect(!challenge.isCurrent(nowMS:challenge.expiresAtMS,uptime:200))
}


@MainActor private func reauthorizationProducer() throws -> (data:Data,receipt:Data,operation:String,expiry:Int64) {
    let path = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/native-widget-reauthorization-core.json")
    let bytes = try Data(contentsOf:path)
    #expect(SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined() == "cc405107cc66786b3ba0de21143f6a7f9fbc58fe6f8f5bfa9e235316c9777886")
    let fixture = try #require(JSONSerialization.jsonObject(with:bytes) as? [String:Any])
    let response = try #require(fixture["challenge_response"] as? [String:Any])
    let challenge = try #require(response["challenge"] as? [String:Any])
    return (try WidgetReauthorizationOperation.canonical(response),
        try WidgetReauthorizationOperation.canonical(#require(response["first_key_receipt"] as? [String:Any])),
        try #require(response["operation_id"] as? String),try #require(challenge["expires_at_ms"] as? Int64))
}
@Test(.isolatedClientResources, arguments:["producer","hash","receipt","nonce","duplicate","unsafe","late","policy","extra"])
@MainActor func widgetReauthorizationBindsActualCoreProducerAndOriginalDeadlines(_ mode:String) throws {
    let fixture = try reauthorizationProducer()
    var response = try #require(JSONSerialization.jsonObject(with:fixture.data) as? [String:Any])
    var challenge = try #require(response["challenge"] as? [String:Any])
    if mode == "hash" { response["client_data_hash_b64"] = Data(repeating:0,count:32).base64EncodedString() }
    if mode == "receipt" { var r = try #require(response["first_key_receipt"] as? [String:Any]);r["key_revision"] = 2;response["first_key_receipt"] = r }
    if mode == "nonce" { challenge["challenge_nonce"] = "noncanonical";response["challenge"] = challenge }
    if mode == "unsafe" { challenge["expires_at_ms"] = 9_007_199_254_740_992 as Int64;response["challenge"] = challenge }
    if mode == "policy" { var d = try #require(response["delegation"] as? [String:Any]);var p = try #require(d["policy"] as? [String:Any]);p["original_grant_expires_at_ms"] = 1;d["policy"] = p;response["delegation"] = d }
    if mode == "extra" { response["native_clock_permission"] = true }
    var bytes = try WidgetReauthorizationOperation.canonical(response)
    if mode == "duplicate" { bytes = Data(("{\"contract_version\":1," + String(decoding:bytes.dropFirst(),as:UTF8.self)).utf8) }
    var value:WidgetReauthorizationOperation.Challenge?
    do { value = try .parse(bytes,operationID:fixture.operation,receipt:fixture.receipt,
        nowMS:fixture.expiry-(mode == "late" ? 0 : 60_000),requestedUptime:100,uptime:101) } catch {}
    #expect((value != nil) == (mode == "producer"))
    if let value {
        #expect(value.isCurrent(nowMS:fixture.expiry-1,uptime:159))
        #expect(!value.isCurrent(nowMS:fixture.expiry,uptime:160))
        #expect(!value.isCurrent(nowMS:fixture.expiry-59_000,uptime:221))
    }
}
@MainActor final class WidgetReauthorizationFixture {
    enum Stage:String { case challenge,assertion,register,status }
    enum Failure:Error { case modeled }
    let producer:(data:Data,receipt:Data,operation:String,expiry:Int64)
    let key = Data(repeating:7,count:32).base64EncodedString()
    var bytes:Data?, owner = true, expired = false
    var hold:Stage?, fail:Stage?
    let latch = WidgetFirstKeyLatch()
    var events:[String] = []
    var calls:[Stage:Int] = [:]
    init() throws { producer = try reauthorizationProducer() }
    func record() throws -> WidgetReauthorizationOperation.Record? { try bytes.map { try JSONDecoder().decode(WidgetReauthorizationOperation.Record.self,from:$0) } }
    private func called(_ stage:Stage) async throws {
        calls[stage,default:0] += 1;events.append("effect."+stage.rawValue)
        if hold == stage { await latch.wait() }
        if fail == stage { throw Failure.modeled }
    }
    func ports() -> WidgetReauthorizationOperation.Ports {
        .init(load:{try self.record()},save:{self.bytes = try JSONEncoder().encode($0);self.events.append("store."+$0.phase.rawValue)},
            ownerCurrent:{self.owner},current:{self.owner && $0.isCurrent(nowMS:self.producer.expiry-(self.expired ? 0 : 60_000),uptime:101)},
            challenge:{try await self.called(.challenge);return try .parse(self.producer.data,operationID:self.producer.operation,receipt:self.producer.receipt,nowMS:self.producer.expiry-60_000,requestedUptime:100,uptime:101)},
            assertion:{key,hash in #expect(key == self.key && hash.count == 32);try await self.called(.assertion);return Data("MODEL assertion NOT Apple proof".utf8)},
            register:{_,_,_ in try await self.called(.register)},status:{_ in try await self.called(.status)})
    }
    func run() async throws { try await WidgetReauthorizationOperation.run(operationID:producer.operation,key:key,receipt:producer.receipt,ports:ports()) }
}
@Test(.isolatedClientResources) @MainActor func widgetReauthorizationOwnsEachPhaseWithoutGeneratingAnotherKey() async throws {
    let f = try WidgetReauthorizationFixture();try await f.run()
    #expect(f.events == ["store.challengeStarted","effect.challenge","store.challengeReceived","store.assertionStarted","effect.assertion","store.assertionReady","store.registrationStarted","effect.register","store.ready"])
    #expect(f.calls[.challenge] == 1 && f.calls[.assertion] == 1 && f.calls[.register] == 1)
    let restarted = try WidgetReauthorizationFixture();restarted.bytes = f.bytes;try await restarted.run()
    #expect(restarted.calls == [.status:1])
    restarted.expired = true
    do { try await restarted.run();Issue.record("Expired original status must close") } catch {}
    #expect(restarted.calls == [.status:1])
}
@Test(.isolatedClientResources,arguments:[WidgetReauthorizationFixture.Stage.challenge,.assertion,.register])
@MainActor func widgetReauthorizationWithdrawalDuringAwaitCannotStartTheNextEffect(_ stage:WidgetReauthorizationFixture.Stage) async throws {
    let f = try WidgetReauthorizationFixture();f.hold = stage
    let task = Task { try await f.run() };await f.latch.awaitEntry();f.owner = false;f.latch.release()
    do { try await task.value;Issue.record("Withdrawn owner must close") } catch {}
    if stage == .challenge { #expect(f.calls[.assertion] == nil) }
    if stage == .assertion { #expect(f.calls[.register] == nil);#expect(try f.record()?.phase == .assertionReady) }
    let restarted = try WidgetReauthorizationFixture();restarted.bytes = f.bytes
    if stage != .register {
        do { try await restarted.run();Issue.record("Cold SDK phase must not resume") } catch {}
        #expect(restarted.calls.isEmpty)
    }
}
@Test(.isolatedClientResources,arguments:[WidgetReauthorizationFixture.Stage.challenge,.assertion,.register])
@MainActor func widgetReauthorizationUnknownOutcomeNeverRepeatsNonceAssertionOrSubmit(_ stage:WidgetReauthorizationFixture.Stage) async throws {
    let f = try WidgetReauthorizationFixture();f.fail = stage
    do { try await f.run();Issue.record("Expected modeled unknown") } catch {}
    let restarted = try WidgetReauthorizationFixture();restarted.bytes = f.bytes
    do { try await restarted.run() } catch {}
    #expect(restarted.calls[.challenge] == nil && restarted.calls[.assertion] == nil && restarted.calls[.register] == nil)
    #expect(restarted.calls[.status] == (stage == .register ? 1 : nil))
}
