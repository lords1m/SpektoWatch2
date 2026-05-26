import XCTest
@testable import SpektoWatch2

/// Unit and stress tests for `AcousticMetricsCalculator`.
///
/// ## Coverage
///
/// - Basic metric correctness (LAF, LAeq floor, histogram percentiles).
/// - **Concurrent-reset stress test** (M15 task-8 / AE-1):
///   A background task hammers `updateMetrics` while the test thread
///   repeatedly calls `reset()`. The OSAllocatedUnfairLock added in
///   task-8 must prevent torn / mixed-epoch accumulator state.
final class AcousticMetricsCalculatorTests: XCTestCase {

    // MARK: - Helpers

    /// Reasonable synthetic frame inputs at ~70 dB SPL.
    private func makeSyntheticFrame(
        energyLinear: Float = 1e-5,   // roughly 70 dB re 1 (calibrated externally)
        peak: Float = 75.0,
        dt: Float = 0.05,
        duration: TimeInterval = 0.0
    ) -> (z: Float, a: Float, c: Float, peak: Float, dt: Float, dur: TimeInterval) {
        (z: energyLinear, a: energyLinear, c: energyLinear,
         peak: peak, dt: dt, dur: duration)
    }

    // MARK: - Basic correctness

    /// A freshly initialised calculator should return floor-level readings.
    func testInitialLevelsAreAtFloor() {
        let calc = AcousticMetricsCalculator(sampleRate: 44100.0)
        let f = makeSyntheticFrame()
        let result = calc.updateMetrics(
            energyZ: f.z, energyA: f.a, energyC: f.c,
            peakLevel: f.peak, dt: f.dt, recordingDuration: f.dur
        )

        // After a single tiny-energy frame the exponential averager is still dominated
        // by the seed energy 1e-12. LAF should be close to the noise floor (≪ 0 dBFS).
        let laf = result.levels["LAF"]!
        XCTAssertLessThan(laf, 0.0, "Initial LAF should be well below 0 dBFS")
    }

    /// Feeding a sustained tone should drive LAF upward with each frame.
    func testLAFIncreasesWithSustainedTone() {
        let calc = AcousticMetricsCalculator(sampleRate: 44100.0)
        let energy: Float = 1e-3   // ~60 dB above seed

        var prevLAF: Float = -200.0
        for i in 0 ..< 20 {
            let result = calc.updateMetrics(
                energyZ: energy, energyA: energy, energyC: energy,
                peakLevel: 80.0, dt: 0.05,
                recordingDuration: Double(i) * 0.05
            )
            let laf = result.levels["LAF"]!
            XCTAssertGreaterThanOrEqual(laf, prevLAF,
                "LAF should be non-decreasing while feeding a sustained tone (frame \(i))")
            prevLAF = laf
        }
    }

    /// `LAFmin` must be ≤ `LAFmax` after any number of updates.
    func testMinIsNeverGreaterThanMax() {
        let calc = AcousticMetricsCalculator(sampleRate: 44100.0)
        for i in 0 ..< 50 {
            let energy = Float.random(in: 1e-10 ... 1e-2)
            let result = calc.updateMetrics(
                energyZ: energy, energyA: energy, energyC: energy,
                peakLevel: 90.0, dt: 0.02,
                recordingDuration: Double(i) * 0.02
            )
            XCTAssertLessThanOrEqual(result.levels["LAFmin"]!, result.levels["LAFmax"]!,
                "LAFmin > LAFmax at frame \(i)")
        }
    }

    /// After `reset()`, the first `updateMetrics` call starts from the initial seed.
    func testResetRestoresFloor() {
        let calc = AcousticMetricsCalculator(sampleRate: 44100.0)

        // Warm up with high-energy frames
        for i in 0 ..< 30 {
            _ = calc.updateMetrics(
                energyZ: 1.0, energyA: 1.0, energyC: 1.0,
                peakLevel: 120.0, dt: 0.05,
                recordingDuration: Double(i) * 0.05
            )
        }

        // Reset and feed one tiny frame
        calc.reset()
        let postReset = calc.updateMetrics(
            energyZ: 1e-12, energyA: 1e-12, energyC: 1e-12,
            peakLevel: 0.0, dt: 0.05,
            recordingDuration: 0.0
        )

        // LAFmax should be back near the noise floor, not the 120 dB from before
        XCTAssertLessThan(postReset.levels["LAFmax"]!, 0.0,
            "LAFmax after reset should be at floor, not carrying over pre-reset data")
    }

