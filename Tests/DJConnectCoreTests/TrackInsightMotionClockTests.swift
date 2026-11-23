import Foundation
import Testing
import DJConnectCore
@testable import DJConnectUI

struct TrackInsightMotionClockTests {
    @Test func rateChangeNeverRepositionsExistingParticles() {
        var clock = TrackInsightMotionClock()
        clock.update(running: true, rate: 0.58, at: 800_000_000)
        let before = clock.frame(at: 800_000_010)
        clock.update(running: true, rate: 1.42, at: 800_000_010)
        #expect(clock.frame(at: 800_000_010) == before)
        let after = clock.frame(at: 800_000_011)
        #expect(abs(after.travel - before.travel - 1.42) < 0.000001)
        #expect(after.elapsed == 11)
    }

    @Test func routineViewUpdatesCannotResetPhase() {
        var clock = TrackInsightMotionClock()
        clock.update(running: true, rate: 0.8, at: 10)
        for second in 1...30 { clock.update(running: true, rate: 0.8, at: Double(10 + second)) }
        #expect(abs(clock.frame(at: 40).travel - 24) < 0.000001)
        #expect(clock.frame(at: 40).elapsed == 30)
    }

    @Test func pauseBackgroundAndReducedMotionFreezeThenResume() {
        var clock = TrackInsightMotionClock()
        clock.update(running: true, rate: 1, at: 10)
        clock.update(running: false, rate: 1, at: 15)
        let frozen = clock.frame(at: 15)
        #expect(clock.frame(at: 1000) == frozen)
        clock.update(running: true, rate: 1, at: 1000)
        #expect(clock.frame(at: 1000) == frozen)
        #expect(clock.frame(at: 1001).travel == frozen.travel + 1)
    }

    @Test func wholeTrackProgressDoesNotStopAtReadLeaseBoundaries() {
        let start = Date(timeIntervalSince1970: 1000)
        var playback = DJConnectPlayback(uri: "spotify:track:first", isPlaying: true,
            trackName: "Same title", artistName: "Artist", progressMS: 0, durationMS: 90_000)
        var anchor = TrackVibePlaybackAnchor()
        anchor.update(from: playback, at: start)
        for second in [14.0, 16, 30, 60, 90, 100] {
            let phase = TrackVibePlaybackPhase(playback: playback, anchor: anchor, date: start.addingTimeInterval(second))
            #expect(abs(phase.positionSeconds - min(second, 90)) < 0.001)
            #expect(abs(phase.progress - min(second / 90, 1)) < 0.001)
        }
        playback.progressMS = 40_000; playback.isPlaying = false
        anchor.update(from: playback, at: start.addingTimeInterval(40))
        #expect(TrackVibePlaybackPhase(playback: playback, anchor: anchor, date: start.addingTimeInterval(60)).positionSeconds == 40)
        playback.isPlaying = true
        anchor.update(from: playback, at: start.addingTimeInterval(60))
        #expect(TrackVibePlaybackPhase(playback: playback, anchor: anchor, date: start.addingTimeInterval(70)).positionSeconds == 50)
        playback.progressMS = 5_000
        anchor.update(from: playback, at: start.addingTimeInterval(70))
        #expect(TrackVibePlaybackPhase(playback: playback, anchor: anchor, date: start.addingTimeInterval(71)).positionSeconds == 6)
        playback.uri = "spotify:track:second"; playback.progressMS = 0
        anchor.update(from: playback, at: start.addingTimeInterval(71))
        #expect(TrackVibePlaybackPhase(playback: playback, anchor: anchor, date: start.addingTimeInterval(72)).positionSeconds == 1)
    }

    @Test func wrappedParticleIsInvisibleOnBothSidesOfSeam() {
        for seam in [-1000.0, 0, 1, 1000] {
            #expect(TrackInsightParticleWrap(seam).opacity == 0)
            #expect(TrackInsightParticleWrap(seam - 0.0001).opacity < 0.0001)
            #expect(TrackInsightParticleWrap(seam + 0.0001).opacity < 0.0001)
        }
        #expect(TrackInsightParticleWrap(0.5).opacity == 1)
        #expect(abs(TrackInsightParticleWrap(-0.25).position - 0.75) < 0.000001)
        #expect(TrackInsightParticleWrap(.infinity).opacity == 0)
    }

    @Test func populationChangesFadeInsteadOfPoppingWholeSparks() {
        #expect(TrackInsightParticleWrap.populationOpacity(index: 8, population: 8) == 0)
        #expect(TrackInsightParticleWrap.populationOpacity(index: 8, population: 8.25) == 0.25)
        #expect(TrackInsightParticleWrap.populationOpacity(index: 8, population: 9) == 1)
    }
}
