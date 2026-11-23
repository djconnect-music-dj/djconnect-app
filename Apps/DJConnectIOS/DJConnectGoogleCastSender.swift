#if os(iOS) && canImport(GoogleCast)
import DJConnectCore
import Foundation
@preconcurrency import GoogleCast

/// iOS app target only. Composition must link the official GoogleCastDynamic
/// 4.8.6 product and initialize GCKCastContext once with receiverOptions().
/// The historical AppID still requires real Console/receiver qualification;
/// source construction or a GCK connection is never physical TV acceptance.
@MainActor final class DJConnectGoogleCastSender: NSObject, DJConnectLegacyCastSending, @preconcurrency GCKSessionManagerListener {
    static func receiverOptions() -> GCKCastOptions {
        let criteria = GCKDiscoveryCriteria(applicationID: DJConnectLegacyCastContract.historicalReceiverAppID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        options.physicalVolumeButtonsWillControlDeviceVolume = false
        return options
    }
    private let context: GCKCastContext
    private let clock: ContinuousClock
    private let clockOrigin: ContinuousClock.Instant
    private var launchFence = DJConnectLegacyCastLaunchFence()
    private var launchSession: GCKCastSession?
    private var operation = UUID()
    private var owner: DJConnectLegacyCastOwner?
    private var ownedSession: GCKCastSession?
    private var channel: DJConnectVisualCastChannel?
    private var lease: DJConnectLegacyCastStatusLease?
    private var pendingHandoff: String?
    private var discoveryTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private(set) var devices: [DJConnectLegacyCastDevice] = []
    private(set) var state: DJConnectLegacyCastState = .idle
    var onChange: (@MainActor () -> Void)?

    init(context: GCKCastContext) {
        self.context = context
        let clock = ContinuousClock()
        self.clock = clock
        self.clockOrigin = clock.now
        super.init()
        context.sessionManager.add(self)
    }
    private var now: TimeInterval {
        let elapsed = clockOrigin.duration(to: clock.now).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }

    func startDiscovery() {
        guard discoveryTask == nil else { return }
        context.discoveryManager.startDiscovery()
        discoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let discovery = self.context.discoveryManager
                self.devices = (0..<discovery.deviceCount).map { index in
                    let device = discovery.device(at: index)
                    return DJConnectLegacyCastDevice(id: device.uniqueID, name: device.friendlyName ?? "Google Cast")
                }
                self.onChange?()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
    func stopDiscovery() {
        discoveryTask?.cancel(); discoveryTask = nil
        context.discoveryManager.stopDiscovery()
        devices = []; onChange?()
    }
    private func current(_ request: UUID, _ original: DJConnectLegacyCastOwner) throws {
        guard !Task.isCancelled, operation == request, owner === original, original.isCurrent() else {
            throw DJConnectLegacyCastContract.Error.scopeChanged
        }
    }
    private func matchingSession(_ deviceID: String) -> GCKCastSession? {
        guard let session = context.sessionManager.currentCastSession,
              session.device.uniqueID == deviceID, session.connectionState == .connected,
              session.applicationMetadata?.applicationID == DJConnectLegacyCastContract.historicalReceiverAppID else { return nil }
        return session
    }
    func connect(to deviceID: String, owner original: DJConnectLegacyCastOwner) async throws {
        invalidate()
        // No successor may absorb a late callback from an unresolved launch.
        guard !launchFence.reserved else { throw DJConnectLegacyCastContract.Error.unavailable }
        guard original.isCurrent(), let device = context.discoveryManager.device(withUniqueID: deviceID) else {
            throw DJConnectLegacyCastContract.Error.unavailable
        }
        let request = UUID(); operation = request; owner = original
        state = .connecting; onChange?()
        do {
            if matchingSession(deviceID) == nil {
                let manager = context.sessionManager
                // Do not replace another SDK session merely to manufacture a
                // matching callback or a cleanup witness.
                guard manager.currentCastSession == nil,
                      launchFence.reserve(manager: manager, deviceID: deviceID) else {
                    throw DJConnectLegacyCastContract.Error.unavailable
                }
                guard manager.startSession(with: device) else {
                    launchFence.rejectedBeforeCallback()
                    throw DJConnectLegacyCastContract.Error.unavailable
                }
            }
            let connectionDeadline = now + 15
            while matchingSession(deviceID) == nil {
                try current(request, original)
                guard now < connectionDeadline else { throw DJConnectLegacyCastContract.Error.timeout }
                try await Task.sleep(for: .milliseconds(100))
            }
            try current(request, original)
            guard let session = matchingSession(deviceID) else { throw DJConnectLegacyCastContract.Error.scopeChanged }
            ownedSession = session
            let channelID = UUID()
            let next = DJConnectVisualCastChannel(namespace: DJConnectLegacyCastContract.namespace) { [weak self] message in
                Task { @MainActor in self?.received(message, operation: request, channelID: channelID) }
            }
            channel = next
            guard session.add(next) else { throw DJConnectLegacyCastContract.Error.unavailable }
            let channelDeadline = now + 5
            while !next.isConnected || !next.isWritable {
                try current(request, original)
                guard context.sessionManager.currentCastSession === session, now < channelDeadline else {
                    throw DJConnectLegacyCastContract.Error.timeout
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            // Only the genuine paired owner callback requests Core's existing
            // Runtime token. Discovery/SDK device data cannot construct one.
            let capability = try await original.capability()
            try current(request, original)
            guard context.sessionManager.currentCastSession === session,
                  matchingSession(deviceID) === session, channel === next,
                  next.isConnected, next.isWritable else { throw DJConnectLegacyCastContract.Error.scopeChanged }
            let handoffID = UUID()
            let data = try capability.handoff(origin: original.haOrigin, sessionID: original.sessionID, id: handoffID)
            guard let message = String(data: data, encoding: .utf8) else { throw DJConnectLegacyCastContract.Error.invalidCapability }
            lease = DJConnectLegacyCastStatusLease(handoffID: handoffID, sessionID: original.sessionID, channelID: channelID, now: now)
            pendingHandoff = message
            guard next.sendTextMessage(message, error: nil) else { throw DJConnectLegacyCastContract.Error.sendFailed }
            watch(request, original: original, session: session, channel: next)
        } catch {
            if operation == request { invalidate(); state = .failed; onChange?() }
            throw error
        }
    }
    private func watch(_ request: UUID, original: DJConnectLegacyCastOwner, session: GCKCastSession, channel next: DJConnectVisualCastChannel) {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.operation == request else { return }
                guard original.isCurrent(), self.context.sessionManager.currentCastSession === session,
                      self.matchingSession(session.device.uniqueID) === session,
                      self.channel === next, next.isConnected, var lease = self.lease,
                      lease.tick(now: self.now) else {
                    self.invalidate(); self.state = .failed; self.onChange?(); return
                }
                self.lease = lease
                // Lost receiver readiness is retried with the SAME ID and the
                // original deadline, never another owner token or lease.
                if let message = self.pendingHandoff, next.isWritable {
                    _ = next.sendTextMessage(message, error: nil)
                }
            }
        }
    }
    private func received(_ message: String, operation request: UUID, channelID: UUID) {
        guard operation == request, let owner, owner.isCurrent(),
              let session = ownedSession, context.sessionManager.currentCastSession === session,
              matchingSession(session.device.uniqueID) === session,
              let data = message.data(using: .utf8), var lease,
              lease.receive(data, channel: channelID, now: now) else { return }
        self.lease = lease; pendingHandoff = nil; state = lease.state
        if [.ended,.stopped,.failed].contains(state) {
            let terminal = state; invalidate(); state = terminal
        }
        onChange?()
    }
    func stopView() { invalidate() }
    func invalidate() {
        operation = UUID(); statusTask?.cancel(); statusTask = nil
        if let session = ownedSession, context.sessionManager.currentCastSession === session,
           let channel, let lease, let data = try? lease.stopEnvelope(),
           let message = String(data: data, encoding: .utf8), channel.isConnected, channel.isWritable {
            _ = channel.sendTextMessage(message, error: nil)
        }
        if let channel { _ = ownedSession?.remove(channel) }
        launchFence.cancel()
        endCancelledLaunchIfCurrent()
        channel = nil; ownedSession = nil; owner = nil; pendingHandoff = nil
        lease?.invalidate(); lease = nil; state = .stopped; onChange?()
        // No remoteMediaClient load/play/pause/volume, HA command or Session end.
    }
    private func endCancelledLaunchIfCurrent() {
        let manager = context.sessionManager
        if launchFence.shouldEnd(manager: manager, currentSession: manager.currentCastSession) {
            _ = manager.endSessionAndStopCasting(false)
        }
    }
    // The real SDK's willStart callback supplies the session object before
    // connection completes. A cancellation before that callback remains closed
    // to successors and cleans up only this exact object if it later arrives.
    func sessionManager(_ manager: GCKSessionManager, willStart session: GCKCastSession) {
        guard manager === context.sessionManager,
              launchFence.willStart(manager: manager, deviceID: session.device.uniqueID, session: session) else { return }
        launchSession = session
        endCancelledLaunchIfCurrent()
    }
    func sessionManager(_ manager: GCKSessionManager, didStart session: GCKCastSession) {
        guard manager === context.sessionManager, launchSession === session else { return }
        endCancelledLaunchIfCurrent()
    }
    func sessionManager(_ manager: GCKSessionManager, didFailToStart session: GCKCastSession, withError error: Error) {
        finishLaunch(manager, session: session)
    }
    func sessionManager(_ manager: GCKSessionManager, didEnd session: GCKCastSession, withError error: Error?) {
        finishLaunch(manager, session: session)
    }
    private func finishLaunch(_ manager: GCKSessionManager, session: GCKCastSession) {
        guard manager === context.sessionManager, launchSession === session else { return }
        launchFence.terminal(manager: manager, session: session)
        launchSession = nil
    }

}

/// SDK callback carries only bounded content to the actual current MainActor
/// owner. Old channel callbacks cannot relabel a later operation.
private final class DJConnectVisualCastChannel: GCKCastChannel, @unchecked Sendable {
    private let receive: @Sendable (String) -> Void
    init(namespace: String, receive: @escaping @Sendable (String) -> Void) {
        self.receive = receive
        super.init(namespace: namespace)
    }
    override func didReceiveTextMessage(_ message: String) {
        guard message.utf8.count <= 4096 else { return }
        receive(message)
    }
}
#endif