    /// `getStatistics()` should agree with the corresponding levels dict entry.
    func testGetStatisticsConsistency() {
        let calc = AcousticMetricsCalculator(sampleRate: 44100.0)
        let energy: Float = 5e-4

        var lastResult = MetricsResult(levels: [:], bandLeqZ: [], bandLeqA: [], bandLeqC: [])
        for i in 0 ..< 10 {
            lastResult = calc.updateMetrics(
                energyZ: energy, energyA: energy, energyC: energy,
                peakLevel: 85.0, dt: 0.1,
                recordingDuration: Double(i) * 0.1
            )
        }

        let stats = calc.getStatistics()
        // laeqFast from getStatistics == LAF from last updateMetrics
        XCTAssertEqual(stats.laeqFast, lastResult.levels["LAF"]!, accuracy: 0.01,
            "getStatistics().laeqFast should match last LAF level")
        XCTAssertEqual(stats.peak, lastResult.levels["LAFmax"]!, accuracy: 0.01,
            "getStatistics().peak should match LAFmax")
        XCTAssertEqual(stats.min, lastResult.levels["LAFmin"]!, accuracy: 0.01,
            "getStatistics().min should match LAFmin")
    }

    // MARK: - Histogram / percentiles

    /// LAF5 should be ≥ LAF95 (LAF5 = level exceeded 5 % of the time — the noisier end).
    func testLAF5IsGreaterOrEqualToLAF95() {
        let calc = AcousticMetricsCalculator(sampleRate: 44100.0)

        // Feed a mix of loud and quiet frames so the histogram has spread
        for i in 0 ..< 200 {
            let energy: Float = i % 3 == 0 ? 1e-2 : 1e-6
            _ = calc.updateMetrics(
                energyZ: energy, energyA: energy, energyC: energy,
                peakLevel: 80.0, dt: 0.05,
                recordingDuration: Double(i) * 0.05
            )
        }

        let result = calc.updateMetrics(
            energyZ: 1e-4, energyA: 1e-4, energyC: 1e-4,
            peakLevel: 80.0, dt: 0.05,
            recordingDuration: 10.05
        )

        let laf5  = result.levels["LAF5"]!
        let laf95 = result.levels["LAF95"]!
        XCTAssertGreaterThanOrEqual(laf5, laf95,
            "LAF5 (exceeded 5% of time) should be ≥ LAF95 (exceeded 95% of time)")
    }

    // MARK: - Thread-safety stress test (AE-1 / M15 task-8)

