import Combine
import Foundation
import DJConnectCore

/// Presentation observations only. A new lease requires a real, validated
/// reader completion; cached DTOs and render/expiry events cannot renew one.
@MainActor final class AskDJHelpCatalogueModel: ObservableObject {
    struct Observation: Sendable { let ids: Set<String>; let trackID: String? }
    typealias Reader = @MainActor (DJConnectAskDJCatalogue.Context, DJConnectAskDJCatalogue.Surface, String, ContinuousClock.Instant) async throws -> Observation
    @Published private(set) var sections: [DJConnectAskDJCatalogue.CatalogueSection] = []
    @Published private(set) var busy = false
    @Published private(set) var admittedContext: DJConnectAskDJCatalogue.Context?
    @Published private(set) var allowsVisibleRefresh = false
    private var generation = UUID()
    private var originalContext: DJConnectAskDJCatalogue.Context?
    private var readTask: Task<Observation, Error>?
    private var automaticRead = false
    private var deadline: ContinuousClock.Instant?
    private var expiry: Task<Void, Never>?
    private var lastDispatch: ContinuousClock.Instant?
    private var unavailableReference: [DJConnectAskDJCatalogue.CatalogueSection] = []
    private let now: () -> ContinuousClock.Instant
    init(now: @escaping () -> ContinuousClock.Instant = { .now }) { self.now = now }

    func close() {
        generation = UUID(); deadline = nil; originalContext = nil
        readTask?.cancel(); readTask = nil
        expiry?.cancel(); expiry = nil
        automaticRead = false; allowsVisibleRefresh = false
        sections = []; unavailableReference = []; admittedContext = nil; busy = false
    }
    func retireExpiredObservation() {
        guard let deadline, now() >= deadline else { return }
        self.deadline = nil; expiry?.cancel(); expiry = nil
        sections = unavailableReference; admittedContext = nil
        // A distinct, already-dispatched refresh owns its own original window.
        // Retiring the previous lease cannot turn that response into an old DTO.
        if !automaticRead {
            generation = UUID(); readTask?.cancel(); readTask = nil; busy = false
        }
    }
    func contextChanged(to next: DJConnectAskDJCatalogue.Context) {
        if let originalContext, originalContext != next { close() }
    }
    private func scheduleExpiry(_ limit: ContinuousClock.Instant) {
        expiry?.cancel()
        let remaining = now().duration(to: limit)
        expiry = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: remaining) } catch { return }
            guard !Task.isCancelled, let self, self.deadline == limit else { return }
            self.retireExpiredObservation()
        }
    }
    private func transient(_ error: Error) -> Bool {
        if let error = error as? DJConnectError { return error.isTransientConnectivityFailure }
        guard let error = error as? URLError else { return false }
        return [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost, .dnsLookupFailed].contains(error.code)
    }

    /// Explicit open/tap/retry retains its existing separate fresh validation.
    /// Automatic refresh never overlaps it and waits ten seconds after dispatch.
    func read(catalogue: DJConnectAskDJCatalogue?, surface: DJConnectAskDJCatalogue.Surface,
              language: String, context: @escaping @MainActor () -> DJConnectAskDJCatalogue.Context,
              reader: Reader?, retainingCurrent: Bool = false) async -> [DJConnectAskDJCatalogue.CatalogueSection]? {
        if readTask != nil { return nil }
        let original = context()
        if retainingCurrent {
            guard allowsVisibleRefresh, originalContext == original else { return nil }
            generation = UUID()
        } else { close() }
        guard let catalogue, let reader else { return nil }
        let captured = generation, limit = now().advanced(by: .seconds(15))
        originalContext = original; automaticRead = retainingCurrent; busy = true
        if !retainingCurrent { deadline = limit }
        defer { if captured == generation { busy = false; readTask = nil; automaticRead = false } }
        do {
            let task = Task { @MainActor in
                guard !Task.isCancelled, captured == self.generation,
                      context() == original, self.now() < limit else { throw CancellationError() }
                self.lastDispatch = self.now()
                return try await reader(original, surface, language, limit)
            }
            readTask = task
            let observation = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            guard !Task.isCancelled, captured == generation, context() == original, now() < limit else {
                if captured == generation { close() }; return nil
            }
            guard observation.trackID == nil || observation.trackID == original.trackID else { close(); return nil }
            var admitted = original; admitted.serverEligibleIDs = observation.ids; admitted.trackID = observation.trackID
            if observation.trackID == nil {
                admitted.slots = [:]
                for key in ["current_track", "current_album", "forecast_ready"] { admitted.flags[key] = false }
            }
            let result = catalogue.catalogueSections(admitted, surface: surface, language: language,
                eligibleIDs: observation.ids, includeUnavailable: true)
            deadline = limit; admittedContext = admitted; sections = result
            unavailableReference = catalogue.catalogueSections(original, surface: surface, language: language,
                eligibleIDs: [], includeUnavailable: true)
            allowsVisibleRefresh = true
            scheduleExpiry(limit)
            return result
        } catch {
            guard captured == generation else { return nil }
            if retainingCurrent, !Task.isCancelled, context() == original, transient(error) {
                retireExpiredObservation() // Never extends the old deadline.
            } else { close() }
            return nil
        }
    }
    @discardableResult func refreshIfVisible(catalogue: DJConnectAskDJCatalogue?, surface: DJConnectAskDJCatalogue.Surface,
        language: String, visible: Bool, sceneActive: Bool,
        context: @escaping @MainActor () -> DJConnectAskDJCatalogue.Context, reader: Reader?) async -> Bool {
        guard visible, sceneActive, !Task.isCancelled else { close(); return false }
        guard allowsVisibleRefresh, !busy, readTask == nil,
              let lastDispatch, now() >= lastDispatch.advanced(by: .seconds(10)) else { return false }
        guard originalContext == context() else { close(); return false }
        return await read(catalogue: catalogue, surface: surface, language: language,
            context: context, reader: reader, retainingCurrent: true) != nil
    }
    var isCurrent: Bool { admittedContext != nil && deadline.map { now() < $0 } == true }
}

/// Only material playback/context inputs; ordinary progress, artwork and fresh
/// timestamp updates do not churn Help. Both sides use the same observation time.
struct AskDJHelpPlaybackProjection: Equatable {
    let state: String?
    let item: String?
    let title: String?
    let artist: String?
    let album: String?
    let source: String?
    let currentTrack: Bool
    init(_ playback: DJConnectSessionPlayback?, at now: Date) {
        state = playback?.state; item = playback?.itemID; title = playback?.title
        artist = playback?.artist; album = playback?.album; source = playback?.sourceURL
        if let stamp = DJConnectSessionForecast.timestamp(playback?.updatedAt) {
            currentTrack = (0..<30).contains(now.timeIntervalSince(stamp)) &&
                ["playing", "paused"].contains(state ?? "") && item?.isEmpty == false &&
                title?.isEmpty == false && artist?.isEmpty == false
        } else { currentTrack = false }
    }
}
