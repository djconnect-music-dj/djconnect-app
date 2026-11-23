import Foundation

/// Existing visual-only CAF route. These types are runtime correlation, never
/// Home Assistant owner authority, device enrollment or A/B display admission.
public enum DJConnectLegacyCastContract {
    public static let namespace = "urn:x-cast:com.djconnect.vibecast.v1"
    public static let historicalReceiverAppID = "8EA92910"
    public static let receiverURL = URL(string: "https://receiver.djconnect.dev/")!

    public static func origin(_ value: String) -> String? {
        guard value.utf8.count <= 1024, !value.contains("\\"),
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }),
              let parts = URLComponents(string: value), parts.scheme == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, ["", "/"].contains(parts.path),
              let url = parts.url, url.host != nil else { return nil }
        var normalized = parts
        normalized.path = ""
        return normalized.string
    }

    public struct Capability: Decodable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
        public let sessionID: String
        public var description: String { "Read-only Cast capability (redacted)" }
        public var debugDescription: String { description }
        private let token: String
        private let viewBroadcast: Bool
        private let ownerControls: Bool
        private enum CodingKeys: String, CodingKey {
            case success, sessionID = "session_id", token = "broadcast_token", capabilities
        }
        private enum CapabilityKeys: String, CodingKey {
            case viewBroadcast = "view_broadcast", ownerControls = "owner_controls"
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard try c.decode(Bool.self, forKey: .success) else { throw Error.invalidCapability }
            sessionID = try c.decode(String.self, forKey: .sessionID)
            token = try c.decode(String.self, forKey: .token)
            let caps = try c.nestedContainer(keyedBy: CapabilityKeys.self, forKey: .capabilities)
            viewBroadcast = try caps.decode(Bool.self, forKey: .viewBroadcast)
            ownerControls = try caps.decode(Bool.self, forKey: .ownerControls)
            guard !sessionID.isEmpty, sessionID.count <= 128, (24...256).contains(token.count),
                  viewBroadcast, !ownerControls else { throw Error.invalidCapability }
        }
        public func handoff(origin: String, sessionID expected: String, id: UUID) throws -> Data {
            guard sessionID == expected, let origin = DJConnectLegacyCastContract.origin(origin) else {
                throw Error.invalidCapability
            }
            // The existing read-only Runtime capability is the only secret sent.
            return try JSONSerialization.data(withJSONObject: ["kind":"vibecast_handoff", "version":1,
                "ha_url":origin, "session_id":sessionID, "broadcast_token":token,
                "status_version":1, "handoff_id":id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()])
        }
    }
    public enum Error: Swift.Error { case unavailable, invalidCapability, scopeChanged, timeout, sendFailed }
}

/// Captured only by the existing AppModel paired-owner request boundary. The
/// closure must retain its genuine Session/install/profile/pairing/epoch fences.
/// A Google device identifier does not supply that authority.
@MainActor public final class DJConnectLegacyCastOwner {
    public let sessionID: String
    public let haOrigin: String
    public let isCurrent: @MainActor () -> Bool
    public let capability: @MainActor () async throws -> DJConnectLegacyCastContract.Capability
    public init(sessionID: String, haOrigin: String, isCurrent: @escaping @MainActor () -> Bool,
                capability: @escaping @MainActor () async throws -> DJConnectLegacyCastContract.Capability) throws {
        guard !sessionID.isEmpty, sessionID.count <= 128,
              let origin = DJConnectLegacyCastContract.origin(haOrigin), isCurrent() else {
            throw DJConnectLegacyCastContract.Error.scopeChanged
        }
        self.sessionID = sessionID; self.haOrigin = origin
        self.isCurrent = isCurrent; self.capability = capability
    }
}

public struct DJConnectLegacyCastDevice: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public enum DJConnectLegacyCastState: String, Equatable, Sendable {
    case idle, connecting, receiverReady, snapshotAccepted, presentingMoment, presentingSilence
    case recovering, ended, stopped, failed
    public var softwarePresentationConfirmed: Bool { self == .presentingMoment || self == .presentingSilence }
}

