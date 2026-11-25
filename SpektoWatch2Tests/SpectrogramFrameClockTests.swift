import XCTest
@testable import SpektoWatch2

final class SpectrogramFrameClockTests: XCTestCase {

    private let sampleRate = 48_000.0

    /// Frames extracted from one tap burst must be spaced by hop/sampleRate,
    /// not share the callback's arrival time (which made the adapter see dt = 0).
    func testFramesWithinBurstAreSpacedByHop() {
        var clock = SpectrogramFrameClock()
        let arrival = 1_000.0
        clock.advance(arrivalTime: arrival, appendedSamples: 4800, sampleRate: sampleRate)

        let fftSize = 1024, hop = 400
        var buffered = 4800
        var stamps: [TimeInterval] = []
        while buffered >= fftSize {
            stamps.append(clock.frameTimestamp(samplesAfterFrameEnd: buffered - fftSize, sampleRate: sampleRate))
            buffered -= hop
        }

        XCTAssertEqual(stamps.count, 10)
        for (a, b) in zip(stamps, stamps.dropFirst()) {
            XCTAssertEqual(b - a, Double(hop) / sampleRate, accuracy: 1e-9)
        }
        // Newest frame ends at most one hop before the newest sample.
        XCTAssertLessThanOrEqual(stamps.last!, arrival)
        XCTAssertGreaterThan(stamps.last!, arrival - Double(hop) / sampleRate)
    }

    /// Steady callbacks advance the anchor by exactly the appended samples;
    /// scheduling jitter is only slewed in.
    func testAnchorFollowsSampleCountAndDampsJitter() {
        var clock = SpectrogramFrameClock()
        clock.advance(arrivalTime: 10.0, appendedSamples: 480, sampleRate: sampleRate)
        let jittered = 10.0 + 0.01 + 0.004   // 10 ms of audio, arrived 4 ms late
        let end = clock.advance(arrivalTime: jittered, appendedSamples: 480, sampleRate: sampleRate)
        XCTAssertEqual(end, 10.01 + 0.004 * SpectrogramFrameClock.slewFactor, accuracy: 1e-9)
    }

    func testLargeGapReanchorsToArrival() {
        var clock = SpectrogramFrameClock()
        clock.advance(arrivalTime: 10.0, appendedSamples: 480, sampleRate: sampleRate)
        let end = clock.advance(arrivalTime: 12.0, appendedSamples: 480, sampleRate: sampleRate)
        XCTAssertEqual(end, 12.0, accuracy: 1e-9)
    }

    func testTimestampsStayMonotonicAfterReset() {
        var clock = SpectrogramFrameClock()
        clock.advance(arrivalTime: 10.0, appendedSamples: 4800, sampleRate: sampleRate)
        let first = clock.frameTimestamp(samplesAfterFrameEnd: 0, sampleRate: sampleRate)
        clock.resetAnchor()
        // Re-anchored to an earlier arrival (e.g. clock adjustment): still monotonic.
        clock.advance(arrivalTime: 9.0, appendedSamples: 4800, sampleRate: sampleRate)
        let second = clock.frameTimestamp(samplesAfterFrameEnd: 0, sampleRate: sampleRate)
        XCTAssertGreaterThan(second, first)
    }

    // MARK: - RealtimeHop

    func testDisplayMatchedHop() {
        XCTAssertEqual(RealtimeHop.displayMatched(sampleRate: 48_000, displayFPS: 120), 400)
        XCTAssertEqual(RealtimeHop.displayMatched(sampleRate: 48_000, displayFPS: 60), 800)
        XCTAssertEqual(RealtimeHop.displayMatched(sampleRate: 44_100, displayFPS: 120), 368)
        XCTAssertEqual(RealtimeHop.displayMatched(sampleRate: 44_100, displayFPS: 60), 735)
    }

    func testResolveUsesConfiguredHopWhenMatchingOffAndClampsToFFTSize() {
        XCTAssertEqual(RealtimeHop.resolve(configuredHop: 1024, displayMatchedFPS: 0, sampleRate: 48_000, fftSize: 4096), 1024)
        XCTAssertEqual(RealtimeHop.resolve(configuredHop: 1024, displayMatchedFPS: 120, sampleRate: 48_000, fftSize: 4096), 400)
        XCTAssertEqual(RealtimeHop.resolve(configuredHop: 1024, displayMatchedFPS: 60, sampleRate: 48_000, fftSize: 512), 512)
        XCTAssertEqual(RealtimeHop.resolve(configuredHop: 0, displayMatchedFPS: 0, sampleRate: 48_000, fftSize: 4096), 1)
    }

    /// Large hops are capped so every widget gets ≥ 30 frames/s (≥ 24 fps target).
    func testResolveCapsHopAtMinimumFrameRate() {
        XCTAssertEqual(RealtimeHop.resolve(configuredHop: 4096, displayMatchedFPS: 0, sampleRate: 48_000, fftSize: 4096), 1600)
        XCTAssertEqual(RealtimeHop.resolve(configuredHop: 2048, displayMatchedFPS: 0, sampleRate: 44_100, fftSize: 4096), 1470)
        for hop in [256, 512, 1024, 2048, 4096] {
            for rate in [44_100.0, 48_000.0] {
                let resolved = RealtimeHop.resolve(configuredHop: hop, displayMatchedFPS: 0, sampleRate: rate, fftSize: 8192)
                XCTAssertGreaterThanOrEqual(rate / Double(resolved), RealtimeHop.minimumFrameRate)
            }
        }
    }

    func testClockReportsLastBufferDuration() {
        var clock = SpectrogramFrameClock()
        clock.advance(arrivalTime: 10.0, appendedSamples: 4800, sampleRate: sampleRate)
        XCTAssertEqual(clock.lastBufferDuration, 0.1, accuracy: 1e-12)
    }

    @MainActor
    func testEngineScrollSpeedPresetStillDrivesHop() {
        let engine = AudioEngine(filterManager: BandstopFilterManager(), connectivityManager: WatchConnectivityManager())
        engine.scrollSpeed = .fast
        XCTAssertEqual(engine.scrollSpeed, .fast)
        XCTAssertEqual(engine.realtimeHopSize, ScrollSpeed.fast.rawValue)

        // 1200 is below the 30 fps cap at both 44.1 and 48 kHz.
        engine.applyRealtimeHop(configuredHop: 1200, matchDisplayRefreshRate: false)
        XCTAssertEqual(engine.realtimeHopSize, 1200, "exact overlap hop, not the nearest preset")
        XCTAssertEqual(engine.scrollSpeed, .normal)

        // A 2048 hop is capped so widgets keep ≥ 30 frames/s.
        engine.applyRealtimeHop(configuredHop: 2048, matchDisplayRefreshRate: false)
        XCTAssertLessThan(engine.realtimeHopSize, 2048)
    }
}
