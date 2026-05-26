import Foundation
import Combine

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
    private var savedCalibrationOffset: Float = 0
    private var savedFrequencyWeighting: FrequencyWeighting = .a
    private var savedTimeWeighting: TimeWeighting = .fast
    private var savedBlockSize: FFTBlockSize = .size4096
    private var didStart = false

    // MARK: – Lifecycle

    /// Configure the main engine for recording playback.
    /// Call once in `RecordingDetailView.onAppear`.
    func start(engine: AudioEngine, recording: Recording) {
        guard !didStart else { return }
        didStart = true
        audioEngine = engine

        // Save current live-measurement settings before overwriting.
        savedCalibrationOffset   = engine.calibrationOffset
        savedFrequencyWeighting  = engine.frequencyWeighting
        savedTimeWeighting       = engine.timeWeighting
        savedBlockSize           = engine.currentBlockSize

        // Suspend live mic capture so playback samples are the only data
        // source entering the pipeline.
        engine.stopLiveMode()

        // Apply the recording's measurement parameters.
        engine.calibrationOffset = recording.calibrationOffset
        if let w = FrequencyWeighting(rawValue: recording.frequencyWeighting) {
            engine.setFrequencyWeighting(w)
        }
        if let t = TimeWeighting(rawValue: recording.timeWeighting) {
            engine.setTimeWeighting(t)
        }
        if let b = FFTBlockSize(rawValue: recording.fftBlockSize) {
            engine.setBlockSize(b)
        }
    }

    /// Restore the main engine to its live-measurement state.
    /// Call once in `RecordingDetailView.onDisappear`.
    func stop() {
        guard didStart, let engine = audioEngine else { return }
        didStart = false

        // Restore the user's live settings.
        engine.setBlockSize(savedBlockSize)
        engine.calibrationOffset = savedCalibrationOffset
        engine.setFrequencyWeighting(savedFrequencyWeighting)
        engine.setTimeWeighting(savedTimeWeighting)

        // Resume live mic capture.
        engine.startLiveMode()

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
