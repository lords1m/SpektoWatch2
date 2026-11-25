import Foundation
import AVFoundation
import Combine

// Central coordinator for the adaptive masking feature.
//
// Lifecycle:
//   idle → calibratingAmbient → waitingForTrigger ⇄ marking → ready(suggestion)
//
// The engine registers a band-data callback with AudioEngine so it can observe the
// live spectrum without touching the audio session. Only when entering preview/play
// mode does it pause AudioEngine and take over the session for playback.
//
// All methods must be called on the main thread (@MainActor).
@MainActor
final class MaskingEngine: ObservableObject {

    // MARK: – State machine

    enum State: Equatable {
        case idle
        case calibratingAmbient(secondsRemaining: Int)
        case waitingForTrigger
        case marking
        case ready(MaskerSuggestion)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.waitingForTrigger, .waitingForTrigger),
                 (.marking, .marking):
                return true
            case (.calibratingAmbient(let a), .calibratingAmbient(let b)):
                return a == b
            case (.ready, .ready):
                return true
            default:
                return false
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var captureCount: Int = 0
    @Published private(set) var convergenceScore: Float = 0.0
    @Published private(set) var noveltyScore: Float = 0.0
    @Published private(set) var currentTriggerSpectrum: TriggerSpectrum?

    // True while the central record button should route to beginMark/endMark
    // instead of starting a normal file recording.
    var isCapturingTrigger: Bool {
        switch state {
        case .waitingForTrigger, .marking: return true
        default: return false
        }
    }

    // Minimum captures before the engine considers the spectrum usable
    var minimumCaptures: Int = 3

    // MARK: – Sub-components

    private let accumulator     = TriggerSpectrumAccumulator()
    private let noveltyDetector = SpectralNoveltyDetector()
    let previewPlayer           = MaskingPreviewPlayer()

    // MARK: – Calibration timer

    private var calibrationTask: Task<Void, Never>?
    private let calibrationDuration: Int = 10   // seconds

    // MARK: – AudioEngine hook (weak to avoid retain cycle)

    private weak var audioEngine: AudioEngine?
    /// AS-6: session lease held while the masker preview plays.
    private var previewLease: AudioSessionCoordinator.Lease?
    /// AS-5: what live capture was doing before the preview suspended it.
    private var previewCaptureToken: AudioEngine.CaptureToken?

    // MARK: – Init

