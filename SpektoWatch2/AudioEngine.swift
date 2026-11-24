import Foundation
import AVFoundation
import Accelerate
import Combine
import os
import os.signpost
#if canImport(UIKit)
import UIKit
#endif

enum ScrollSpeed: Int, CaseIterable {
    case verySlow = 4096  // ~10 FPS
    case slow = 2048      // ~21 FPS
    case normal = 1024    // ~43 FPS
    case fast = 512       // ~86 FPS
    case veryFast = 256   // ~172 FPS
    
    var label: String {
        switch self {
        case .verySlow: return String(localized: "scroll_speed.very_slow")
        case .slow: return String(localized: "scroll_speed.slow")
        case .normal: return String(localized: "scroll_speed.normal")
        case .fast: return String(localized: "scroll_speed.fast")
        case .veryFast: return String(localized: "scroll_speed.very_fast")
        }
    }

    static func closest(to hopSize: Int) -> ScrollSpeed {
        let target = max(1, hopSize)
        return allCases.min { abs($0.rawValue - target) < abs($1.rawValue - target) } ?? .fast
    }
}

enum EngineStatus: Equatable {
    case idle
    case starting
    case running
    case error(String)
}

enum StereoInputMode: String, CaseIterable {
    case bottomBack
    case frontBack
    case frontBottom

    /// Localized picker label. Raw values are stable English keys (not persisted).
    var displayName: String {
        switch self {
        case .bottomBack: return String(localized: "stereo_input.bottom_back")
        case .frontBack: return String(localized: "stereo_input.front_back")
        case .frontBottom: return String(localized: "stereo_input.front_bottom")
        }
    }
}

/// Main audio engine coordinating FFT processing, frequency weighting, and acoustic metrics
class AudioEngine: ObservableObject {
    private static let performanceLog = OSLog(subsystem: "com.spektowatch", category: "performance.audio")
    // Canonical third-octave centers live in
    // `Managers/SpectrumBandAggregator.swift` (M13 task-6); the empty-band
    // fallback now lives in `ProcessingPipeline`.

    // MARK: - Processing Components

    private var fftProcessor: FFTProcessor
    private var weightingProcessor: FrequencyWeightingProcessor
    private let metricsCalculator: AcousticMetricsCalculator
    /// Integrates per-band Leq when the Apple Watch is the live mic and the
    /// payload omits pre-smoothed `bandLeq*` arrays (older watch builds).
    /// Owns the wearable metrics calculator + inter-packet timer
    /// (extracted in Phase 3, Task 3.4).
    private let wearableIngest: WearableIngestCoordinator
    private let spectrogramProcessor: SpectrogramProcessor
    /// Pure per-frame DSP (FFT → weighting → bands → energies → LCpeak) and the
    /// real-time scratch buffers (extracted in Phase 3, Task 3.3). Driven only
    /// from the audio render thread via `processFFTFrame`.
    ///
    /// RT-1: immutable per FFT size. Main builds a replacement (with its
    /// scratch preallocated) and swaps the reference under `processingLock`;
    /// the render thread snapshots it at the top of each frame together with
    /// the processors, so it never sees scratch being resized underneath it.
    private var processingPipeline = ProcessingPipeline(energyCount: FFTBlockSize.size4096.rawValue / 2)
    /// RT-1/RT-5: replaced DSP objects are kept alive on main for a moment so
    /// the render thread never drops the last reference (no dealloc on RT).
    private var retiredDSPObjects: [AnyObject] = []
    /// RT-5: preallocated per-frame metric value buffer (render thread only).
    private var metricValuesScratch: [Float] = []
    private let testGenerator: TestAudioGenerator
    private let bandstopFilterManager: BandstopFilterManager
    private let connectivityManager: WatchConnectivityManager

    // MARK: - Audio Engine

    /// Owns the AVAudioEngine capture graph, session/stereo configuration, tap,
    /// and prewarming (extracted in Phase 3, Task 3.2). Created on first capture
    /// start so `AudioEngine` init stays off the hot AVAudioEngine graph-build
    /// path during deferred `AppServices.startAudio()`. `onBuffer` is wired to
    /// `processAudioBuffer` (called on the audio render thread).
    private lazy var captureSession: AudioCaptureSession = {
        let session = AudioCaptureSession(tapBlockSize: tapBlockSize, nominalSampleRate: sampleRate)
        session.onBuffer = { [weak self] buffer in
            self?.processAudioBuffer(buffer)
        }
        // AS-1: AVAudioEngine stops itself on I/O configuration changes
        // (route change, sample-rate change); restart instead of leaving the
        // UI in `.running` with a dead graph.
        session.onConfigurationChange = { [weak self] in
            self?.restartCaptureAfterDisruption(reason: "configuration change")
        }
        return session
    }()
    private var fftSize: Int = FFTBlockSize.size4096.rawValue
    private let tapBlockSize: AVAudioFrameCount = 512
    private let sampleRate: Double = 44100.0
    private var processingSampleRate: Double = 44100.0

    // MARK: - FFT Configuration

    /// Aktuelle Fensterfunktion
    @Published var currentWindowFunction: WindowFunction = .hann
    /// Aktuelle Blockgröße
    @Published var currentBlockSize: FFTBlockSize = .size4096
    
    // MARK: - Buffer Management

    /// Offset-based FFT-window accumulator (sampleBuffer/offset/frame scratch).
    /// Always touched under `processingLock`.
    private let sampleRing = SampleRingBuffer()
    private var gainBoost: Float = 10.0 {
        didSet {
            rtSettingsLock.withLock { $0.gainBoost = gainBoost }
        }
    }

    // Reusable scratch buffer for the mono channel of an incoming audio callback.
    // Avoids allocating a fresh `[Float]` per buffer (typical iOS audio buffer is
    // 256–4096 frames; at ~100 callbacks/sec that was ~1 MB/sec of churn).
    private var monoSampleScratch: [Float] = []

    // Lock for thread-safe FFT reconfiguration.
    //
    // Read by the audio render callback (`processSamples`, `processFFTFrame`)
    // every audio buffer and written by main-thread setters when the user
    // picks a different FFT size or window function. `OSAllocatedUnfairLock`
    // is roughly an order of magnitude cheaper than `NSLock` in the
    // contention-free steady state and — critically — does not call into
    // `pthread_mutex_lock`, so an acquisition on the audio render thread
    // cannot trigger a kernel mutex wait or priority inversion under thermal
    // pressure. Matches the pattern already used by `FFTProcessor`.
    private let processingLock = OSAllocatedUnfairLock()

    // MARK: - Real-Time Thread Mirrors

    private struct RTSettings {
        var calibrationOffset: Float = CalibrationProvider.defaultOffset
        var frequencyWeighting: FrequencyWeighting = .a
        var scrollSpeed: ScrollSpeed = .normal
        var gainBoost: Float = 10.0
        var recordingStartTime: Date? = nil
    }

    private struct RTPerfStats {
        var lastAudioBufferTimestamp: TimeInterval = 0
        var fftProcessTimeAccumMs: Double = 0
        var fftProcessCount: Int = 0
        var maxBufferedSeconds: Double = 0
    }

    private struct RTStereoState {
        var isStereo: Bool = false
        var phase: Float = 1.0
    }

    private let rtSettingsLock = OSAllocatedUnfairLock<RTSettings>(initialState: RTSettings())
    private let rtPerfLock = OSAllocatedUnfairLock<RTPerfStats>(initialState: RTPerfStats())
    private let rtStereoLock = OSAllocatedUnfairLock<RTStereoState>(initialState: RTStereoState())

    // MARK: - State Management

    private var isUsingDummyData = false
    private var isStartingCapture = false
    /// AS-7: bumped by every stop so a capture start that is still
    /// configuring the session in the background cannot flip the engine back
    /// to `.running` after the user (or a suspend) stopped it.
    private var captureGeneration: UInt64 = 0
    /// AS-1: `true` while an audio-session interruption (call, Siri, …) has
    /// paused the iPhone mic. Recording files stay open.
    @Published private(set) var isCaptureInterrupted = false
    private var sessionEventsCancellable: AnyCancellable?

    /// AS-2 / Q3: the synthetic test-audio fallback after a mic failure is a
    /// debugging aid only — release builds surface the error instead of
    /// presenting synthetic audio as a measurement.
    static var allowsSyntheticFallback: Bool {
        #if DEBUG
        return UITestRuntime.useTestAudio
            || ProcessInfo.processInfo.environment["SPEKTO_SYNTHETIC_FALLBACK"] == "1"
        #else
        return false
        #endif
    }
    private var debugPrintCounter = 0
    private let maxHistorySize = 1000
    private var latencyLogCounter = 0
    private let enableVerboseLogs = false
    private let enableSpectrumDiagnostics = ProcessInfo.processInfo.environment["SPEKTO_DEBUG_SPECTRUM"] == "1"
    /// Pure timing gates for the publish path: 60 Hz UI / 15 Hz spectrogram /
    /// 0.1 s watch send (extracted in Phase 3, Task 3.5). Internal so the
    /// characterization tests can pin the cadences.
    let uiThrottle = UIPublishThrottle()

    /// Direct high-rate subject for spectrogram renderers — does NOT trigger objectWillChange.
    let spectrogramSubject = PassthroughSubject<SpectrogramData, Never>()
    private let maxRealtimeBacklogSeconds: Double = 0.12
    /// Live input-signal diagnostics (impulse latency + silence warning) that
    /// span the audio render thread and the UI publish path.
    private let signalMonitor = InputSignalMonitor()
    private var spectrumDiagnosticsCounter = 0
    private var lastObservedInputSampleRate: Double = 44100.0
    // State-isolated unfair lock matches the M6 task-6 pattern: the audio
    // render path reads via `withLockUnchecked`, callers from main mutate
    // via `withLock`. Replaces an `NSLock` that was reachable from
    // `processFFTFrame` via `requiredSpectralWeightingsForCurrentFrame`.
    private let widgetSpectralWeightingsLock = OSAllocatedUnfairLock<Set<FrequencyWeighting>>(initialState: [])

    /// Guards whether any visible widget requires pre-aggregated Bark bands.
    /// Read on the audio render thread via `withLockUnchecked`; written on
    /// main via `setWidgetBarkBandsRequired(_:)`.
    private let widgetBarkBandsRequiredLock = OSAllocatedUnfairLock<Bool>(initialState: false)

    /// AE-5: Measurement frame write errors are stored here on the audio render thread
    /// (Logger is not RT-safe). The `updateUI` main-thread block drains and logs it.
    private let lastWriteErrorLock = OSAllocatedUnfairLock<String?>(initialState: nil)

    // MARK: - Microphone Calibration
    // Device map, recommended-offset lookup, and load/save logic live
    // in CalibrationProvider (M13 task-3). This file owns only the
    // active runtime value + its didSet persistence, so the settings
    // slider's `$audioEngine.calibrationOffset` binding still works.
    // dB SPL = dBFS + calibrationOffset.
    @Published var calibrationOffset: Float = CalibrationProvider.defaultOffset {
        didSet {
            let effective = calibrationOverride ?? calibrationOffset
            rtSettingsLock.withLock { $0.calibrationOffset = effective }
            CalibrationProvider.persist(offset: calibrationOffset)
        }
    }

