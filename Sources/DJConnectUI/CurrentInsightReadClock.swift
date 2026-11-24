import Foundation

/// Internal read clock for deterministic original-lease race tests. Production
/// always uses the live clocks; no launch argument or persisted override exists.
@MainActor
struct CurrentInsightReadClock {
    var wallNow: () -> Date = { Date() }
    var monotonicNow: () -> ContinuousClock.Instant = { .now }
}

/// Internal deterministic seam for the owner preview's original receive clock.
/// Production has no persisted or launch-argument override.
@MainActor struct HorizonMomentReadClock {
    var wallNow: () -> Date = { Date() }
    var monotonicNow: () -> ContinuousClock.Instant = { .now }
}
