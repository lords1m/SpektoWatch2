import Foundation

// Detects when the incoming spectrum deviates from the learned ambient background.
//
// Instead of watching for loud events (RMS threshold), this watches for spectral
// change — a quiet but spectrally distinct sound in a loud room will still be flagged.
//
// All access must be on the main thread (same as AudioEngine band callbacks).
final class SpectralNoveltyDetector {

    // MARK: – Configuration

    // Time constant for the ambient model update: α ≈ 1/fps/τ
    // At 44100/512 ≈ 86 fps and τ = 10 s: α ≈ 0.0012
    private let alpha: Float
    private let framesPerSecond: Int

    // Mean absolute divergence per band that triggers a "novelty" notification
    var noveltyThresholdDB: Float = 4.0

    // Minimum number of frames before the model is considered calibrated
    private let minCalibrationFrames: Int

    // MARK: – State

    private var ambientModel: [Float]
    private var framesProcessed: Int = 0

    // Smoothed novelty score (EMA with short time constant for UI display)
    private(set) var currentNoveltyScore: Float = 0.0
    private let scoreAlpha: Float = 0.2

    var isCalibrated: Bool { framesProcessed >= minCalibrationFrames }

    // Cooldown: prevent onNoveltyDetected from firing more than once per second.
    // Without this it fires on every audio frame (~86×/s) for sustained events.
    private var noveltyDebounceFrames: Int = 0

    // Called when a novelty event is detected (above threshold, and model is calibrated)
    var onNoveltyDetected: (() -> Void)?

    // MARK: – Init

    init(sampleRate: Double = 44100, hopSize: Int = 512, ambientTimeConstant: Double = 10.0) {
        let fps = Float(sampleRate / Double(hopSize))
        alpha = 1.0 / (fps * Float(ambientTimeConstant))
        framesPerSecond = Int(fps)
        minCalibrationFrames = Int(fps * 5.0)   // 5 s of data before trusting the model
        ambientModel = [Float](repeating: 0, count: TriggerSpectrum.bandCount)
    }

    // MARK: – Update

    // Feed one frame of band data. Returns the novelty score for this frame [0…1].
    // Score is 0 when spectrum matches ambient, 1 when maximally divergent.
    @discardableResult
    func update(bands: [Float]) -> Float {
        guard bands.count == TriggerSpectrum.bandCount else { return 0 }

        if framesProcessed == 0 {
            ambientModel = bands
        }

        framesProcessed += 1

        // Novelty = mean absolute deviation from ambient model (dB)
        let divergence = zip(bands, ambientModel).reduce(0.0 as Float) { $0 + abs($1.0 - $1.1) }
                         / Float(TriggerSpectrum.bandCount)

        // Normalise to [0…1]: 20 dB divergence maps to score ≈ 1
        let rawScore = min(divergence / 20.0, 1.0)
        currentNoveltyScore = scoreAlpha * rawScore + (1 - scoreAlpha) * currentNoveltyScore

        if noveltyDebounceFrames > 0 { noveltyDebounceFrames -= 1 }
        if isCalibrated && divergence >= noveltyThresholdDB && noveltyDebounceFrames == 0 {
            noveltyDebounceFrames = framesPerSecond   // 1 s cooldown between callbacks
            onNoveltyDetected?()
        }

        // Update ambient model — slow EMA so transient events don't corrupt the baseline.
        // Only update when score is LOW (i.e., no trigger present), preventing
        // the ambient model from "learning" the trigger itself.
        if rawScore < 0.3 {
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
        currentNoveltyScore = 0
        noveltyDebounceFrames = 0
    }
}