    /// Hammers `updateMetrics` from a background thread while `reset()` is called
    /// repeatedly from the test thread.
    ///
    /// **Pass criterion**: no crash, no Swift runtime exclusivity violation, and every
    /// `getStatistics()` snapshot taken immediately after `reset()` shows coherent state:
    /// `laeqFast` (LAF energy) must not be NaN or infinity — a torn Double write on the
    /// energy accumulator would manifest as garbage here.
    func testConcurrentUpdateAndResetDoesNotCrash() {
        let calc = AcousticMetricsCalculator(sampleRate: 44100.0)

        let iterationsPerBurst = 500
        let resetCount = 20
        let backgroundFinished = XCTestExpectation(description: "background-update-loop")

        // Background: tight updateMetrics loop
        Task.detached(priority: .userInitiated) {
            for i in 0 ..< (iterationsPerBurst * resetCount) {
                let energy = Float.random(in: 1e-10 ... 1e-2)
                _ = calc.updateMetrics(
                    energyZ: energy, energyA: energy, energyC: energy,
                    peakLevel: Float.random(in: 60.0 ... 120.0),
                    dt: 0.023,
                    recordingDuration: Double(i) * 0.023
                )
            }
            backgroundFinished.fulfill()
        }

        // Foreground: periodic resets, checking coherence after each
        for _ in 0 ..< resetCount {
            // Let the background task accumulate some frames first
            Thread.sleep(forTimeInterval: 0.002)
            calc.reset()

            // Immediately after reset the stats must be coherent (no NaN / ±∞)
            let stats = calc.getStatistics()
            XCTAssertFalse(stats.laeqFast.isNaN,
                "laeqFast must not be NaN immediately after reset")
            XCTAssertFalse(stats.laeqFast.isInfinite,
                "laeqFast must not be infinite immediately after reset")
            XCTAssertFalse(stats.peak.isNaN,
                "peak must not be NaN immediately after reset")
            XCTAssertFalse(stats.min.isNaN,
                "min must not be NaN immediately after reset")
        }

        wait(for: [backgroundFinished], timeout: 10.0)

        // Final sanity: the calculator is still usable after the storm
        let finalResult = calc.updateMetrics(
            energyZ: 1e-4, energyA: 1e-4, energyC: 1e-4,
            peakLevel: 80.0, dt: 0.05, recordingDuration: 0.0
        )
        XCTAssertFalse(finalResult.levels["LAF"]!.isNaN, "LAF must be valid after stress test")
        XCTAssertFalse(finalResult.levels["LAeq"]!.isNaN, "LAeq must be valid after stress test")
    }

    /// A second concurrent stress variant: two background tasks both calling
    /// `updateMetrics` simultaneously (reader-reader contention), no reset.
    /// Both should complete without crashing.
    func testTwoConcurrentUpdatersDoNotCrash() {
        let calc = AcousticMetricsCalculator(sampleRate: 44100.0)
        let done1 = XCTestExpectation(description: "updater-1")
        let done2 = XCTestExpectation(description: "updater-2")

        Task.detached(priority: .userInitiated) {
            for i in 0 ..< 1000 {
                _ = calc.updateMetrics(
                    energyZ: 1e-4, energyA: 1e-4, energyC: 1e-4,
                    peakLevel: 80.0, dt: 0.023,
                    recordingDuration: Double(i) * 0.023
                )
            }
            done1.fulfill()
        }

        Task.detached(priority: .userInitiated) {
            for i in 0 ..< 1000 {
                _ = calc.updateMetrics(
                    energyZ: 5e-5, energyA: 5e-5, energyC: 5e-5,
                    peakLevel: 75.0, dt: 0.023,
                    recordingDuration: Double(i) * 0.023
                )
            }
            done2.fulfill()
        }

        wait(for: [done1, done2], timeout: 10.0)

        let stats = calc.getStatistics()
        XCTAssertFalse(stats.laeqFast.isNaN,
            "laeqFast must be valid after dual-updater stress")
    }

    // MARK: - Per-band Leq EMA (M14 task-3)

    /// Feeding a constant band level seeds immediately on frame 1,
    /// then stays constant: EMA of a constant = that constant.
    func testBandLeqSeedsOnFirstFrameAndStaysConstant() {
        let calc = AcousticMetricsCalculator(sampleRate: 44100.0)
        let target: Float = 70.0
        let bands = [Float](repeating: target, count: 31)

        let seeded = calc.updateMetrics(
            energyZ: 1e-5, energyA: 1e-5, energyC: 1e-5,
            peakLevel: target, dt: 0.05, recordingDuration: 0.0,
            bandsZ: bands
        )
        XCTAssertEqual(seeded.bandLeqZ.count, 31,
            "bandLeqZ should have 31 entries after first frame")
        XCTAssertEqual(seeded.bandLeqZ[0], target, accuracy: 0.1,
            "Band Leq should be seeded at the first-frame value")

        // Constant input → EMA is idempotent
        var last = seeded
        for i in 1..<50 {
            last = calc.updateMetrics(
                energyZ: 1e-5, energyA: 1e-5, energyC: 1e-5,
                peakLevel: target, dt: 0.05,
                recordingDuration: Double(i) * 0.05,
                bandsZ: bands
            )
        }
        XCTAssertEqual(last.bandLeqZ[0], target, accuracy: 0.5,
            "Band Leq should stay at the constant input level after many frames")
    }