    /// DL-10: Non-persisted calibration used by the DSP path while a stored
    /// recording is analysed (`PlaybackAnalyzer`). Never written to
    /// `CalibrationProvider`, so a crash mid-playback cannot replace the
    /// user's calibration with the recording's.
    private(set) var calibrationOverride: Float?

    /// The calibration the DSP path is currently applying
    /// (`calibrationOverride` when set, otherwise the user's offset).
    var effectiveCalibrationOffset: Float { calibrationOverride ?? calibrationOffset }

    /// Sets or clears the non-persisted DSP calibration override (DL-10).
    func setCalibrationOverride(_ value: Float?) {
        calibrationOverride = value
        let effective = value ?? calibrationOffset
        rtSettingsLock.withLock { $0.calibrationOffset = effective }
    }
    private var currentInputGain: Float = 1.0

    // MARK: - Recording

    private var recordingStartTime: Date? {
        didSet {
            rtSettingsLock.withLock { $0.recordingStartTime = recordingStartTime }
        }
    }

    // --- AE-2: Writer cross-thread safety ---
    //
    // Both writers are created and nulled on the main thread but read on the audio
    // render thread (processAudioBuffer / processFFTFrame). Wrapping them in
    // OSAllocatedUnfairLock prevents the use-after-free that would occur if the
    // main thread nils the writer while the audio thread holds a reference.
    //
    // Audio thread: read via `withLockUnchecked { $0 }` (real-time safe, no
    //   priority-inversion overhead).
    // Main thread: read/write via `withLock { ... }` or `withLockUnchecked { ... }`.
    //
    // The lock duration covers only the reference load/store, not the write call
    // itself — the strong reference keeps the object alive past the unlock.
    /// Owns the real-time audio + measurement file writers, their cross-thread
    /// locks, the last-file URLs, and the metric-key schema (extracted in
    /// Phase 3, post-3.5 shrink). Recording-mode gating stays here.
    private let recordingWriter = RecordingWriterCoordinator()

    /// Forwarders so existing call sites (ControlBarView, RecordingManager, and
    /// the `… = nil` reset sites below) keep working unchanged.
    var lastRecordingURL: URL? {
        get { recordingWriter.lastRecordingURL }
        set { recordingWriter.lastRecordingURL = newValue }
    }
    var lastMeasurementDataURL: URL? {
        get { recordingWriter.lastMeasurementDataURL }
        set { recordingWriter.lastMeasurementDataURL = newValue }
    }
    
    // MARK: - Published Properties

    // MARK: - Recording coordinator
    //
    // Flags + duration storage moved into RecordingCoordinator as part
    // of M13 task-5. The properties below are computed forwarders so
    // existing read/write call sites (ControlBarView, DashboardViewModel,
    // WaterfallView, the audio frame writers below) keep working
    // unchanged.
    //
    // The `recording.isMeasurementRecording` didSet side effects
    // (setupMeasurementDataFileIfNeeded / closeMeasurementWriter) moved
    // out of the property and into a Combine subscription bridged in
    // init — same pattern as task-4's live-state extraction.
    let recording = RecordingCoordinator()
    private var recordingBridge: AnyCancellable?
    private var measurementRecordingSink: AnyCancellable?

    // --- AE-3: Audio-thread-safe mirrors of RecordingCoordinator flags ---
    //
    // `RecordingCoordinator.isRecordingToFile` and `.isMeasurementRecording` are
    // @Published properties. @Published has no thread-safety guarantee — writing on
    // main while reading on the audio render thread is a data race per the Swift
    // memory model. These locks mirror the flags atomically so the audio thread
    // can read them without touching @Published storage.
    //
    // The mirrors are always updated alongside the RecordingCoordinator property
    // (see the computed setters below). All audio-thread reads go through these locks.
    private let audioThreadIsRecordingToFile = OSAllocatedUnfairLock<Bool>(initialState: false)
    private let audioThreadIsMeasurementRecording = OSAllocatedUnfairLock<Bool>(initialState: false)

    // RecordingCoordinator forwarders deleted 2026-05-27 as M13 task-5
    // continued: all call sites use `audioEngine.recording.X` directly.
    // The audio-thread-safe `audioThreadIs*` mirrors are kept in sync via
    // Combine sinks on `recording.$isRecordingToFile` /
    // `$isMeasurementRecording` (installed in init), replacing the old
    // setter side effects.
    private var recordingFileMirrorSink: AnyCancellable?
    private var measurementMirrorSink: AnyCancellable?
    @Published var engineStatus: EngineStatus = .idle
    @Published private(set) var activeMicrophoneSource: MicrophoneSource?
    @Published var lastError: SpektoWatchError?
    // MARK: - Live acoustic state
    //
    // The 17 live-metric `@Published` properties (`currentSpectrogramData`,
    // `currentLevel`, …, `currentBarkBandsC`) live on `LiveAcousticState`.
    // All read and write sites — internal and external — use `live.X`
    // directly. The compatibility forwarders that previously bridged
    // `audioEngine.X` to `live.X` were deleted 2026-05-27 as M13 task-4
    // closed out.
    let live = LiveAcousticState()
    // Called on the main thread after each band-update cycle.
    // MaskingEngine sets this to observe live spectrum data without a second audio tap.
    // bands = Z-weighted 1/3-octave bands (31 values, dB SPL); rmsDB = broadband level.
    var onBandsUpdated: (([Float], Float) -> Void)?

    @Published var timeWeighting: TimeWeighting = .fast {
        didSet {
            spectrogramProcessor.spectrogramTimeWeighting = timeWeighting
        }
    }
    @Published var frequencyWeighting: FrequencyWeighting = .a {
        didSet {
            rtSettingsLock.withLock { $0.frequencyWeighting = frequencyWeighting }
            connectivityManager.sendFrequencyWeightingSelection(frequencyWeighting.rawValue)
        }
    }
    @Published var spectrogramResolution: SpectrogramResolution = .current {
        didSet {
            guard spectrogramResolution != oldValue else { return }
            SpectrogramResolution.save(spectrogramResolution)
            applySpectrogramResolutionToProcessors()
        }
    }

    @Published var spectrogramFrequencySmoothing: Float = 0.0 {
        didSet {
            let clamped = max(0.0, min(1.0, spectrogramFrequencySmoothing))
            if abs(clamped - spectrogramFrequencySmoothing) > 0.0001 {
                spectrogramFrequencySmoothing = clamped
                return
            }
            UserDefaults.standard.set(Double(clamped), forKey: PersistenceKeys.spectrogramFrequencySmoothing)
        }
    }
    @Published var spectrogramTemporalSmoothing: Float = 0.6 {
        didSet {
            let clamped = max(0.0, min(1.0, spectrogramTemporalSmoothing))
            if abs(clamped - spectrogramTemporalSmoothing) > 0.0001 {
                spectrogramTemporalSmoothing = clamped
                return
            }
            spectrogramProcessor.temporalSmoothingIntensity = clamped
            UserDefaults.standard.set(Double(clamped), forKey: PersistenceKeys.spectrogramTemporalSmoothing)
        }
    }
    @Published var spectrogramFrequencyScale: SpectrogramFrequencyScale = .current {
        didSet {
            guard spectrogramFrequencyScale != oldValue else { return }
            SpectrogramFrequencyScale.save(spectrogramFrequencyScale)
        }
    }
    /// Lower bound of the displayed spectrogram frequency range (Hz).
    @Published var spectrogramMinFrequency: Double = 20 {
        didSet {
            let clamped = min(
                max(spectrogramMinFrequency, SpectrogramFrequencyRange.absoluteMin),
                spectrogramMaxFrequency / 1.2
            )
            if abs(clamped - spectrogramMinFrequency) > 0.001 {
                spectrogramMinFrequency = clamped
                return
            }
            UserDefaults.standard.set(spectrogramMinFrequency, forKey: PersistenceKeys.spectrogramMinFrequency)
            NotificationCenter.default.post(name: .spectrogramFrequencyRangeChanged, object: nil)
        }
    }
    /// Upper bound of the displayed spectrogram frequency range (Hz), clamped to
    /// the active microphone's Nyquist frequency.
    @Published var spectrogramMaxFrequency: Double = 20_000 {
        didSet {
            let nyquist = sampleRate / 2.0
            let upperLimit = min(SpectrogramFrequencyRange.absoluteMax, max(2_000, nyquist))
            let clamped = max(min(spectrogramMaxFrequency, upperLimit), spectrogramMinFrequency * 1.2)
            if abs(clamped - spectrogramMaxFrequency) > 0.001 {
                spectrogramMaxFrequency = clamped
                return
            }
            UserDefaults.standard.set(spectrogramMaxFrequency, forKey: PersistenceKeys.spectrogramMaxFrequency)
            NotificationCenter.default.post(name: .spectrogramFrequencyRangeChanged, object: nil)
        }
    }
    @Published var scrollSpeed: ScrollSpeed = .normal {
        didSet {
            rtSettingsLock.withLock { $0.scrollSpeed = scrollSpeed }
        }
    }
    
    @Published var availableDataSources: [AVAudioSessionDataSourceDescription] = []
    @Published var selectedDataSource: AVAudioSessionDataSourceDescription? {
        didSet {
            if let dataSource = selectedDataSource, engineStatus == .running {
                try? AVAudioSession.sharedInstance().setInputDataSource(dataSource)
            }
        }
    }
    @Published var selectedStereoMode: StereoInputMode = .frontBottom {
        didSet {
            applyStereoMode()
        }
    }
    
    // MARK: - Temporal Smoothing
    
    // MARK: - Initialization
    
