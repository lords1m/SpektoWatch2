import XCTest
@testable import SpektoWatch2

/// Characterization tests locking the behaviour of the three `AudioEngine`
/// paths that the Phase-3 strangler extractions will touch
/// (VERBESSERUNGSPLAN Phase 3, Task 3.1):
///
/// 1. Sample buffering / offset compaction (`sampleBuffer` / `sampleBufferOffset`)
/// 2. UI throttling intervals (60 Hz / 15 Hz)
/// 3. Wearable ingest fallback-Leq integration (`wearableMetricsCalculator`,
///    `lastWearableIngestTime`)
///
/// These pin OBSERVABLE behaviour, not implementation details, so they keep
/// passing across the AudioCaptureSession / ProcessingPipeline /
/// WearableIngestCoordinator / UIPublishThrottle extractions.
@MainActor
final class AudioEngineCharacterizationTests: XCTestCase {

    private func makeEngine() -> AudioEngine {
        AudioEngine(
            filterManager: BandstopFilterManager(),
            connectivityManager: WatchConnectivityManager()
        )
    }

    // MARK: - 1. Sample buffer / offset reassembly

    /// The offset-based ring (O(1) `removeFirst`) must reassemble FFT frames
    /// identically regardless of how the incoming samples are chunked, as long
    /// as the total stays under the real-time backlog-drop limit (~0.12 s).
    /// 5120 samples (= one 4096 window + one 1024 hop) crosses a frame boundary
    /// while staying below the drop threshold, so the streamed and one-shot
    /// engines must produce identical accumulated metrics.
    func testSampleBufferChunkingInvarianceUnderBacklogLimit() {
        let total = 5120
        let signal: [Float] = (0..<total).map { sin(2 * .pi * Float($0) / 64.0) * 0.5 }

        let oneShot = makeEngine()
        oneShot.processExternalAudio(signal)

        let streamed = makeEngine()
        for start in stride(from: 0, to: total, by: 1024) {
            streamed.processExternalAudio(Array(signal[start..<min(start + 1024, total)]))
        }

        let a = oneShot.getRecordingStatistics()
        let b = streamed.getRecordingStatistics()

        XCTAssertEqual(a.laeqFast, b.laeqFast, accuracy: 0.01,
                       "LAeq must be chunking-invariant below the backlog limit")
        XCTAssertEqual(a.peak, b.peak, accuracy: 0.01,
                       "Peak must be chunking-invariant below the backlog limit")
        XCTAssertEqual(a.min, b.min, accuracy: 0.01,
                       "Min must be chunking-invariant below the backlog limit")
    }

    /// Feeding samples incrementally must accumulate across calls: two half-FFT
    /// chunks together yield the same metrics as one full-FFT chunk. Guards the
    /// cross-call buffer persistence the ProcessingPipeline extraction inherits.
    func testSampleBufferAccumulatesAcrossCalls() {
        let signal: [Float] = (0..<4096).map { sin(2 * .pi * Float($0) / 50.0) * 0.4 }

        let split = makeEngine()
        split.processExternalAudio(Array(signal[0..<2048]))
        let afterFirstHalf = split.getRecordingStatistics()
        // No full FFT window yet → no frame processed → metrics still at reset.
        XCTAssertLessThanOrEqual(afterFirstHalf.peak, 0,
                                 "No frame should be processed before a full window arrives")
        split.processExternalAudio(Array(signal[2048..<4096]))

        let whole = makeEngine()
        whole.processExternalAudio(signal)

        XCTAssertEqual(split.getRecordingStatistics().laeqFast,
                       whole.getRecordingStatistics().laeqFast, accuracy: 0.01,
                       "Split feed must match single feed once a full window is buffered")
    }

    // MARK: - 2. UI throttling intervals

    /// The live-metric and spectrogram publish cadences are the contract for the
    /// planned `UIPublishThrottle`. Pin the exact 60 Hz / 15 Hz values.
    func testUIThrottleIntervalsMatchTargetRates() {
        let engine = makeEngine()
        XCTAssertEqual(engine.targetUIInterval, 1.0 / 60.0, accuracy: 1e-9,
                       "Live-metric publish cadence must stay 60 Hz")
        XCTAssertEqual(engine.targetSpectrogramUIInterval, 1.0 / 15.0, accuracy: 1e-9,
                       "Spectrogram publish cadence must stay 15 Hz")
    }

    // MARK: - 3. Wearable ingest fallback Leq

    /// When the watch payload carries no per-band Leq arrays (`bandLeqZ` absent),
    /// the engine must integrate them from the spectrogram via
    /// `integrateWearableBandLeq` and publish into `live.bandLeqZ`. Older watch
    /// builds rely on this fallback.
    func testWearableIngestFallbackIntegratesBandLeqWhenAbsent() {
        let expectation = XCTestExpectation(description: "Fallback band Leq integrated")
        let data = SpectrogramData(
            frequencies: [100, 200, 500, 1_000, 2_000, 4_000],
            magnitudes: [45, 52, 60, 55, 50, 48],
            broadbandLevel: 63.0,
            levels: ["LZF": 63.0, "LAF": 61.0, "LCF": 62.0, "LCpeak": 73.0],
            sampleRate: 44_100
        )

        let engine = makeEngine()
        engine.startWearableLiveMode()
        engine.ingestWearableSpectrogramData(data)
        // Second ingest exercises the `lastWearableIngestTime` dt branch.
        engine.ingestWearableSpectrogramData(data)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            XCTAssertEqual(engine.activeMicrophoneSource, .appleWatch)
            XCTAssertFalse(engine.live.bandLeqZ.isEmpty,
                           "Fallback integration must populate live.bandLeqZ when payload omits it")
            XCTAssertEqual(engine.live.levelHistory.last ?? .nan, data.broadbandLevel, accuracy: 0.001)
            engine.stopWearableLiveMode()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }
}