    /// Verifies that the per-band Leq EMA matches the closed-form expression
    /// `x_N = x0·(1−α)^N + x1·(1−(1−α)^N)` after a step from `seed` to `newTarget`.
    func testBandLeqEMAMatchesClosedForm() {
        let calc = AcousticMetricsCalculator(sampleRate: 44100.0)
        let alpha  = calc.leqBandAlpha          // 0.02
        let seed:      Float = 70.0             // dB — first frame seeds here
        let newTarget: Float = 50.0             // dB — subsequent frames
        let n = 31
        let seedBands      = [Float](repeating: seed,      count: n)
        let newTargetBands = [Float](repeating: newTarget, count: n)

        // Frame 1: seed
        _ = calc.updateMetrics(
            energyZ: 1e-5, energyA: 1e-5, energyC: 1e-5,
            peakLevel: seed, dt: 0.05, recordingDuration: 0.0,
            bandsZ: seedBands
        )

        // Frames 2…(N+1): apply EMA toward newTarget
        let N = 150
        var result = MetricsResult(levels: [:], bandLeqZ: [], bandLeqA: [], bandLeqC: [])
        for i in 1...N {
            result = calc.updateMetrics(
                energyZ: 1e-5, energyA: 1e-5, energyC: 1e-5,
                peakLevel: newTarget, dt: 0.05,
                recordingDuration: Double(i) * 0.05,
                bandsZ: newTargetBands
            )
        }

        // Closed-form: linear-domain EMA after N steps
        let linSeed   = pow(10.0, Double(seed)      / 10.0)
        let linNew    = pow(10.0, Double(newTarget)  / 10.0)
        let decay     = pow(Double(1.0 - alpha), Double(N))
        let expected  = Float(10.0 * log10(linSeed * decay + linNew * (1.0 - decay)))

        XCTAssertEqual(result.bandLeqZ[0], expected, accuracy: 0.5,
            "Band Leq EMA must match closed-form after \(N) frames")
    }

    /// After `reset()`, band Leq buffers are cleared: the next frame seeds fresh.
    func testBandLeqClearsOnReset() {
        let calc  = AcousticMetricsCalculator(sampleRate: 44100.0)
        let bands = [Float](repeating: 80.0, count: 31)

        // Warm up
        for i in 0..<30 {
            _ = calc.updateMetrics(
                energyZ: 1e-3, energyA: 1e-3, energyC: 1e-3,
                peakLevel: 80.0, dt: 0.05,
                recordingDuration: Double(i) * 0.05,
                bandsZ: bands
            )
        }

        calc.reset()

        let newBands = [Float](repeating: 40.0, count: 31)
        let postReset = calc.updateMetrics(
            energyZ: 1e-5, energyA: 1e-5, energyC: 1e-5,
            peakLevel: 40.0, dt: 0.05, recordingDuration: 0.0,
            bandsZ: newBands
        )
        // Buffer was cleared — first frame re-seeds at 40 dB, not at the pre-reset ~80 dB
        XCTAssertEqual(postReset.bandLeqZ[0], 40.0, accuracy: 0.5,
            "Band Leq must reseed at the new value after reset")
    }

    /// When `bandsA` is empty, `bandLeqA` in the result stays empty.
    func testBandLeqSkippedWhenBandsNotProvided() {
        let calc  = AcousticMetricsCalculator(sampleRate: 44100.0)
        let bandsZ = [Float](repeating: 60.0, count: 31)

        let result = calc.updateMetrics(
            energyZ: 1e-4, energyA: 1e-4, energyC: 1e-4,
            peakLevel: 60.0, dt: 0.05, recordingDuration: 0.0,
            bandsZ: bandsZ
            // bandsA and bandsC intentionally omitted (default [])
        )
        XCTAssertEqual(result.bandLeqZ.count, 31,
            "bandLeqZ must be populated when bandsZ is provided")
        XCTAssertTrue(result.bandLeqA.isEmpty,
            "bandLeqA must be empty when bandsA was not provided")
        XCTAssertTrue(result.bandLeqC.isEmpty,
            "bandLeqC must be empty when bandsC was not provided")
    }
}