@MainActor public protocol DJConnectLegacyCastSending: AnyObject {
    var devices: [DJConnectLegacyCastDevice] { get }
    var state: DJConnectLegacyCastState { get }
    var onChange: (@MainActor () -> Void)? { get set }
    func startDiscovery()
    func stopDiscovery()
    func connect(to deviceID: String, owner: DJConnectLegacyCastOwner) async throws
    func stopView()
    func invalidate()
}

/// One actual channel/handoff/session correlation. Parsing success confers no
/// playback or HA authority. All clocks are local monotonic observations.
public struct DJConnectLegacyCastStatusLease: Sendable {
    public private(set) var state: DJConnectLegacyCastState = .connecting
    public let handoffID: UUID
    public let sessionID: String
    public let channelID: UUID
    private var sequence: UInt64 = 0
    private var deadline: TimeInterval
    private var handshakeDeadline: TimeInterval?
    private var retired = false
    private var lastClock: TimeInterval

    public init(handoffID: UUID, sessionID: String, channelID: UUID, now: TimeInterval) {
        self.handoffID = handoffID; self.sessionID = sessionID; self.channelID = channelID
        deadline = now + 15; handshakeDeadline = now + 15; lastClock = now
    }
    public mutating func invalidate() { retired = true; state = .stopped }
    @discardableResult public mutating func tick(now: TimeInterval) -> Bool {
        guard !retired else { return false }
        guard now.isFinite, now >= lastClock, now < deadline,
              handshakeDeadline.map({ now < $0 }) ?? true else {
            retired = true; state = .failed; return false
        }
        lastClock = now; return true
    }
    @discardableResult public mutating func receive(_ data: Data, channel: UUID, now: TimeInterval) -> Bool {
        guard tick(now: now), channel == channelID, data.count <= 4096,
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(raw.keys).isSubset(of: ["kind","version","handoff_id","session_id","sequence","state","lease_ms","reason","presentation"]),
              let message = try? JSONDecoder().decode(Status.self, from: data),
              message.kind == "vibecast_status", message.version == 1,
              message.handoffID == handoffID.uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
              message.sessionID == sessionID, message.sequence > sequence,
              message.leaseMS == 15000,
              message.reason.map({ Status.reasons.contains($0) }) ?? true else { return false }
        let next: DJConnectLegacyCastState
        switch message.state {
        case "receiver_ready": next = .receiverReady
        case "connecting": next = .connecting
        case "snapshot_accepted": next = .snapshotAccepted
        case "recovering": next = .recovering
        case "presenting":
            guard let presentation = message.presentation, ["moment","silence"].contains(presentation) else { return false }
            next = presentation == "moment" ? .presentingMoment : .presentingSilence
        case "ended": next = .ended
        case "stopped": next = .stopped
        case "error": next = .failed
        default: return false
        }
        guard next.softwarePresentationConfirmed || message.presentation == nil else { return false }
        sequence = message.sequence
        if next.softwarePresentationConfirmed { handshakeDeadline = nil }
        else if state.softwarePresentationConfirmed { handshakeDeadline = now + 15 }
        deadline = now + Double(message.leaseMS) / 1000
        state = next
        if [.ended,.stopped,.failed].contains(next) { retired = true }
        return true
    }
    public func stopEnvelope() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["kind":"vibecast_stop","version":1,
            "handoff_id":handoffID.uuidString.replacingOccurrences(of: "-", with: "").lowercased(), "session_id":sessionID])
    }
    private struct Status: Decodable {
        let kind: String, version: Int, handoffID: String, sessionID: String, sequence: UInt64
        let state: String, leaseMS: Int, reason: String?, presentation: String?
        enum CodingKeys: String, CodingKey {
            case kind, version, handoffID = "handoff_id", sessionID = "session_id", sequence, state
            case leaseMS = "lease_ms", reason, presentation
        }
        static let reasons: Set<String> = ["snapshot_timeout","invalid_handoff","incompatible_snapshot",
            "access_rejected","runtime_end","host_stop","sender_disconnected","superseded"]
    }
}