    init(filterManager: BandstopFilterManager, connectivityManager: WatchConnectivityManager) {
        self.bandstopFilterManager = filterManager
        self.connectivityManager = connectivityManager

        // Initialize processing components
        fftProcessor = FFTProcessor(fftSize: fftSize, sampleRate: processingSampleRate)
        weightingProcessor = FrequencyWeightingProcessor(fftSize: fftSize, sampleRate: processingSampleRate)
        metricsCalculator = AcousticMetricsCalculator(sampleRate: sampleRate)
        wearableIngest = WearableIngestCoordinator(sampleRate: sampleRate)
        spectrogramProcessor = SpectrogramProcessor(bandstopFilterManager: filterManager)
        spectrogramProcessor.binningFactor = 1
        spectrogramProcessor.spectrogramTimeWeighting = .fast
        spectrogramProcessor.hopDuration = Float(tapBlockSize) / Float(sampleRate)
        testGenerator = TestAudioGenerator(sampleRate: sampleRate)
        spectrogramProcessor.temporalSmoothingIntensity = spectrogramTemporalSmoothing
        
        // Setup test generator callback
        testGenerator.onDataGenerated = { [weak self] samples in
            self?.processSamples(samples)
        }

        // liveBridge removed 2026-05-27 (M13 task-4 Phase-2 complete):
        // every widget now observes `audioEngine.live` directly (or doesn't
        // need to observe live state at all), so engine-level
        // objectWillChange no longer needs to fan out live-tick updates.
        // All 17 live-metric computed forwarders (currentSpectrogramData …
        // currentBarkBandsC) deleted 2026-05-27. Remaining @Published
        // properties (engineStatus, timeWeighting, frequencyWeighting,
        // scrollSpeed) are engine-settings storage, not forwarders.

        // Bridge for RecordingCoordinator (M13 task-5). Kept so existing
        // `@ObservedObject var audioEngine` consumers re-render when
        // recording state changes — they read `audioEngine.recording.X`
        // through the parent engine's observation.
        recordingBridge = recording.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        // Keep the audio-thread-safe mirror locks in sync with the
        // RecordingCoordinator's published state. Previously the
        // forwarder setters wrote both the @Published value and the lock
        // mirror in one assignment; with the forwarders gone, sinks on
        // the projected publishers do the same job.
        recordingFileMirrorSink = recording.$isRecordingToFile
            .sink { [weak self] newValue in
                self?.audioThreadIsRecordingToFile.withLock { $0 = newValue }
            }
        measurementMirrorSink = recording.$isMeasurementRecording
            .sink { [weak self] newValue in
                self?.audioThreadIsMeasurementRecording.withLock { $0 = newValue }
            }

        // Run the file-setup / writer-close side effects when
        // recording.isMeasurementRecording flips. Previously a didSet on the
        // @Published property — moved here so the storage can live on
        // RecordingCoordinator.
        // dropFirst() to skip the initial false value emission.
        measurementRecordingSink = recording.$isMeasurementRecording
            .dropFirst()
            .sink { [weak self] newValue in
                guard let self else { return }
                guard self.recording.isRecordingToFile else { return }
                if newValue {
                    self.setupMeasurementDataFileIfNeeded()
                } else {
                    self.lastMeasurementDataURL = nil
                    self.closeMeasurementWriter()
                }
            }

        // Load saved calibration offset or use device-specific default.
        // Logic + device map lives in CalibrationProvider (M13 task-3).
        calibrationOffset = CalibrationProvider.resolveStartupOffset()

        if let savedFrequencySmoothing = UserDefaults.standard.object(forKey: PersistenceKeys.spectrogramFrequencySmoothing) as? Double {
            spectrogramFrequencySmoothing = Float(savedFrequencySmoothing)
        }
        if let savedTemporalSmoothing = UserDefaults.standard.object(forKey: PersistenceKeys.spectrogramTemporalSmoothing) as? Double {
            spectrogramTemporalSmoothing = Float(savedTemporalSmoothing)
        }

        // Frequency-axis display range (Hz). Default upper bound tracks the
        // microphone's Nyquist; user overrides persist across launches.
        let savedRange = SpectrogramFrequencyRange.current(sampleRate: sampleRate)
        spectrogramMaxFrequency = savedRange.maxHz
        spectrogramMinFrequency = savedRange.minHz

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSpectrogramResolutionChanged(_:)),
            name: .spectrogramResolutionChanged,
            object: nil
        )

        sessionEventsCancellable = AudioSessionCoordinator.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleSessionEvent(event)
            }
    }

    // MARK: - Interruptions / route changes (AS-1)

    private var isRealIPhoneCaptureActive: Bool {
        activeMicrophoneSource == .iPhone
            && engineStatus == .running
            && !isUsingDummyData
            && !shouldUseTestAudioCapture
    }

    private func handleSessionEvent(_ event: AudioSessionCoordinator.SessionEvent) {
        dispatchPrecondition(condition: .onQueue(.main))
        switch event {
        case .interruptionBegan:
            guard isRealIPhoneCaptureActive else { return }
            isCaptureInterrupted = true
            Logger.audioEngine.warning("Capture interrupted (recording=\(self.recording.isRecordingToFile))")
        case .interruptionEnded:
            // A measurement app resumes after a call/Siri even without
            // `.shouldResume`; the restart fails cleanly if the mic is busy.
            if isCaptureInterrupted {
                restartCaptureAfterDisruption(reason: "interruption ended")
            }
        case .mediaServicesReset:
            guard isRealIPhoneCaptureActive || isCaptureInterrupted else { return }
            captureSession.resetEngine()
            restartCaptureAfterDisruption(reason: "media services reset", reconfigureSession: true)
        case .routeChanged:
            // The engine posts AVAudioEngineConfigurationChange when the
            // route change affects I/O; that path restarts capture.
            break
        }
    }

    /// AS-1: reinstalls the tap and restarts the capture graph. The
    /// measurement file keeps its open writer — the timestamp jump of the
    /// next frame marks the gap. If the hardware format changed mid-recording
    /// the audio writer is closed (the file so far is kept) because the
    /// `.caf` cannot change format. If restart fails during a recording the
    /// files are finalized and the error is surfaced.
    func restartCaptureAfterDisruption(reason: String, reconfigureSession: Bool = false) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.restartCaptureAfterDisruption(reason: reason, reconfigureSession: reconfigureSession) }
            return
        }
        guard activeMicrophoneSource == .iPhone,
              engineStatus == .running || isCaptureInterrupted,
              !isUsingDummyData, !shouldUseTestAudioCapture else { return }
        do {
            if reconfigureSession {
                _ = try captureSession.configureCaptureSession(
                    stereoMode: selectedStereoMode,
                    selectedDataSource: selectedDataSource
                )
            }
            let format = try captureSession.restart()
            updateProcessingSampleRateIfNeeded(format.sampleRate, source: "Mic restart")
            if recording.isRecordingToFile, let fileFormat = recordingWriter.audioFormat,
               fileFormat.sampleRate != format.sampleRate || fileFormat.channelCount != format.channelCount {
                Logger.audioEngine.error("Input format changed during recording — audio file closed, measurement continues")
                closeAudioFileWriter()
            }
            isCaptureInterrupted = false
            engineStatus = .running
            Logger.audioEngine.info("Capture restarted after \(reason)")
        } catch {
            isCaptureInterrupted = false
            Logger.audioEngine.error("Capture restart after \(reason) failed: \(error.localizedDescription)")
            if recording.isRecordingToFile {
                // Finalize what we have; URLs stay set so stopping the
                // recording still saves it.
                closeAudioFileWriter()
                closeMeasurementWriter()
            }
            lastError = .audioEngineFailure(reason: error.localizedDescription)
            engineStatus = .error("Audioaufnahme konnte nach einer Unterbrechung nicht fortgesetzt werden.")
        }
    }

    // MARK: - Suspend / resume (AS-5 / AS-7)

    /// What `suspendCapture()` stopped, so `resumeCapture(_:)` restores
    /// exactly that (nothing, iPhone mic, or Apple Watch source).
    struct CaptureToken: Equatable {
        let wasActive: Bool
        let source: MicrophoneSource?
    }

    /// Stops whatever live source is running (synchronously updating
    /// `engineStatus`) and returns a token describing it. Never call during a
    /// file recording (`PlaybackAnalyzer` refuses, DL-1).
    func suspendCapture() -> CaptureToken {
        dispatchPrecondition(condition: .onQueue(.main))
        let wasActive = engineStatus == .running || engineStatus == .starting || isStartingCapture
        let token = CaptureToken(wasActive: wasActive, source: activeMicrophoneSource)
        guard wasActive else { return token }
        if activeMicrophoneSource == .appleWatch {
            stopWearableLiveMode()
        } else {
            stopLiveMode()
        }
        return token
    }

    /// Restores the state captured by `suspendCapture()`. A token for an
    /// idle engine leaves it idle (AS-5: no forced iPhone mic).
    func resumeCapture(_ token: CaptureToken) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard token.wasActive else { return }
        if token.source == .appleWatch {
            startWearableLiveMode()
        } else {
            startLiveMode()
        }
    }

    /// Runs `body` now when on main, otherwise asynchronously on main (AS-7).
    private func onMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread {
            body()
        } else {
            DispatchQueue.main.async(execute: body)
        }
    }

    @objc private func handleSpectrogramResolutionChanged(_ notification: Notification) {
        guard let resolution = notification.object as? SpectrogramResolution else { return }
        if spectrogramResolution != resolution {
            spectrogramResolution = resolution
        } else {
            applySpectrogramResolutionToProcessors()
        }
    }

    private func applySpectrogramResolutionToProcessors() {
        connectivityManager.sendSpectrogramResolution(spectrogramResolution)
    }
    
    // MARK: - Public Configuration Methods

    /// Resets the spectrogram frequency-display range to the active microphone's
    /// default (20 Hz – min(20 kHz, Nyquist)). Max is raised before min so the
    /// per-property clamps don't fight each other.
    func resetSpectrogramFrequencyRangeToMicrophoneDefault() {
        let def = SpectrogramFrequencyRange.microphoneDefault(sampleRate: sampleRate)
        spectrogramMaxFrequency = def.maxHz
        spectrogramMinFrequency = def.minHz
    }

    func setTimeWeighting(_ weighting: TimeWeighting) {
        timeWeighting = weighting
    }
    
    func setFrequencyWeighting(_ weighting: FrequencyWeighting) {
        frequencyWeighting = weighting
    }

    func setWidgetSpectralWeightingRequirements(_ weightings: Set<FrequencyWeighting>) {
        widgetSpectralWeightingsLock.withLock { state in
            state = weightings
        }
    }

    /// Tells the engine whether any widget currently needs pre-aggregated Bark bands.
    /// Called by `DashboardViewModel` whenever the widget list changes.
    /// When `false` (the default) the per-frame Bark aggregation is skipped entirely.
    func setWidgetBarkBandsRequired(_ required: Bool) {
        widgetBarkBandsRequiredLock.withLock { $0 = required }
    }
    
    func setGainBoost(_ gain: Float) {
        gainBoost = gain
    }

    // MARK: - FFT Configuration

    /// Wendet eine FFTConfiguration an
    @MainActor
    func applyFFTConfiguration(_ config: FFTConfiguration) {
        let newSize = config.blockSize.rawValue
        let newWindow = config.windowFunction

        // Prüfe ob Änderungen nötig sind
        guard newSize != fftSize || newWindow != currentWindowFunction else { return }

        Logger.audioEngine.info("Applying FFT config: \(newWindow.rawValue), \(newSize) samples")
        reconfigureFFT(blockSize: config.blockSize, windowFunction: newWindow)
        objectWillChange.send()
    }

    /// Setzt nur die Fensterfunktion
    func setWindowFunction(_ function: WindowFunction) {
        guard function != currentWindowFunction else { return }

        processingLock.withLockUnchecked {
            currentWindowFunction = function
            fftProcessor.setWindowFunction(function)
        }
        Logger.audioEngine.info("Window function changed to: \(function.rawValue)")
    }

    /// Setzt nur die Blockgröße
    func setBlockSize(_ size: FFTBlockSize) {
        guard size.rawValue != fftSize else { return }

        reconfigureFFT(blockSize: size, windowFunction: currentWindowFunction)
        Logger.audioEngine.info("FFT size changed to: \(size.rawValue)")
    }

    private func reconfigureFFT(blockSize: FFTBlockSize, windowFunction: WindowFunction) {
        let newSize = blockSize.rawValue
        // RT-1: build every replacement object off-lock (allocations happen
        // here on main), then swap references in one short critical section.
        let sampleRate = processingLock.withLockUnchecked { processingSampleRate }
        let newPipeline = ProcessingPipeline(energyCount: newSize / 2)
        let newFFT = FFTProcessor(fftSize: newSize, sampleRate: sampleRate, windowFunction: windowFunction)
        let newWeighting = FrequencyWeightingProcessor(fftSize: newSize, sampleRate: sampleRate)
        let retired: [AnyObject] = processingLock.withLockUnchecked {
            sampleRing.reset()
            let old: [AnyObject] = [processingPipeline, fftProcessor, weightingProcessor]
            processingPipeline = newPipeline
            fftProcessor = newFFT
            weightingProcessor = newWeighting
            fftSize = newSize
            return old
        }
        currentWindowFunction = windowFunction
        currentBlockSize = blockSize
        retireDSPObjects(retired)
    }

    /// Keeps replaced DSP objects alive briefly on main so an in-flight
    /// render-thread frame never releases the last reference (RT-1/RT-5).
    private func retireDSPObjects(_ objects: [AnyObject]) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.retireDSPObjects(objects) }
            return
        }
        retiredDSPObjects.append(contentsOf: objects)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.retiredDSPObjects.removeFirst(min(objects.count, self.retiredDSPObjects.count))
        }
    }

    /// Gibt die aktuelle Frequenzauflösung zurück
    var frequencyResolution: Float {
        return Float(processingSampleRate) / Float(fftSize)
    }

    /// Gibt die aktuelle Zeitauflösung in ms zurück
    var timeResolutionMs: Float {
        return Float(fftSize) / Float(processingSampleRate) * 1000.0
    }

    // MARK: - Live/Recording Control

    /// Warms the lazy `AVAudioEngine` after `AudioEngine` construction so the
    /// first `startLiveMode()` / `startRecording()` does less main-thread work.
    func prewarmCaptureGraph() {
        captureSession.prewarmGraph()
    }

    /// Startet die Live-Anzeige (ohne Aufnahme in Datei)
    func startLiveMode() {
        print("[AudioEngine] startLiveMode called")
        print("[AudioEngine] Current engineStatus: \(engineStatus)")
        guard engineStatus != .running, engineStatus != .starting else {
            print("[AudioEngine] Engine already running, returning early")
            return
        }
        Logger.audioEngine.info("Starting AudioEngine in LIVE mode (no file recording)")
        recording.isRecordingToFile = false
        activeMicrophoneSource = .iPhone
        print("[AudioEngine] Set recording.isRecordingToFile = false")
        startAudioCapture()
    }

    /// Startet die Aufnahme (mit Speicherung in Datei)
    func startRecording() {
        print("[AudioEngine] startRecording called")
        print("[AudioEngine] Current engineStatus: \(engineStatus)")
        print("[AudioEngine] Current recording.isRecordingToFile: \(recording.isRecordingToFile)")

        if engineStatus == .starting {
            print("[AudioEngine] Engine is starting, ignoring startRecording")
            return
        }

        // Always capture measurement data when starting a recording.
        if !recording.isMeasurementRecording {
            recording.isMeasurementRecording = true
        }

        guard engineStatus != .running else {
            // Wenn bereits im Live-Modus, nur auf Aufnahme umschalten
            if !recording.isRecordingToFile {
                Logger.audioEngine.info("Switching from LIVE to RECORDING mode")
                recording.isRecordingToFile = true
                activeMicrophoneSource = .iPhone
                print("[AudioEngine] Set recording.isRecordingToFile = true (switching from live)")
                recordingStartTime = Date()
                recording.recordingDuration = 0.0
                resetMetrics()
                setupRecordingFile()
                if recording.isMeasurementRecording {
                    setupMeasurementDataFileIfNeeded()
                } else {
                    lastMeasurementDataURL = nil
                    closeMeasurementWriter()
                }
            }
            return
        }
        Logger.audioEngine.info("Starting AudioEngine in RECORDING mode")
        recording.isRecordingToFile = true
        activeMicrophoneSource = .iPhone
        if !recording.isMeasurementRecording {
            lastMeasurementDataURL = nil
            closeMeasurementWriter()
        }
        print("[AudioEngine] Set recording.isRecordingToFile = true")
        startAudioCapture()
    }

    /// Starts a live measurement whose data source is the Apple Watch microphone.
    /// This keeps the phone dashboard in a running state without opening the
    /// iPhone audio input; processed watch spectrogram packets drive the UI.
    func startWearableLiveMode() {
        print("[AudioEngine] startWearableLiveMode called")
        guard engineStatus != .running, engineStatus != .starting else {
            print("[AudioEngine] Engine already running, returning early")
            return
        }

        Logger.audioEngine.info("Starting AudioEngine in WEARABLE live mode")
        recording.isRecordingToFile = false
        recording.isMeasurementRecording = false
        activeMicrophoneSource = .appleWatch
        recordingStartTime = Date()
        recording.recordingDuration = 0.0
        resetMetrics()

        onMain {
            self.engineStatus = .running
            self.isStartingCapture = false
        }
    }

    private func startAudioCapture() {
        let signpostID = PerformanceSignpost.begin("AudioEngineStart")
        defer {
            PerformanceSignpost.end("AudioEngineStart", signpostID: signpostID)
        }

        print("[AudioEngine] startAudioCapture called")
        print("[AudioEngine] Current engineStatus: \(engineStatus)")
        print("[AudioEngine] Current recording.isRecordingToFile: \(recording.isRecordingToFile)")
        if isStartingCapture || engineStatus == .starting {
            print("[AudioEngine] Capture already starting, returning early")
            return
        }
        isStartingCapture = true
        // AS-2: every start begins from real capture; a previous session's
        // fallback must not leak into this one.
        isUsingDummyData = false

        onMain {
            self.engineStatus = .starting
        }

        recordingStartTime = Date()
        recording.recordingDuration = 0.0
        signalMonitor.resetSilenceLog()

        resetMetrics()

        if shouldUseTestAudioCapture {
            startTestAudioCapture()
        } else {
            startRealRecording()
        }
    }

    /// Simulator and UI-test launches use the synthetic generator so capture
    /// does not depend on microphone permission or AVAudioEngine graph timing.
    private var shouldUseTestAudioCapture: Bool {
        #if DEBUG
        if UITestRuntime.useTestAudio { return true }
        #endif
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private func startTestAudioCapture() {
        Logger.audioEngine.info("Using test audio generator for capture")
        print("[AudioEngine] Starting test generator")
        if recording.isRecordingToFile {
            setupRecordingFile()
            setupMeasurementDataFileIfNeeded()
        }
        testGenerator.start()
        let finish: () -> Void = {
            print("[AudioEngine] Setting engineStatus to .running")
            self.engineStatus = .running
            self.isStartingCapture = false
            print("[AudioEngine] engineStatus is now: \(self.engineStatus)")
            print("[AudioEngine] recording.isRecordingToFile: \(self.recording.isRecordingToFile)")
        }
        if Thread.isMainThread {
            finish()
        } else {
            DispatchQueue.main.async(execute: finish)
        }
    }

    /// Stoppt die Live-Anzeige (ohne Aufnahme zu beenden)
    func stopLiveMode() {
        print("[AudioEngine] stopLiveMode called")
        print("[AudioEngine] Current engineStatus: \(engineStatus)")
        Logger.audioEngine.info("Stopping AudioEngine live mode")
        stopAudioCapture()
    }

    /// Stoppt die Aufnahme
    func stopRecording() {
        print("[AudioEngine] stopRecording called")
        print("[AudioEngine] Current engineStatus: \(engineStatus)")
        print("[AudioEngine] Current recording.isRecordingToFile: \(recording.isRecordingToFile)")
        Logger.audioEngine.info("Stopping AudioEngine recording")
        recording.isRecordingToFile = false
        print("[AudioEngine] Set recording.isRecordingToFile = false")
        stopAudioCapture()
    }

    /// Stops a wearable-source live measurement. This does not touch
    /// AVAudioEngine because the phone microphone was never opened.
    func stopWearableLiveMode() {
        print("[AudioEngine] stopWearableLiveMode called")
        guard activeMicrophoneSource == .appleWatch else { return }

        recordingStartTime = nil
        closeMeasurementWriter()

        onMain {
            self.engineStatus = .idle
            self.recording.isRecordingToFile = false
            self.isStartingCapture = false
            self.activeMicrophoneSource = nil
        }
    }

    private func stopAudioCapture() {
        print("[AudioEngine] stopAudioCapture called")
        print("[AudioEngine] Current engineStatus: \(engineStatus)")

        recordingStartTime = nil
        captureGeneration &+= 1
        closeAudioFileWriter()
        closeMeasurementWriter()
        // AS-7: synchronous when already on main, so an immediate
        // `startLiveMode()` no longer early-returns on a stale `.running`.
        onMain {
            self.engineStatus = .idle
            self.recording.isRecordingToFile = false
            self.activeMicrophoneSource = nil
            self.isStartingCapture = false
            self.isCaptureInterrupted = false
        }

        // AS-2: always stop both sources — a previous fallback or a test
        // generator must never keep running next to (or instead of) the mic.
        testGenerator.stop()
        if !shouldUseTestAudioCapture {
            captureSession.stop()
        }
        isUsingDummyData = false

        DispatchQueue.main.async {
            self.live.levelHistory.removeAll()
            self.live.levelHistory.reserveCapacity(self.maxHistorySize + 64)
            self.live.currentLevel = -120.0
        }

        // Reset buffer state
        processingLock.withLockUnchecked {
            sampleRing.reset()
        }
    }

    private func setupRecordingFile() {
        guard recording.isRecordingToFile else { return }
        recordingWriter.setupRecordingFile(
            format: captureSession.inputFormat(),
            frameCapacity: max(tapBlockSize, 4096)
        )
    }

    private func setupMeasurementDataFileIfNeeded() {
        guard recording.isRecordingToFile, recording.isMeasurementRecording else {
            closeMeasurementWriter()
            return
        }

        let fps = Float(processingSampleRate / Double(max(1, scrollSpeed.rawValue)))
        recordingWriter.setupMeasurementFileIfNeeded(
            sampleRate: processingSampleRate,
            fps: fps,
            fftBlockSize: fftSize,
            fftBinCount: max(1, fftSize / 2)
        )
    }

    private func closeMeasurementWriter() {
        recordingWriter.closeMeasurement()
    }

    private func closeAudioFileWriter() {
        recordingWriter.closeAudio()
    }

    func checkAvailableInputs() {
        let session = AVAudioSession.sharedInstance()
        if let inputs = session.availableInputs,
           let builtInMic = inputs.first(where: { $0.portType == .builtInMic }) {
            DispatchQueue.main.async {
                self.availableDataSources = builtInMic.dataSources ?? []
                if self.selectedDataSource == nil {
                    self.selectedDataSource = session.inputDataSource ?? self.availableDataSources.first
                }
            }
        }
    }
    
    func applyStereoMode() {
        guard !availableDataSources.isEmpty else { return }
        
        var targetOrientation: AVAudioSession.Orientation?
        
        switch selectedStereoMode {
        case .frontBottom:
            targetOrientation = .front
        case .bottomBack:
            targetOrientation = .back
        case .frontBack:
            targetOrientation = .bottom
        }
        
        if let targetOrientation = targetOrientation,
           let source = availableDataSources.first(where: { $0.orientation == targetOrientation }) {
            
            if let supported = source.supportedPolarPatterns, supported.contains(.stereo) {
                try? source.setPreferredPolarPattern(.stereo)
            }
            
            DispatchQueue.main.async {
                if self.selectedDataSource?.dataSourceID != source.dataSourceID {
                    self.selectedDataSource = source
                }
            }
        }
    }
    
    func processExternalAudio(_ samples: [Float], sampleRate externalSampleRate: Double? = nil) {
        if let externalSampleRate = externalSampleRate {
            lastObservedInputSampleRate = externalSampleRate
            updateProcessingSampleRateIfNeeded(externalSampleRate, source: "External")
            if abs(externalSampleRate - processingSampleRate) > 1.0 {
                Logger.audioEngine.warning(
                    "External sample-rate mismatch: input \(externalSampleRate, format: .fixed(precision: 1)) Hz vs processing \(self.processingSampleRate, format: .fixed(precision: 1)) Hz"
                )
            }
        }
        let now = CFAbsoluteTimeGetCurrent()
        rtPerfLock.withLockUnchecked { $0.lastAudioBufferTimestamp = now }
        processSamples(samples)
    }
    
    func getRecordingStatistics() -> (laeqFast: Float, peak: Float, min: Float) {
        return metricsCalculator.getStatistics()
    }

    /// Aktualisiert die Kalibrierungswerte basierend auf AVAudioSession
    /// Hinweis: Überschreibt NICHT den benutzerdefinierten calibrationOffset,
    /// sondern wendet nur Gain-Korrekturen an
    func updateCalibration() {
        let session = AVAudioSession.sharedInstance()

        // Lese aktuellen Input-Gain (falls verfügbar)
        let newInputGain = session.inputGain

        // Nur loggen wenn sich etwas geändert hat
        if newInputGain != currentInputGain {
            currentInputGain = newInputGain
            Logger.audioEngine.info("Input gain updated: \(self.currentInputGain, format: .fixed(precision: 2)), calibrationOffset: \(self.calibrationOffset, format: .fixed(precision: 1)) dB")
        }
    }

    /// Pre-warm audio session to reduce start latency
    func prewarmAudioSession() {
        captureSession.prewarmSession()
    }

    /// Setzt die Kalibrierung auf den empfohlenen Wert für dieses Gerät zurück
    func resetCalibrationToDeviceDefault() {
        let recommended = CalibrationProvider.recommendedOffset()
        calibrationOffset = recommended
        Logger.audioEngine.info("Calibration reset to device default: \(recommended) dB")
    }

    /// Gibt den aktuellen Kalibrierungs-Offset zurück
    func getCalibrationOffset() -> Float {
        return calibrationOffset
    }

    static func getDeviceModel() -> String {
        CalibrationProvider.currentDeviceModel()
    }

    // MARK: - Private Recording Methods

    private func startRealRecording() {
        let audioSession = AVAudioSession.sharedInstance()

        // Check permissions first (quick check on main thread)
        // Use new iOS 17+ API with fallback for older versions
        #if swift(>=5.9)
        if #available(iOS 17.0, *) {
            let permission = AVAudioApplication.shared.recordPermission
            if permission == .undetermined {
                AVAudioApplication.requestRecordPermission { [weak self] granted in
                    guard let self = self else { return }
                    if granted {
                        DispatchQueue.main.async {
                            // Continue the pending capture startup instead of re-entering
                            // startRecording(), which is ignored while engineStatus == .starting.
                            self.startRealRecording()
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.isStartingCapture = false
                            self.recording.isRecordingToFile = false
                            self.engineStatus = .error("Microphone permission denied")
                        }
                    }
                }
                return
            }
            if permission == .denied {
                Logger.audioEngine.error("Microphone permission denied")
                DispatchQueue.main.async {
                    self.isStartingCapture = false
                    self.recording.isRecordingToFile = false
                    self.engineStatus = .error("Microphone permission denied")
                }
                return
            }
        } else {
            if audioSession.recordPermission == .undetermined {
                audioSession.requestRecordPermission { [weak self] granted in
                    guard let self = self else { return }
                    if granted {
                        DispatchQueue.main.async {
                            self.startRealRecording()
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.isStartingCapture = false
                            self.recording.isRecordingToFile = false
                            self.engineStatus = .error("Microphone permission denied")
                        }
                    }
                }
                return
            }
            if audioSession.recordPermission == .denied {
                Logger.audioEngine.error("Microphone permission denied")
                DispatchQueue.main.async {
                    self.isStartingCapture = false
                    self.recording.isRecordingToFile = false
                    self.engineStatus = .error("Microphone permission denied")
                }
                return
            }
        }
        #else
        if audioSession.recordPermission == .undetermined {
            audioSession.requestRecordPermission { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    DispatchQueue.main.async {
                        self.startRealRecording()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isStartingCapture = false
                        self.recording.isRecordingToFile = false
                        self.engineStatus = .error("Microphone permission denied")
                    }
                }
            }
            return
        }
        if audioSession.recordPermission == .denied {
            Logger.audioEngine.error("Microphone permission denied")
            DispatchQueue.main.async {
                self.isStartingCapture = false
                self.recording.isRecordingToFile = false
                self.engineStatus = .error("Microphone permission denied")
            }
            return
        }
        #endif

        // Capture state needed for background work
        let generation = captureGeneration
        let isRecording = self.recording.isRecordingToFile
        let selectedSource = self.selectedDataSource
        let stereoMode = self.selectedStereoMode

        // Move blocking audio session setup to background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                // Configure audio session + stereo polar pattern (blocking).
                let dataSources = try self.captureSession.configureCaptureSession(
                    stereoMode: stereoMode,
                    selectedDataSource: selectedSource
                )

                // Now setup audio engine on main thread (required for AVAudioEngine)
                DispatchQueue.main.async {
                    guard generation == self.captureGeneration else {
                        // Stopped while configuring (AS-7): drop the lease.
                        self.captureSession.stop()
                        return
                    }
                    self.finishAudioEngineSetup(isRecording: isRecording, dataSources: dataSources, audioSession: audioSession)
                }

            } catch {
                DispatchQueue.main.async {
                    guard generation == self.captureGeneration else { return }
                    Logger.audioEngine.error("Audio engine failed to start: \(error.localizedDescription)")
                    self.handleCaptureStartFailure(error.localizedDescription)
                }
            }
        }
    }

    private func finishAudioEngineSetup(isRecording: Bool, dataSources: [AVAudioSessionDataSourceDescription], audioSession: AVAudioSession) {
        let signpostID = PerformanceSignpost.begin("AudioEngineSetup")
        defer { PerformanceSignpost.end("AudioEngineSetup", signpostID: signpostID) }

        // Update calibration based on current audio session settings
        updateCalibration()

        // Update available data sources
        self.availableDataSources = dataSources
        if self.selectedDataSource == nil {
            self.selectedDataSource = audioSession.inputDataSource ?? dataSources.first
        }

        do {
            // Setup audio engine
            let recordingFormat = captureSession.inputFormat()

            guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
                Logger.audioEngine.warning("Invalid audio format detected")
                handleCaptureStartFailure("Ungültiges Audioformat des Mikrofons")
                return
            }

            // Falls das Gerät nicht mit 44.1 kHz liefert, FFT-Achse entsprechend anpassen.
            self.updateProcessingSampleRateIfNeeded(recordingFormat.sampleRate, source: "Mic")

            // Setup recording file only if recording to file
            if isRecording {
                recordingWriter.setupRecordingFile(
                    format: recordingFormat,
                    frameCapacity: max(tapBlockSize, 4096)
                )
                setupMeasurementDataFileIfNeeded()
            } else {
                closeAudioFileWriter()
                closeMeasurementWriter()
                Logger.audioEngine.info("Live mode - no file recording")
            }

            // Install audio tap + start the capture graph.
            try captureSession.installTapAndStart(format: recordingFormat)
            engineStatus = .running
            isStartingCapture = false

        } catch {
            Logger.audioEngine.error("Audio engine setup failed: \(error.localizedDescription)")
            handleCaptureStartFailure(error.localizedDescription)
        }
    }

    /// AS-2: a failed mic start ends in `.error` (never overwritten by
    /// `.running`); only debug builds with the explicit flag fall back to the
    /// synthetic generator.
    private func handleCaptureStartFailure(_ message: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        isStartingCapture = false
        captureSession.stop()
        if Self.allowsSyntheticFallback {
            Logger.audioEngine.info("Falling back to test audio generator (debug flag)")
            isUsingDummyData = true
            testGenerator.start()
            engineStatus = .running
            return
        }
        closeAudioFileWriter()
        closeMeasurementWriter()
        recording.isRecordingToFile = false
        activeMicrophoneSource = nil
        lastError = .audioEngineFailure(reason: message)
        engineStatus = .error(message)
    }
    
    private func resetMetrics() {
        metricsCalculator.reset()
        wearableIngest.reset()

        DispatchQueue.main.async {
            self.live.levelHistory.removeAll()
            self.live.levelHistory.reserveCapacity(self.maxHistorySize + 64)
            self.live.currentLevel = -120.0
            self.live.maxLevel = -120.0
            self.live.minLevel = -120.0
        }
    }

    private func emitSpectrogramData(_ data: SpectrogramData) {
        // Send directly from whatever thread we're on. The audio render callback
        // is serial so there are no concurrent sends. Subscribers that need a
        // different thread use .receive(on:) — the previous main-thread bounce
        // added 86 DispatchQueue.main.async blocks/sec for no benefit.
        spectrogramSubject.send(data)
    }

    /// Applies processed Apple Watch spectrogram data to the phone dashboard.
    /// The watch sends compact derived data only; no raw audio is accepted here.
    func ingestWearableSpectrogramData(_ data: SpectrogramData) {
        guard activeMicrophoneSource == .appleWatch else { return }

        emitSpectrogramData(data)

        let octaveBandsZ = data.thirdOctaveBandsZ
            ?? computeDisplayThirdOctaveBands(frequencies: data.frequencies, magnitudes: data.magnitudes)
        let octaveBandsA = data.thirdOctaveBandsA
            ?? data.magnitudesA.map {
                computeDisplayThirdOctaveBands(frequencies: data.frequencies, magnitudes: $0)
            }
            ?? octaveBandsZ
        let octaveBandsC = data.thirdOctaveBandsC
            ?? data.magnitudesC.map {
                computeDisplayThirdOctaveBands(frequencies: data.frequencies, magnitudes: $0)
            }
            ?? octaveBandsZ

        let bandLeq: (z: [Float], a: [Float], c: [Float])
        if let z = data.bandLeqZ, z.count == SpectrumBandAggregator.thirdOctaveCenters.count {
            bandLeq = (z, data.bandLeqA ?? [], data.bandLeqC ?? [])
        } else {
            let integrated = wearableIngest.integrateBandLeq(
                from: data,
                thirdsZ: octaveBandsZ,
                thirdsA: octaveBandsA,
                thirdsC: octaveBandsC,
                recordingDuration: recording.recordingDuration,
                loudnessReferenceKey: Self.loudnessLevelKey(for: frequencyWeighting)
            )
            bandLeq = (integrated.bandLeqZ, integrated.bandLeqA, integrated.bandLeqC)
        }

        let barkBandsZ = data.barkBandsZ
            ?? SpectrumBandAggregator.barkBands(frequencies: data.frequencies, spectrum: data.magnitudes)
        let needsBark = widgetBarkBandsRequiredLock.withLockUnchecked { $0 }
        let barkBandsA: [Float]
        let barkBandsC: [Float]
        if needsBark {
            barkBandsA = data.magnitudesA.map {
                SpectrumBandAggregator.barkBands(frequencies: data.frequencies, spectrum: $0)
            } ?? []
            barkBandsC = data.magnitudesC.map {
                SpectrumBandAggregator.barkBands(frequencies: data.frequencies, spectrum: $0)
            } ?? []
        } else {
            barkBandsA = []
            barkBandsC = []
        }

        DispatchQueue.main.async {
            if let startTime = self.recordingStartTime {
                self.recording.recordingDuration = Date().timeIntervalSince(startTime)
            }

            self.live.currentSpectrogramData = data
            self.live.currentOctaveBandsZ = octaveBandsZ
            self.live.currentOctaveBandsA = octaveBandsA
            self.live.currentOctaveBandsC = octaveBandsC
            if !bandLeq.z.isEmpty {
                self.live.bandLeqZ = bandLeq.z
                self.live.bandLeqOctaveZ = Self.octaveLeqBands(fromThirds: bandLeq.z)
            }
            if !bandLeq.a.isEmpty {
                self.live.bandLeqA = bandLeq.a
                self.live.bandLeqOctaveA = Self.octaveLeqBands(fromThirds: bandLeq.a)
            }
            if !bandLeq.c.isEmpty {
                self.live.bandLeqC = bandLeq.c
                self.live.bandLeqOctaveC = Self.octaveLeqBands(fromThirds: bandLeq.c)
            }
            if !barkBandsZ.isEmpty { self.live.currentBarkBandsZ = barkBandsZ }
            if !barkBandsA.isEmpty { self.live.currentBarkBandsA = barkBandsA }
            if !barkBandsC.isEmpty { self.live.currentBarkBandsC = barkBandsC }
            self.live.currentLevel = data.broadbandLevel
            self.live.currentPeakLevel = data.levels["LCpeak"] ?? max(self.live.currentPeakLevel, data.broadbandLevel)
            self.live.maxLevel = max(self.live.maxLevel, data.broadbandLevel)
            if data.broadbandLevel > -110 {
                self.live.minLevel = min(self.live.minLevel, data.broadbandLevel)
            }
            self.live.levelHistory.append(data.broadbandLevel)
            let overshootBudget = 64
            if self.live.levelHistory.count > self.maxHistorySize + overshootBudget {
                self.live.levelHistory.removeFirst(self.live.levelHistory.count - self.maxHistorySize)
            }
            self.onBandsUpdated?(octaveBandsZ, data.broadbandLevel)
        }
    }

    // MARK: - Audio Processing
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let signpostID = OSSignpostID(log: Self.performanceLog)
        os_signpost(.begin, log: Self.performanceLog, name: "AudioTapCallback", signpostID: signpostID)
        defer { os_signpost(.end, log: Self.performanceLog, name: "AudioTapCallback", signpostID: signpostID) }

        let observedSampleRate = buffer.format.sampleRate
        if observedSampleRate > 0 {
            lastObservedInputSampleRate = observedSampleRate
            updateProcessingSampleRateIfNeeded(observedSampleRate, source: "Mic")
        }

        let now = CFAbsoluteTimeGetCurrent()
        rtPerfLock.withLockUnchecked { $0.lastAudioBufferTimestamp = now }
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        
        // Write to file only if recording to file mode is active.
        // Load the writer reference under the lock; the strong ref keeps it alive
        // past the unlock even if the main thread nils it concurrently.
        if audioThreadIsRecordingToFile.withLockUnchecked({ $0 }),
           let writer = recordingWriter.rtLoadAudioWriter() {
            writer.write(buffer)
        }
        
        // Extract samples and calculate stereo phase.
        // Reuse `monoSampleScratch` instead of `Array(UnsafeBufferPointer(...))` —
        // the previous form allocated a fresh `[Float]` on every callback.
        let channels = Int(buffer.format.channelCount)
        if monoSampleScratch.count != frameCount {
            monoSampleScratch = [Float](repeating: 0, count: frameCount)
        }
        monoSampleScratch.withUnsafeMutableBufferPointer { dst in
            _ = memcpy(dst.baseAddress!, channelData[0],
                       frameCount * MemoryLayout<Float>.stride)
        }

        var phase: Float = 1.0
        if channels > 1 {
            var dotProd: Float = 0
            var sumSqL: Float = 0
            var sumSqR: Float = 0
            vDSP_dotpr(monoSampleScratch, 1, channelData[1], 1, &dotProd, vDSP_Length(frameCount))
            vDSP_svesq(monoSampleScratch, 1, &sumSqL, vDSP_Length(frameCount))
            vDSP_svesq(channelData[1], 1, &sumSqR, vDSP_Length(frameCount))
            phase = dotProd / (sqrt(sumSqL * sumSqR) + 1e-9)
        }

        // Publish stereo state via lock so updateUI drains it at 60 Hz instead of
        // queueing 86 DispatchQueue.main.async closures/sec from the RT thread.
        let isStereo = channels > 1
        rtStereoLock.withLockUnchecked { state in
            state.isStereo = isStereo
            state.phase = phase
        }

        processSamples(monoSampleScratch)
    }
    
    private func processSamples(_ newSamples: [Float]) {
        let rtSettings = rtSettingsLock.withLockUnchecked { $0 }
        let cal = rtSettings.calibrationOffset

        // Calculate peak level (dBFS → dB SPL mit Kalibrierung)
        var rms: Float = 0
        vDSP_rmsqv(newSamples, 1, &rms, vDSP_Length(newSamples.count))
        let signalDBFS = 20 * log10(rms + 1e-9)
        // vDSP_maxmgv returns max-magnitude (|x|): correct for signed audio peak
        // (a negative trough like -0.95 vs +0.10 was previously ignored by `max()`)
        // and faster than scalar `max()` + `abs()`.
        var peakAbs: Float = 0
        vDSP_maxmgv(newSamples, 1, &peakAbs, vDSP_Length(newSamples.count))
        let peakDBFS = 20 * log10(peakAbs + 1e-9)
        let peakDB = peakDBFS + cal  // Konvertiere zu dB SPL
        
        debugPrintCounter += 1
        
        // Impulse detection (measure end-to-end latency) + one-shot silence warning.
        signalMonitor.detectImpulse(signalDBFS: signalDBFS, now: CFAbsoluteTimeGetCurrent())
        signalMonitor.logSilenceIfNeeded(signalDBFS: signalDBFS)
        
        // Append + downstream ring mutations are serialised against
        // `applyFFTConfiguration` / `setBlockSize` / `setWindowFunction` (which
        // also reset the ring under `processingLock` on main). Without this
        // guard a reconfigure during a tap callback races on Swift array
        // storage. Lock width is kept to the array operations themselves;
        // downstream FFT work already takes its own snapshots.
        let (currentFFTSize, currentSampleRate, bufferedSamples) = processingLock.withLockUnchecked { () -> (Int, Double, Int) in
            sampleRing.append(newSamples)
            return (fftSize, processingSampleRate, sampleRing.bufferedCount)
        }

        // Backlog (wie viel Audio noch in der Queue steckt)
        let bufferedSeconds = Double(bufferedSamples) / currentSampleRate
        rtPerfLock.withLockUnchecked { stats in
            if bufferedSeconds > stats.maxBufferedSeconds {
                stats.maxBufferedSeconds = bufferedSeconds
            }
        }
        // Keep the visualization near real-time: if processing falls behind,
        // drop oldest queued samples instead of rendering stale history.
        // Never trim below one full FFT window (+ one hop), otherwise no frames can be processed.
        let hop = max(1, rtSettings.scrollSpeed.rawValue)
        let minRequiredBufferedSeconds = Double(currentFFTSize + hop) / currentSampleRate
        let effectiveBacklogLimitSeconds = max(maxRealtimeBacklogSeconds, minRequiredBufferedSeconds)
        if bufferedSeconds > effectiveBacklogLimitSeconds {
            let targetBufferedSamples = Int(effectiveBacklogLimitSeconds * currentSampleRate)
            var samplesToDrop = bufferedSamples - targetBufferedSamples
            if samplesToDrop > 0 {
                samplesToDrop = (samplesToDrop / hop) * hop
                processingLock.withLockUnchecked {
                    sampleRing.dropOldest(samplesToDrop)
                }
            }
        }

        // Absolute compaction ceiling: the per-iteration compaction inside the
        // while loop only fires when the loop body runs. If the backlog trimmer
        // jumped the offset far ahead without the loop executing, drop the
        // dead head of the array now so the underlying storage cannot grow
        // unbounded under sustained pressure.
        let absoluteCompactionThreshold = currentFFTSize * 4
        processingLock.withLockUnchecked {
            sampleRing.compactIfNeeded(threshold: absoluteCompactionThreshold)
        }

        // Process when we have enough samples (using offset for O(1) instead of O(n) removeFirst).
        // Lock spans the read+copy+offset advance; processFFTFrame runs outside
        // the lock so we don't hold it across FFT/weighting work.
        while true {
            let frame: [Float]? = processingLock.withLockUnchecked {
                sampleRing.nextFrame(frameSize: currentFFTSize, hop: hop)
            }
            guard let frame else { break }

            let t0 = CFAbsoluteTimeGetCurrent()
            processFFTFrame(samples: frame, peakLevel: peakDB)
            let t1 = CFAbsoluteTimeGetCurrent()
            let elapsedMs = (t1 - t0) * 1000.0
            rtPerfLock.withLockUnchecked { stats in
                stats.fftProcessTimeAccumMs += elapsedMs
                stats.fftProcessCount += 1
            }
        }
    }
    
    private func processFFTFrame(samples: [Float], peakLevel: Float) {
        let signpostID = OSSignpostID(log: Self.performanceLog)
        os_signpost(.begin, log: Self.performanceLog, name: "FFTFrameProcessing", signpostID: signpostID)
        defer { os_signpost(.end, log: Self.performanceLog, name: "FFTFrameProcessing", signpostID: signpostID) }

        // Snapshot all cross-thread settings once at the top of the frame.
        let rtSettings = rtSettingsLock.withLockUnchecked { $0 }
        let cal = rtSettings.calibrationOffset

        // Thread-sichere FFT-Verarbeitung — snapshot all lock-protected
        // fields in one critical section to keep them mutually consistent.
        let (currentFFTSize, currentSampleRate, localFFTProcessor, localWeightingProcessor, localPipeline) = processingLock.withLockUnchecked {
            (fftSize, processingSampleRate, fftProcessor, weightingProcessor, processingPipeline)
        }

        // Prüfe ob Samples zur aktuellen FFT-Größe passen
        guard samples.count >= currentFFTSize else { return }

        // Gate A/C spectral tracks to data consumers that actually need them.
        // Z is always available; A/C are emitted only for the selected global
        // weighting, active widget overrides, or measurement recording.
        let requiredSpectralWeightings = requiredSpectralWeightingsForCurrentFrame(
            frequencyWeighting: rtSettings.frequencyWeighting
        )
        // Bark band aggregation — only when a widget requests it (zero-cost otherwise).
        let needsBark = widgetBarkBandsRequiredLock.withLockUnchecked { $0 }

        // Pure per-frame DSP runs in ProcessingPipeline (Phase 3, Task 3.3).
        // DCT/Mel pipeline removed from the real-time audio thread (M19 regression).
        // AE-5: Logger calls are not real-time safe — periodic FFT-range logging
        // stays off the audio render thread (use os_signpost / Instruments).
        let dsp = localPipeline.computeFrame(
            samples: samples,
            fftProcessor: localFFTProcessor,
            weightingProcessor: localWeightingProcessor,
            spectrogramProcessor: spectrogramProcessor,
            sampleRate: currentSampleRate,
            gainBoost: rtSettings.gainBoost,
            calibrationOffset: cal,
            needsA: requiredSpectralWeightings.contains(.a),
            needsC: requiredSpectralWeightings.contains(.c),
            needsBark: needsBark
        )

        let dbZ = dsp.fullDBZ
        let displayOctaveBandsZ = dsp.displayOctaveBandsZ
        let displayOctaveBandsA = dsp.displayOctaveBandsA
        let displayOctaveBandsC = dsp.displayOctaveBandsC
        let displayBarkBandsZ = dsp.barkBandsZ
        let displayBarkBandsA = dsp.barkBandsA
        let displayBarkBandsC = dsp.barkBandsC

        // Update acoustic metrics
        let dt = Float(rtSettings.scrollSpeed.rawValue) / Float(currentSampleRate)
        spectrogramProcessor.hopDuration = dt
        // Derive recording duration on the audio thread from the lock-mirrored
        // recordingStartTime rather than reading `@Published recording.recordingDuration`.
        let nowRef = CFAbsoluteTimeGetCurrent()
        let audioThreadRecordingDuration: TimeInterval
        if let startTime = rtSettings.recordingStartTime {
            audioThreadRecordingDuration = max(0, nowRef - startTime.timeIntervalSinceReferenceDate)
        } else {
            audioThreadRecordingDuration = 0
        }
        let metricsResult = metricsCalculator.updateMetrics(
            energyZ: dsp.energyZ,
            energyA: dsp.energyA,
            energyC: dsp.energyC,
            peakLevel: dsp.lcPeak,
            dt: dt,
            recordingDuration: audioThreadRecordingDuration,
            frequencies: localFFTProcessor.frequencies,
            magnitudes: dbZ,
            bandsZ: displayOctaveBandsZ,
            bandsA: dsp.hasA ? displayOctaveBandsA : [],
            bandsC: dsp.hasC ? displayOctaveBandsC : [],
            loudnessReferenceKey: Self.loudnessLevelKey(for: rtSettings.frequencyWeighting)
        )
        let levels = metricsResult.levels

        let broadbandLevel = levels["LAF"] ?? -120.0

        // Writer lifecycle lives on main: `startAudioCapture` /
        // `startRealRecording` set it up at recording start, and the
        // `measurementRecordingSink` (RecordingCoordinator bridge) handles
        // mid-session toggles. The per-frame call removed here did
        // FileManager + writer allocation on the audio render thread —
        // forbidden by the M15 real-time-safety contract.
        // Read flags via audio-thread-safe mirrors (AE-3).
        // Load the writer reference under the lock (AE-2).
        let atIsRecording = audioThreadIsRecordingToFile.withLockUnchecked { $0 }
        let atIsMeasurement = audioThreadIsMeasurementRecording.withLockUnchecked { $0 }
        if atIsRecording && atIsMeasurement {
            if let writer = recordingWriter.rtLoadMeasurementWriter() {
                let timestampSeconds = Float(audioThreadRecordingDuration)
                // RT-5: fill a preallocated buffer instead of `map` per frame.
                let keys = recordingWriter.metricKeys
                if metricValuesScratch.count != keys.count {
                    metricValuesScratch = [Float](repeating: -120.0, count: keys.count)
                }
                for index in keys.indices {
                    metricValuesScratch[index] = levels[keys[index]] ?? -120.0
                }
                do {
                    try writer.writeFrame(
                        timestamp: timestampSeconds,
                        metricValues: metricValuesScratch,
                        broadbandLevel: broadbandLevel,
                        thirdOctaveZ: displayOctaveBandsZ,
                        thirdOctaveA: displayOctaveBandsA,
                        thirdOctaveC: displayOctaveBandsC,
                        fullFFT: dbZ
                    )
                } catch {
                    // AE-5: Logger is not real-time safe. Store the error description
                    // in an atomic cell; the main-thread updateUI block logs and clears it.
                    lastWriteErrorLock.withLockUnchecked { $0 = error.localizedDescription }
                }
            }
        }
        
        logSpectrumDiagnosticsIfNeeded(
            fullFrequencies: localFFTProcessor.frequencies,
            fullMagnitudes: dbZ,
            binnedFrequencies: dsp.bandFrequencies,
            binnedMagnitudes: dsp.bandMagnitudesZ
        )
        
        let bufferTimestamp = rtPerfLock.withLockUnchecked { $0.lastAudioBufferTimestamp }

        // Create spectrogram data with all weightings
        let spectrogramData = SpectrogramData(
            frequencies: dsp.bandFrequencies,
            magnitudes: dsp.bandMagnitudesZ,            // Z-weighted (linear)
            magnitudesA: dsp.bandMagnitudesA,           // A-weighted when requested
            magnitudesC: dsp.bandMagnitudesC,           // C-weighted when requested
            visualFrequencies: nil,
            visualMagnitudes: nil,
            broadbandLevel: broadbandLevel,
            levels: levels,
            sampleRate: currentSampleRate,
            timestamp: Date(timeIntervalSinceReferenceDate: bufferTimestamp)
        )
        
        // Feed spectrogram renderers directly — bypasses objectWillChange, no SwiftUI re-render.
        emitSpectrogramData(spectrogramData)

        // Update UI on main thread
        updateUI(
            spectrogramData: spectrogramData,
            octaveBandsZ: displayOctaveBandsZ,
            octaveBandsA: displayOctaveBandsA,
            octaveBandsC: displayOctaveBandsC,
            bandLeqZ: metricsResult.bandLeqZ,
            bandLeqA: metricsResult.bandLeqA,
            bandLeqC: metricsResult.bandLeqC,
            barkBandsZ: displayBarkBandsZ,
            barkBandsA: displayBarkBandsA,
            barkBandsC: displayBarkBandsC,
            broadbandLevel: broadbandLevel,
            peakLevel: peakLevel,
            processEndTime: CFAbsoluteTimeGetCurrent()
        )
    }

    private func requiredSpectralWeightingsForCurrentFrame(
        frequencyWeighting: FrequencyWeighting
    ) -> Set<FrequencyWeighting> {
        var weightings: Set<FrequencyWeighting> = [.z, frequencyWeighting]
        // Read via audio-thread-safe mirror locks (AE-3).
        if audioThreadIsRecordingToFile.withLockUnchecked({ $0 })
            && audioThreadIsMeasurementRecording.withLockUnchecked({ $0 }) {
            weightings.formUnion([.a, .c])
        }

        let widgetWeightings = widgetSpectralWeightingsLock.withLockUnchecked { $0 }
        weightings.formUnion(widgetWeightings)
        return weightings
    }
    
    /// RT-5: latest UI payload, written by the render thread and drained
    /// by `uiPumpTimer` on main. Replaces one `DispatchQueue.main.async`
    /// block allocation per frame from the render thread.
    private struct PendingUIFrame {
        let spectrogramData: SpectrogramData
        let octaveBandsZ: [Float]
        let octaveBandsA: [Float]
        let octaveBandsC: [Float]
        let bandLeqZ: [Float]
        let bandLeqA: [Float]
        let bandLeqC: [Float]
        let barkBandsZ: [Float]
        let barkBandsA: [Float]
        let barkBandsC: [Float]
        let broadbandLevel: Float
        let peakLevel: Float
        let processEndTime: TimeInterval
        let bufferTs: TimeInterval
        let processingLagMs: Double
    }
    private let pendingUIFrameLock = OSAllocatedUnfairLock<PendingUIFrame?>(initialState: nil)
    /// `true` while the main-thread pump timer runs (or a start is pending).
    private let uiPumpRequested = OSAllocatedUnfairLock<Bool>(initialState: false)
    private var uiPumpTimer: Timer?
    private var uiPumpIdleTicks = 0

    private func updateUI(
        spectrogramData: SpectrogramData,
        octaveBandsZ: [Float],
        octaveBandsA: [Float],
        octaveBandsC: [Float],
        bandLeqZ: [Float],
        bandLeqA: [Float],
        bandLeqC: [Float],
        barkBandsZ: [Float],
        barkBandsA: [Float],
        barkBandsC: [Float],
        broadbandLevel: Float,
        peakLevel: Float,
        processEndTime: TimeInterval
    ) {
        guard uiThrottle.shouldEnqueueUI(now: processEndTime) else {
            return
        }

        let bufferTs = rtPerfLock.withLockUnchecked { $0.lastAudioBufferTimestamp }
        let frame = PendingUIFrame(
            spectrogramData: spectrogramData,
            octaveBandsZ: octaveBandsZ,
            octaveBandsA: octaveBandsA,
            octaveBandsC: octaveBandsC,
            bandLeqZ: bandLeqZ,
            bandLeqA: bandLeqA,
            bandLeqC: bandLeqC,
            barkBandsZ: barkBandsZ,
            barkBandsA: barkBandsA,
            barkBandsC: barkBandsC,
            broadbandLevel: broadbandLevel,
            peakLevel: peakLevel,
            processEndTime: processEndTime,
            bufferTs: bufferTs,
            processingLagMs: (processEndTime - bufferTs) * 1000.0
        )
        pendingUIFrameLock.withLockUnchecked { $0 = frame }

        // Start the pump once per idle → active transition (not per frame).
        let needsStart: Bool = uiPumpRequested.withLockUnchecked { requested in
            if requested { return false }
            requested = true
            return true
        }
        if needsStart {
            DispatchQueue.main.async { [weak self] in self?.startUIPumpIfNeeded() }
        }
    }

    private func startUIPumpIfNeeded() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard uiPumpTimer == nil else { return }
        uiPumpIdleTicks = 0
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.drainPendingUIFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        uiPumpTimer = timer
        drainPendingUIFrame()
    }

    private func drainPendingUIFrame() {
        guard let frame = pendingUIFrameLock.withLock({ pending -> PendingUIFrame? in
            let f = pending; pending = nil; return f
        }) else {
            // Stop after ~1 s without frames; the next frame restarts it.
            uiPumpIdleTicks += 1
            if uiPumpIdleTicks > 60 {
                uiPumpTimer?.invalidate()
                uiPumpTimer = nil
                uiPumpRequested.withLock { $0 = false }
                // A frame may have landed between the drain and the reset.
                if pendingUIFrameLock.withLock({ $0 != nil }) {
                    uiPumpRequested.withLock { $0 = true }
                    startUIPumpIfNeeded()
                }
            }
            return
        }
        uiPumpIdleTicks = 0
        applyUIFrame(frame)
    }

    private func applyUIFrame(_ frame: PendingUIFrame) {
        let spectrogramData = frame.spectrogramData
        let octaveBandsZ = frame.octaveBandsZ
        let octaveBandsA = frame.octaveBandsA
        let octaveBandsC = frame.octaveBandsC
        let bandLeqZ = frame.bandLeqZ
        let bandLeqA = frame.bandLeqA
        let bandLeqC = frame.bandLeqC
        let barkBandsZ = frame.barkBandsZ
        let barkBandsA = frame.barkBandsA
        let barkBandsC = frame.barkBandsC
        let broadbandLevel = frame.broadbandLevel
        let peakLevel = frame.peakLevel
        let processEndTime = frame.processEndTime
        let bufferTs = frame.bufferTs
        let processingLagMs = frame.processingLagMs
        self.latencyLogCounter += 1
        if self.latencyLogCounter % 120 == 0 {
            let uiLagMs = (CFAbsoluteTimeGetCurrent() - bufferTs) * 1000.0
            let mainThreadDelayMs = (CFAbsoluteTimeGetCurrent() - processEndTime) * 1000.0
            let (accumMs, count, maxBuf) = self.rtPerfLock.withLock { stats -> (Double, Int, Double) in
                let snapshot = (stats.fftProcessTimeAccumMs, stats.fftProcessCount, stats.maxBufferedSeconds)
                stats.fftProcessTimeAccumMs = 0
                stats.fftProcessCount = 0
                stats.maxBufferedSeconds = 0
                return snapshot
            }
            let avgFftMs = count > 0 ? (accumMs / Double(count)) : 0
            let line = String(
                format: "[Latency] processing %.0f ms, main-thread delay %.0f ms, UI %.0f ms, FFT avg %.1f ms, backlog %.2f s",
                processingLagMs,
                mainThreadDelayMs,
                uiLagMs,
                avgFftMs,
                maxBuf
            )
            print(line)
        }

        let stereo = self.rtStereoLock.withLock { $0 }
        if self.live.isStereoActive != stereo.isStereo {
            self.live.isStereoActive = stereo.isStereo
        }
        if stereo.isStereo || self.live.currentStereoPhase != stereo.phase {
            self.live.currentStereoPhase = stereo.phase
        }

        self.signalMonitor.reportPendingImpulse(peakDbfs: peakLevel - self.effectiveCalibrationOffset)

        // AE-5: Drain any write error reported from the audio thread.
        if let errDesc = self.lastWriteErrorLock.withLock({ old -> String? in
            let v = old; old = nil; return v
        }) {
            Logger.audioEngine.error("Measurement frame write failed: \(errDesc)")
        }

        // Update recording duration
        if let startTime = self.recordingStartTime {
            self.recording.recordingDuration = Date().timeIntervalSince(startTime)
        }
        
        // Update data — currentSpectrogramData throttled to 15 Hz to reduce
        // objectWillChange pressure on the SwiftUI hierarchy (spectrogram
        // renderers get data at full rate via spectrogramSubject).
        if self.uiThrottle.shouldPublishSpectrogram(now: CFAbsoluteTimeGetCurrent()) {
            self.live.currentSpectrogramData = spectrogramData
        }
        self.live.currentOctaveBandsZ = octaveBandsZ
        self.live.currentOctaveBandsA = octaveBandsA
        self.live.currentOctaveBandsC = octaveBandsC
        if !bandLeqZ.isEmpty {
            self.live.bandLeqZ = bandLeqZ
            self.live.bandLeqOctaveZ = Self.octaveLeqBands(fromThirds: bandLeqZ)
        }
        if !bandLeqA.isEmpty {
            self.live.bandLeqA = bandLeqA
            self.live.bandLeqOctaveA = Self.octaveLeqBands(fromThirds: bandLeqA)
        }
        if !bandLeqC.isEmpty {
            self.live.bandLeqC = bandLeqC
            self.live.bandLeqOctaveC = Self.octaveLeqBands(fromThirds: bandLeqC)
        }
        if !barkBandsZ.isEmpty { self.live.currentBarkBandsZ = barkBandsZ }
        if !barkBandsA.isEmpty { self.live.currentBarkBandsA = barkBandsA }
        if !barkBandsC.isEmpty { self.live.currentBarkBandsC = barkBandsC }
        // Use the IEC 61672 LCpeak from the metrics dict (C-weighted peak,
        // computed in processFFTFrame). Fall back to the raw sample peak only
        // if the metrics dict is somehow missing the key.
        self.live.currentPeakLevel = spectrogramData.levels["LCpeak"] ?? max(self.live.currentPeakLevel, peakLevel)
        self.live.currentLevel = broadbandLevel
        self.onBandsUpdated?(octaveBandsZ, broadbandLevel)

        // Update min/max
        self.live.maxLevel = max(self.live.maxLevel, broadbandLevel)
        if broadbandLevel > -110 {
            self.live.minLevel = min(self.live.minLevel, broadbandLevel)
        }
        
        // Update history. The previous form (`append` + `removeFirst()`) ran
        // ~60×/s with `levelHistory` at 1000 floats — that's ~60 K element
        // shifts per second. Amortize by letting the array grow to a small
        // overshoot and trimming a chunk in one O(n) pass, instead of a
        // per-tick shift.
        self.live.levelHistory.append(broadbandLevel)
        let overshootBudget = 64
        if self.live.levelHistory.count > self.maxHistorySize + overshootBudget {
            self.live.levelHistory.removeFirst(self.live.levelHistory.count - self.maxHistorySize)
        }
        
        // Send to watch (throttled)
        // Watch display expects dBFS magnitudes (-180…-40), not dB SPL.
        // Subtract calibrationOffset to convert back from dB SPL → dBFS.
        if self.uiThrottle.shouldSendToWatch(now: Date().timeIntervalSince1970) {
            let offset = self.effectiveCalibrationOffset
            var negOffset = -offset
            var dbfsMagnitudes = spectrogramData.magnitudes
            vDSP_vsadd(dbfsMagnitudes, 1, &negOffset, &dbfsMagnitudes, 1, vDSP_Length(dbfsMagnitudes.count))
            var visualDBFSMagnitudes = spectrogramData.visualMagnitudes
            if var visual = visualDBFSMagnitudes {
                vDSP_vsadd(visual, 1, &negOffset, &visual, 1, vDSP_Length(visual.count))
                visualDBFSMagnitudes = visual
            }
            let watchData = SpectrogramData(
                frequencies: spectrogramData.frequencies,
                magnitudes: dbfsMagnitudes,
                magnitudesA: spectrogramData.magnitudesA,
                magnitudesC: spectrogramData.magnitudesC,
                visualFrequencies: spectrogramData.visualFrequencies,
                visualMagnitudes: visualDBFSMagnitudes,
                broadbandLevel: spectrogramData.broadbandLevel,
                levels: spectrogramData.levels,
                sampleRate: spectrogramData.sampleRate,
                timestamp: spectrogramData.timestamp
            )
            self.connectivityManager.sendSpectrogramData(watchData)
        }
    }

    private func logSpectrumDiagnosticsIfNeeded(
        fullFrequencies: [Float],
        fullMagnitudes: [Float],
        binnedFrequencies: [Float],
        binnedMagnitudes: [Float]
    ) {
        guard enableSpectrumDiagnostics else { return }
        spectrumDiagnosticsCounter += 1
        guard spectrumDiagnosticsCounter % 120 == 0 else { return }

        let full = SpectrogramProcessor.makeDiagnosticSnapshot(
            frequencies: fullFrequencies,
            magnitudes: fullMagnitudes
        )
        let binned = SpectrogramProcessor.makeDiagnosticSnapshot(
            frequencies: binnedFrequencies,
            magnitudes: binnedMagnitudes
        )

        let fullRanges = full.rangeDiagnostics.map {
            "\($0.label):\($0.energeticBins)/\($0.totalBins),max=\(String(format: "%.1f", $0.maxDb))"
        }.joined(separator: " | ")
        let binnedRanges = binned.rangeDiagnostics.map {
            "\($0.label):\($0.energeticBins)/\($0.totalBins),max=\(String(format: "%.1f", $0.maxDb))"
        }.joined(separator: " | ")
        let emptyBands = binned.emptyThirdOctaveBands.prefix(8).map { String(format: "%.0f", $0) }.joined(separator: ",")
        let binHz = processingSampleRate / Double(max(1, fftSize))

        Logger.audioEngine.debug(
            """
            [SpectrumDiag] srIn=\(self.lastObservedInputSampleRate, format: .fixed(precision: 1))Hz srProc=\(self.processingSampleRate, format: .fixed(precision: 1))Hz \
            fft=\(self.fftSize) binHz=\(binHz, format: .fixed(precision: 2)) \
            full{\(fullRanges)} binned{\(binnedRanges)} \
            binnedEmpty3rd=\(emptyBands) fullHigh=\(full.highestEnergeticFrequencyHz, format: .fixed(precision: 0))Hz \
            binnedHigh=\(binned.highestEnergeticFrequencyHz, format: .fixed(precision: 0))Hz
            """
        )
    }

    /// Compute display 1/3-octave band SPL for the watch ingest /
    /// emission path. Logic lives in
    /// `Managers/SpectrumBandAggregator.swift` (M13 task-6) — the
    /// previous in-engine implementation was a duplicate of the
    /// widget-side fallback, and the M12 "negative offset" bug came
    /// from those two implementations drifting apart.
    private func computeDisplayThirdOctaveBands(frequencies: [Float], magnitudes: [Float]) -> [Float] {
        SpectrumBandAggregator.thirdOctaveBands(frequencies: frequencies, spectrum: magnitudes)
    }

    /// Broadband `levels[...]` key used for PHON/SONE given the active weighting.
    private static func loudnessLevelKey(for weighting: FrequencyWeighting) -> String {
        switch weighting {
        case .a: return "LAF"
        case .c: return "LCF"
        case .z: return "LZF"
        }
    }

    /// Pre-aggregates 31 third-octave Leq values into 10 octave Leq bands for widgets.
    private static func octaveLeqBands(fromThirds thirds: [Float]) -> [Float] {
        guard thirds.count == SpectrumBandAggregator.thirdOctaveCenters.count else { return [] }
        return SpectrumBandAggregator.octaveBands(
            frequencies: [],
            spectrum: [],
            fromThirds: thirds
        )
    }

    /// RT-5: the render thread (and the playback tap queue) only *request*
    /// a sample-rate change; the FFT/weighting processors are rebuilt on main.
    /// Frames keep using the previous processors until the swap lands.
    private let pendingSampleRateLock = OSAllocatedUnfairLock<(rate: Double, source: StaticString)?>(initialState: nil)

    private func updateProcessingSampleRateIfNeeded(_ newSampleRate: Double, source: StaticString) {
        guard newSampleRate > 1000 else { return }
        let normalized = (newSampleRate * 10).rounded() / 10
        let currentRate = processingLock.withLockUnchecked { processingSampleRate }
        guard abs(normalized - currentRate) > 1.0 else { return }

        if Thread.isMainThread {
            applyProcessingSampleRate(normalized, source: source)
            return
        }
        let firstRequest: Bool = pendingSampleRateLock.withLockUnchecked { pending in
            let isNew = pending == nil
            pending = (normalized, source)
            return isNew
        }
        if firstRequest {
            // One hop per sample-rate change (not per frame).
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let request = self.pendingSampleRateLock.withLock({ pending -> (rate: Double, source: StaticString)? in
                          let r = pending; pending = nil; return r
                      }) else { return }
                self.applyProcessingSampleRate(request.rate, source: request.source)
            }
        }
    }

    /// Main thread: rebuilds the processors for `rate` and swaps them in.
    private func applyProcessingSampleRate(_ rate: Double, source: StaticString) {
        dispatchPrecondition(condition: .onQueue(.main))
        let (size, window) = processingLock.withLockUnchecked { (fftSize, fftProcessor.windowFunction) }
        let newFFT = FFTProcessor(fftSize: size, sampleRate: rate, windowFunction: window)
        let newWeighting = FrequencyWeightingProcessor(fftSize: size, sampleRate: rate)
        let retired: [AnyObject] = processingLock.withLockUnchecked {
            let old: [AnyObject] = [fftProcessor, weightingProcessor]
            processingSampleRate = rate
            sampleRing.reset()
            fftProcessor = newFFT
            weightingProcessor = newWeighting
            return old
        }
        retireDSPObjects(retired)
        Logger.audioEngine.info("Reconfigured DSP sample rate (\(String(describing: source))): \(rate, format: .fixed(precision: 1)) Hz")
    }
}