    init(audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
        wireAudioEngine(audioEngine)
        accumulator.onCaptureFinalized = { [weak self] captured in
            // Called from `feed` on the main actor (receiveBands).
            MainActor.assumeIsolated {
                guard let self else { return }
                if case .waitingForTrigger = self.state {
                    self.applyCaptureResult(captured)
                }
            }
        }

        noveltyDetector.onNoveltyDetected = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleNoveltyDetected()
            }
        }
    }

    // MARK: – Public API

    // Step 1: record ambient background (no trigger present) for `calibrationDuration` seconds.
    func startAmbientCalibration() {
        guard case .idle = state else { return }
        accumulator.reset()
        noveltyDetector.reset()
        state = .calibratingAmbient(secondsRemaining: calibrationDuration)

        calibrationTask = Task {
            for remaining in stride(from: calibrationDuration - 1, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                state = .calibratingAmbient(secondsRemaining: remaining)
            }
            finishAmbientCalibration()
        }
    }

    // Skip ambient calibration (no spectral subtraction will be applied).
    func skipAmbientCalibration() {
        calibrationTask?.cancel()
        finishAmbientCalibration()
    }

    // Step 2: user presses "Das war es" (called on touch-down)
    func beginMark() {
        guard case .waitingForTrigger = state else { return }
        accumulator.beginMark()
        state = .marking
    }

    // Step 2: user releases "Das war es" (called on touch-up)
    func endMark() {
        guard case .marking = state else { return }
        let accepted = accumulator.endMark()
        state = .waitingForTrigger
        // MC-8: with a post-mark window the capture finishes once those
        // frames have arrived (`onCaptureFinalized`); otherwise it's done now.
        if !accumulator.isCapturePending {
            applyCaptureResult(accepted)
        }
    }

    private func applyCaptureResult(_ captured: Bool) {
        captureCount = accumulator.captureCount
        convergenceScore = accumulator.convergenceScore
        currentTriggerSpectrum = accumulator.currentSpectrum()
        if captured && accumulator.captureCount >= minimumCaptures && convergenceScore >= 0.7 {
            computeSuggestion()
        }
    }

    // Force suggestion computation before convergence threshold is met.
    func computeSuggestionNow() {
        computeSuggestion()
    }

    // Load a preset trigger instead of recording.
    func usePreset(_ preset: TriggerPreset) {
        accumulator.reset()
        currentTriggerSpectrum = preset.spectrum
        let suggestion = MaskerSuggestionEngine.suggest(
            for: preset.spectrum,
            calibrationOffset: audioEngine?.effectiveCalibrationOffset ?? CalibrationProvider.defaultOffset
        )
        state = .ready(suggestion)
    }

    // Restore a previously saved profile — uses the stored masker settings directly.
    func useProfile(_ profile: MaskingProfile) {
        accumulator.reset()
        currentTriggerSpectrum = profile.triggerSpectrum
        let suggestion = MaskerSuggestion(
            maskerType: profile.maskerType,
            eqBands: profile.eqBands,
            volumedBFS: profile.volumedBFS,
            confidenceScore: 1.0
        )
        state = .ready(suggestion)
    }

    // MARK: – Preview

    // Start masker playback. Suspends live capture (remembering what was
    // running) and takes a masking-preview session lease (AS-5 / AS-6).
    func startPreview(suggestion: MaskerSuggestion) {
        if previewPlayer.isPlaying {
            updateMasker(suggestion)
            return
        }
        // Never tear down an active file recording for a preview (DL-1).
        if audioEngine?.recording.isRecordingToFile == true { return }

        previewCaptureToken = audioEngine?.suspendCapture()
        do {
            if previewLease == nil {
                previewLease = try AudioSessionCoordinator.shared.acquire(.maskingPreview)
            }
            try previewPlayer.play(maskerType: suggestion.maskerType,
                                   eqBands: suggestion.eqBands,
                                   volumeDB: suggestion.volumedBFS)
        } catch {
            // Restore on failure so the user isn't left in a broken state
            stopPreview()
        }
    }

    /// AS-6: swaps the masker generator while previewing without touching
    /// live capture or the audio session (no async stop→start round trip).
    func updateMasker(_ suggestion: MaskerSuggestion) {
        guard previewPlayer.isPlaying else { return }
        previewPlayer.stop()
        do {
            try previewPlayer.play(maskerType: suggestion.maskerType,
                                   eqBands: suggestion.eqBands,
                                   volumeDB: suggestion.volumedBFS)
        } catch {
            stopPreview()
        }
    }

    // Stop masker playback, end the lease and restore exactly the capture
    // state that was active before the preview (AS-5: nothing is forced on).
    func stopPreview() {
        previewPlayer.stop()
        if let lease = previewLease {
            AudioSessionCoordinator.shared.release(lease)
            previewLease = nil
        }
        if let token = previewCaptureToken {
            previewCaptureToken = nil
            audioEngine?.resumeCapture(token)
        }
    }

    // Reset everything back to idle.
    func reset() {
        stopPreview()
        calibrationTask?.cancel()
        accumulator.reset()
        noveltyDetector.reset()
        captureCount = 0
        convergenceScore = 0
        noveltyScore = 0
        currentTriggerSpectrum = nil
        state = .idle
    }

    // MARK: – Private

    private func wireAudioEngine(_ engine: AudioEngine) {
        // MaskingEngine always receives Z-weighted (unweighted linear) 1/3-octave
        // bands, regardless of the user's active frequency weighting. This is
        // intentional: the masking ambient model and novelty detector are trained
        // on psychoacoustic Z-band structure; A- or C-weighting would shift the
        // spectral shape and cause the trigger threshold to drift when the user
        // changes the display weighting. `AudioEngine.onBandsUpdated` is wired to
        // `octaveBandsZ` in `updateUI` — do not change it to the active-weighting
        // array (R11 correctness fix).
        // The callback is set to nil when MaskingEngine is deallocated.
        engine.onBandsUpdated = { [weak self] bands, rmsDB in
            Task { @MainActor [weak self] in
                self?.receiveBands(bands, rmsDB: rmsDB)
            }
        }
    }

    private func receiveBands(_ bands: [Float], rmsDB: Float) {
        // Don't feed the accumulator when in idle or when preview is active.
        guard !previewPlayer.isPlaying else { return }
        guard case .idle = state else {
            accumulator.feed(bands: bands, rmsDB: rmsDB)
            noveltyDetector.update(bands: bands)
            noveltyScore = noveltyDetector.currentNoveltyScore
            return
        }
    }

    private func finishAmbientCalibration() {
        calibrationTask?.cancel()
        accumulator.ambientBands = noveltyDetector.snapshotAmbient()
        state = .waitingForTrigger
    }

    private func handleNoveltyDetected() {
        // Optional: surface a subtle pulse in the UI via noveltyScore (already @Published)
        // Intentionally does NOT auto-trigger a mark — the user decides what the trigger is.
    }

    private func computeSuggestion() {
        guard let spectrum = accumulator.currentSpectrum() else { return }
        currentTriggerSpectrum = spectrum
        let suggestion = MaskerSuggestionEngine.suggest(
            for: spectrum,
            calibrationOffset: audioEngine?.effectiveCalibrationOffset ?? CalibrationProvider.defaultOffset
        )
        state = .ready(suggestion)
    }
}
