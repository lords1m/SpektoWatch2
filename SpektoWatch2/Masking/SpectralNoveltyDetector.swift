import Foundation

// Detects when the incoming spectrum deviates from the learned ambient background.
//
// Instead of watching for loud events (RMS threshold), this watches for spectral
// change — a quiet but spectrally distinct sound in a loud room will still be flagged.
//
// MC-8: all timing (ambient time constant, calibration period, cooldown) is
// derived from the frames' arrival times. The band feed arrives at the UI
// cadence (~60 Hz, ~10 Hz from the Watch), not at the 86 frames/s the old
// `sampleRate / hopSize` arithmetic assumed.
//
// All access must be on the main thread (same as AudioEngine band callbacks).
final class SpectralNoveltyDetector {

    // MARK: – Configuration

    private let ambientTimeConstant: Double
    private let calibrationSeconds: Double = 5.0
    private let cooldownSeconds: Double = 1.0

    // Mean absolute divergence per band that triggers a "novelty" notification
    var noveltyThresholdDB: Float = 4.0

    // MARK: – State

    private var ambientModel: [Float]
    private var framesProcessed: Int = 0
    private var firstFrameTime: TimeInterval?
    private var lastFrameTime: TimeInterval?
    private var lastNoveltyTime: TimeInterval = -.infinity

    // Smoothed novelty score (EMA with short time constant for UI display)
    private(set) var currentNoveltyScore: Float = 0.0
    private let scoreAlpha: Float = 0.2

    /// `true` once `calibrationSeconds` of frames have been seen.
    var isCalibrated: Bool {
        guard let first = firstFrameTime, let last = lastFrameTime, framesProcessed > 1 else { return false }
        return last - first >= calibrationSeconds
    }

    // Called when a novelty event is detected (above threshold, and model is calibrated)
    var onNoveltyDetected: (() -> Void)?

    // MARK: – Init

    /// `sampleRate` / `hopSize` are kept for source compatibility only.
    init(sampleRate: Double = 44100, hopSize: Int = 512, ambientTimeConstant: Double = 10.0) {
        self.ambientTimeConstant = max(0.001, ambientTimeConstant)
        ambientModel = [Float](repeating: 0, count: TriggerSpectrum.bandCount)
    }

    // MARK: – Update

    // Feed one frame of band data. Returns the novelty score for this frame [0…1].
    // Score is 0 when spectrum matches ambient, 1 when maximally divergent.
    @discardableResult
    func update(bands: [Float], at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Float {
        guard bands.count == TriggerSpectrum.bandCount else { return 0 }

        let dt: Double
        if let last = lastFrameTime {
            dt = max(0, min(time - last, 1.0))
        } else {
            dt = 0
        }
        if framesProcessed == 0 {
            ambientModel = bands
            firstFrameTime = time
        }
        lastFrameTime = time
        framesProcessed += 1

        // Novelty = mean absolute deviation from ambient model (dB)
        var divergenceSum: Float = 0
        for b in 0..<TriggerSpectrum.bandCount {
            let v = abs(bands[b] - ambientModel[b])
            divergenceSum += v.isFinite ? v : 0
        }
        let divergence = divergenceSum / Float(TriggerSpectrum.bandCount)

        // Normalise to [0…1]: 20 dB divergence maps to score ≈ 1
        let rawScore = min(divergence / 20.0, 1.0)
        currentNoveltyScore = scoreAlpha * rawScore + (1 - scoreAlpha) * currentNoveltyScore

        if isCalibrated && divergence >= noveltyThresholdDB && time - lastNoveltyTime >= cooldownSeconds {
            lastNoveltyTime = time
            onNoveltyDetected?()
        }

        // Update ambient model — slow EMA (time constant `ambientTimeConstant`)
        // so transient events don't corrupt the baseline. Only update when
        // the score is LOW so the model doesn't "learn" the trigger itself.
        if rawScore < 0.3, dt > 0 {
            let alpha = Float(1 - exp(-dt / ambientTimeConstant))
            for b in 0..<TriggerSpectrum.bandCount {
                ambientModel[b] = alpha * bands[b] + (1 - alpha) * ambientModel[b]
            }
        }

        return rawScore
    }

    // Snapshot the current ambient model (used by MaskingEngine to set ambientBands
    // on the accumulator after the calibration step).
    func snapshotAmbient() -> [Float] { ambientModel }

    func reset() {
        ambientModel = [Float](repeating: 0, count: TriggerSpectrum.bandCount)
        framesProcessed = 0
        firstFrameTime = nil
        lastFrameTime = nil
        lastNoveltyTime = -.infinity
        currentNoveltyScore = 0
    }
}
