import Foundation
import Accelerate

/// Integrates per-band Leq for the Apple-Watch live source when the watch
/// payload omits pre-smoothed `bandLeq*` arrays (older watch builds). Owns the
/// dedicated `AcousticMetricsCalculator` and the last-ingest timestamp used to
/// derive the integration interval between watch packets.
///
/// Pure logic only: no UI work, no `@Published` state. `AudioEngine` keeps the
/// `ingestWearableSpectrogramData` UI-publish path and delegates the Leq
/// integration here.
///
/// Extracted from `AudioEngine` in VERBESSERUNGSPLAN Phase 3, Task 3.4. Logic
/// is verbatim.
final class WearableIngestCoordinator {
    private let metricsCalculator: AcousticMetricsCalculator
    private var lastIngestTime: Date?

    init(sampleRate: Double) {
        metricsCalculator = AcousticMetricsCalculator(sampleRate: sampleRate)
    }

    /// Clears the integrated metrics and the inter-packet timer. Mirrors the
    /// `AudioEngine.resetMetrics()` reset of the wearable side.
    func reset() {
        metricsCalculator.reset()
        lastIngestTime = nil
    }

    /// Integrates the watch spectrogram packet into per-band Leq metrics. `dt`
    /// is the wall-clock gap since the previous packet (first packet falls back
    /// to a nominal 2048-sample hop). `loudnessReferenceKey` is the broadband
    /// level key for the active weighting; `recordingDuration` is the current
    /// session duration.
    func integrateBandLeq(
        from data: SpectrogramData,
        thirdsZ: [Float],
        thirdsA: [Float],
        thirdsC: [Float],
        recordingDuration: TimeInterval,
        loudnessReferenceKey: String
    ) -> MetricsResult {
        let now = data.timestamp
        let dt: Float
        if let last = lastIngestTime {
            dt = Float(max(0, now.timeIntervalSince(last)))
        } else {
            dt = Float(2048) / Float(max(data.sampleRate, 1))
        }
        lastIngestTime = now

        func linearEnergy(levelKey: String, fallbackDB: Float) -> Float {
            let db = data.levels[levelKey] ?? fallbackDB
            return pow(10.0, db / 10.0)
        }

        let thirdsACount = SpectrumBandAggregator.thirdOctaveCenters.count
        return metricsCalculator.updateMetrics(
            energyZ: linearEnergy(levelKey: "LZF", fallbackDB: data.broadbandLevel),
            energyA: linearEnergy(levelKey: "LAF", fallbackDB: data.broadbandLevel),
            energyC: linearEnergy(levelKey: "LCF", fallbackDB: data.broadbandLevel),
            peakLevel: data.levels["LCpeak"] ?? data.broadbandLevel,
            dt: max(dt, 1e-4),
            recordingDuration: recordingDuration,
            frequencies: data.frequencies,
            magnitudes: data.magnitudes,
            bandsZ: thirdsZ,
            bandsA: thirdsA.count == thirdsACount ? thirdsA : [],
            bandsC: thirdsC.count == thirdsACount ? thirdsC : [],
            loudnessReferenceKey: loudnessReferenceKey
        )
    }
}
