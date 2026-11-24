import Foundation
import Combine
import os

// PlaybackAnalyzer — recording playback DSP coordinator (M14 task-8, R1).
//
// Routes recording-playback audio through the shared main AudioEngine rather
// than constructing a second full engine. During playback the main engine's
// live mic capture is suspended and its pipeline processes the playback samples
// instead, publishing SpectrogramData to all existing SwiftUI consumers unchanged.
//
// Lifecycle:
//   1. `RecordingDetailView.onAppear` calls `start(engine:recording:)`.
//      The main engine's current settings are saved and it is reconfigured
//      for the recording's calibration offset, frequency weighting, time
//      weighting, and FFT block size.
//   2. `audioPlayer.onAudioSamples` calls `processSamples(_:sampleRate:)`.
//   3. `RecordingDetailView.onDisappear` calls `stop()` to restore all saved
//      settings and resume live mic capture.
//
// Why not a second AudioEngine?
//   Constructing AudioEngine(filterManager:connectivityManager:) allocates a
//   WatchConnectivityManager, a BandstopFilterManager, a SpectrogramProcessor
//   EMA history, and all @Published SwiftUI state. Two complete DSP pipelines
//   are alive during playback — that is the R1 redundancy this class removes.
//
// Why not a dedicated FFTProcessor + SpectrogramProcessor inside this class?
//   HighEndSpectrogramAdapterWithAxes and WidgetCardView both take
//   `audioEngine: AudioEngine` directly. Rather than introducing an
//   AudioEngineProtocol across ~12 consumer files (Phase 3, future work),
//   this class reuses the existing pipeline and its already-observable state.
//
// Thread safety: all methods must be called on the main thread (@MainActor).

@MainActor
final class PlaybackAnalyzer: ObservableObject {

    // MARK: – Private state

    private weak var audioEngine: AudioEngine?

    // Saved main-engine settings — restored when `stop()` is called so the
    // user's live measurement configuration is not permanently affected by
    // playback.
    private var savedFrequencyWeighting: FrequencyWeighting = .a
    private var savedTimeWeighting: TimeWeighting = .fast
    private var savedBlockSize: FFTBlockSize = .size4096
    private var didStart = false
    /// AS-5: what live capture was doing before playback took over.
    private var captureToken: AudioEngine.CaptureToken?

    // MARK: – Lifecycle

    /// Configure the main engine for recording playback.
    /// Call once in `RecordingDetailView.onAppear`.
    ///
    /// Returns `false` (and leaves the engine untouched) while a file
    /// recording is in progress — stopping live mode then would close the
    /// writers and the recording would never reach the list (DL-1).
    @discardableResult
    func start(engine: AudioEngine, recording: Recording) -> Bool {
        guard !didStart else { return true }
        guard !Self.isRecordingInProgress(engine) else {
            Logger.audioEngine.warning("PlaybackAnalyzer.start ignored: file recording in progress")
            return false
        }
        didStart = true
        audioEngine = engine

        // Save current live-measurement settings before overwriting.
        savedFrequencyWeighting  = engine.frequencyWeighting
        savedTimeWeighting       = engine.timeWeighting
        savedBlockSize           = engine.currentBlockSize

        // Suspend live capture (iPhone mic or Watch stream) so playback
        // samples are the only data source entering the pipeline. The token
        // remembers what was running (AS-5).
        captureToken = engine.suspendCapture()

        // Apply the recording's measurement parameters. Calibration goes
        // through the non-persisted override (DL-10) so the user's stored
        // calibration is never replaced, even if the app dies mid-playback.
        engine.setCalibrationOverride(recording.calibrationOffset)
        if let w = FrequencyWeighting(rawValue: recording.frequencyWeighting) {
            engine.setFrequencyWeighting(w)
        }
        if let t = TimeWeighting(rawValue: recording.timeWeighting) {
            engine.setTimeWeighting(t)
        }
        if let b = FFTBlockSize(rawValue: recording.fftBlockSize) {
            engine.setBlockSize(b)
        }
        return true
    }

    /// `true` while the engine is writing a recording to disk.
    static func isRecordingInProgress(_ engine: AudioEngine) -> Bool {
        engine.recording.isRecordingToFile
    }

    /// Restore the main engine to its live-measurement state.
    /// Call once in `RecordingDetailView.onDisappear`.
    func stop() {
        guard didStart, let engine = audioEngine else { return }
        didStart = false

        // Restore the user's live settings.
        engine.setBlockSize(savedBlockSize)
        engine.setCalibrationOverride(nil)
        engine.setFrequencyWeighting(savedFrequencyWeighting)
        engine.setTimeWeighting(savedTimeWeighting)

        // Restore exactly the pre-playback capture state — an idle engine
        // stays idle, a Watch-sourced session resumes the Watch source (AS-5).
        if let token = captureToken {
            engine.resumeCapture(token)
        }
        captureToken = nil

        audioEngine = nil
    }

    // MARK: – DSP bridge

    /// Feed a block of playback samples into the main engine's pipeline.
    /// Mirrors `AudioEngine.processExternalAudio`.
    func processSamples(_ samples: [Float], sampleRate: Double) {
        audioEngine?.processExternalAudio(samples, sampleRate: sampleRate)
    }

    /// Update frequency weighting mid-playback (user toggles A/C/Z).
    func setFrequencyWeighting(_ weighting: FrequencyWeighting) {
        audioEngine?.setFrequencyWeighting(weighting)
    }
}
