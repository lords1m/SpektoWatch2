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
    private let visualSpectrogramProcessor: VisualSpectrogramProcessor
    /// Pure per-frame DSP (FFT → weighting → bands → energies → LCpeak) and the
    /// real-time scratch buffers (extracted in Phase 3, Task 3.3). Driven only
    /// from the audio render thread via `processFFTFrame`.
    private let processingPipeline = ProcessingPipeline()
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
    /// Always touched under `processingLock`, except the lockless reset in
    /// `stopAudioCapture` (matching the pre-extraction inline buffers).
    private let sampleRing = SampleRingBuffer()
    private var visualDBMagnitudesScratch: [Float] = []
    private var gainBoost: Float = 10.0

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

    // MARK: - State Management

    private var isUsingDummyData = false
    private var isStartingCapture = false
    private var debugPrintCounter = 0
    private let maxHistorySize = 1000
    private var lastAudioBufferTimestamp: TimeInterval = 0
    private var latencyLogCounter = 0
    private var fftProcessTimeAccumMs: Double = 0
    private var fftProcessCount: Int = 0
    private var maxBufferedSeconds: Double = 0
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
            CalibrationProvider.persist(offset: calibrationOffset)
        }
    }
    private var currentInputGain: Float = 1.0

    // MARK: - Recording

    private var recordingStartTime: Date?

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
    @Published var scrollSpeed: ScrollSpeed = .normal
    
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
        // Visualisierungspfad nach Apple "Visualizing Sound as an Audio
        // Spectrogram": DCT-II auf dem gefensterten Sample-Block, Mel-
        // Filterbank mit 128 Bändern (20 Hz – 20 kHz), anschließend 20·log10.
        // Mel-Bänder sind bereits perzeptuell skaliert; der Adapter respektiert
        // `visualFrequencies` und überlagert keine zweite Log-Achse mehr.
        let initialResolution = SpectrogramResolution.current
        visualSpectrogramProcessor = VisualSpectrogramProcessor(
            transformSize: fftSize,
            sampleRate: processingSampleRate,
            windowFunction: .hann,
            melBandCount: initialResolution.melBandCount,
            frequencyRange: 20...20_000
        )
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
        visualSpectrogramProcessor.reconfigure(
            transformSize: fftSize,
            sampleRate: processingSampleRate,
            windowFunction: currentWindowFunction,
            melBandCount: spectrogramResolution.melBandCount
        )
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

        // Thread-sichere Rekonfiguration
        processingLock.withLockUnchecked {
            // Buffer leeren um Race-Conditions zu vermeiden
            sampleRing.reset()
            visualDBMagnitudesScratch.removeAll()

            // AE-7: Pre-allocate energy scratch buffers to the new FFT bin count so
            // the audio render thread never hits the lazy-allocation branch in
            // processFFTFrame. energyCount == newSize/2 (half-spectrum bin count).
            processingPipeline.resetScratch(energyCount: newSize / 2)

            // Aktualisiere interne Werte
            fftSize = newSize
            currentWindowFunction = newWindow
            currentBlockSize = config.blockSize

            // Rekonfiguriere den FFT Processor
            fftProcessor.reconfigure(fftSize: newSize, windowFunction: newWindow)
            visualSpectrogramProcessor.reconfigure(
                transformSize: newSize,
                sampleRate: processingSampleRate,
                windowFunction: newWindow
            )

            // Erstelle neuen Weighting Processor (alter wird nach unlock freigegeben)
            let newWeightingProcessor = FrequencyWeightingProcessor(fftSize: newSize, sampleRate: processingSampleRate)
            weightingProcessor = newWeightingProcessor
        }

        // Veröffentliche Änderungen
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    /// Setzt nur die Fensterfunktion
    func setWindowFunction(_ function: WindowFunction) {
        guard function != currentWindowFunction else { return }

        processingLock.withLockUnchecked {
            currentWindowFunction = function
            fftProcessor.setWindowFunction(function)
            visualSpectrogramProcessor.reconfigure(
                transformSize: fftSize,
                sampleRate: processingSampleRate,
                windowFunction: function
            )
        }
        Logger.audioEngine.info("Window function changed to: \(function.rawValue)")
    }

    /// Setzt nur die Blockgröße
    func setBlockSize(_ size: FFTBlockSize) {
        guard size.rawValue != fftSize else { return }

        processingLock.withLockUnchecked {
            // Buffer leeren um Race-Conditions zu vermeiden
            sampleRing.reset()
            visualDBMagnitudesScratch.removeAll()

            // AE-7: Pre-allocate energy scratch buffers.
            processingPipeline.resetScratch(energyCount: size.rawValue / 2)

            fftSize = size.rawValue
            currentBlockSize = size
            fftProcessor.reconfigure(fftSize: size.rawValue, windowFunction: currentWindowFunction)
            visualSpectrogramProcessor.reconfigure(
                transformSize: size.rawValue,
                sampleRate: processingSampleRate,
                windowFunction: currentWindowFunction
            )

            // Erstelle neuen Weighting Processor
            let newWeightingProcessor = FrequencyWeightingProcessor(fftSize: size.rawValue, sampleRate: processingSampleRate)
            weightingProcessor = newWeightingProcessor
        }

        Logger.audioEngine.info("FFT size changed to: \(size.rawValue)")
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

        DispatchQueue.main.async {
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

        if Thread.isMainThread {
            engineStatus = .starting
        } else {
            DispatchQueue.main.async {
                self.engineStatus = .starting
            }
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

        DispatchQueue.main.async {
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
        closeAudioFileWriter()
        closeMeasurementWriter()
        DispatchQueue.main.async {
            print("[AudioEngine] Setting engineStatus to .idle")
            self.engineStatus = .idle
            print("[AudioEngine] Setting recording.isRecordingToFile to false")
            self.recording.isRecordingToFile = false
            self.activeMicrophoneSource = nil
            self.isStartingCapture = false
            print("[AudioEngine] engineStatus is now: \(self.engineStatus)")
            print("[AudioEngine] recording.isRecordingToFile is now: \(self.recording.isRecordingToFile)")
        }

        if shouldUseTestAudioCapture || isUsingDummyData {
            testGenerator.stop()
        } else {
            captureSession.stop()
        }

        DispatchQueue.main.async {
            self.live.levelHistory.removeAll()
            self.live.levelHistory.reserveCapacity(self.maxHistorySize + 64)
            self.live.currentLevel = -120.0
        }

        // Reset buffer state
        sampleRing.reset()
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
        lastAudioBufferTimestamp = CFAbsoluteTimeGetCurrent()
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
                    self.finishAudioEngineSetup(isRecording: isRecording, dataSources: dataSources, audioSession: audioSession)
                }

            } catch {
                DispatchQueue.main.async {
                    Logger.audioEngine.error("Audio engine failed to start: \(error.localizedDescription)")
                    self.engineStatus = .error(error.localizedDescription)
                    self.isStartingCapture = false
                    Logger.audioEngine.info("Falling back to test audio generator")
                    self.testGenerator.start()
                    self.engineStatus = .running
                    self.isUsingDummyData = true
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
                Logger.audioEngine.warning("Invalid audio format detected - falling back to test audio")
                testGenerator.start()
                DispatchQueue.main.async {
                    self.engineStatus = .running
                    self.isStartingCapture = false
                }
                isUsingDummyData = true
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
            DispatchQueue.main.async {
                self.engineStatus = .running
                self.isStartingCapture = false
            }

        } catch {
            Logger.audioEngine.error("Audio engine setup failed: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.engineStatus = .error(error.localizedDescription)
                self.isStartingCapture = false
            }
            Logger.audioEngine.info("Falling back to test audio generator")
            testGenerator.start()
            DispatchQueue.main.async {
                self.engineStatus = .running
            }
            isUsingDummyData = true
        }
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
            if abs(observedSampleRate - processingSampleRate) > 1.0 && debugPrintCounter % 240 == 0 {
                Logger.audioEngine.warning(
                    "Mic sample-rate mismatch: input \(observedSampleRate, format: .fixed(precision: 1)) Hz vs processing \(self.processingSampleRate, format: .fixed(precision: 1)) Hz"
                )
            }
        }

        lastAudioBufferTimestamp = CFAbsoluteTimeGetCurrent()
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

        processSamples(monoSampleScratch)

        let isStereo = channels > 1
        // Only dispatch when values actually change — isStereoActive rarely flips,
        // so unconditionally queueing 86 closures/sec was pure overhead.
        let capturedPhase = phase
        DispatchQueue.main.async {
            if self.live.isStereoActive != isStereo { self.live.isStereoActive = isStereo }
            self.live.currentStereoPhase = capturedPhase
        }
    }
    
    private func processSamples(_ newSamples: [Float]) {
        // Calculate peak level (dBFS → dB SPL mit Kalibrierung)
        var rms: Float = 0
        vDSP_rmsqv(newSamples, 1, &rms, vDSP_Length(newSamples.count))
        let signalDBFS = 20 * log10(rms + 1e-9)
        let signalDB = signalDBFS + calibrationOffset  // Konvertiere zu dB SPL
        // vDSP_maxmgv returns max-magnitude (|x|): correct for signed audio peak
        // (a negative trough like -0.95 vs +0.10 was previously ignored by `max()`)
        // and faster than scalar `max()` + `abs()`.
        var peakAbs: Float = 0
        vDSP_maxmgv(newSamples, 1, &peakAbs, vDSP_Length(newSamples.count))
        let peakDBFS = 20 * log10(peakAbs + 1e-9)
        let peakDB = peakDBFS + calibrationOffset  // Konvertiere zu dB SPL
        
        // Debug logging
        debugPrintCounter += 1
        if enableVerboseLogs && debugPrintCounter % 240 == 0 {
            let minSample = newSamples.min() ?? 0
            let maxSample = newSamples.max() ?? 0
            Logger.audioEngine.debug("Input RMS: \(signalDB, format: .fixed(precision: 1)) dB SPL (dBFS: \(signalDBFS, format: .fixed(precision: 1))), Samples: [\(minSample, format: .fixed(precision: 3)) ... \(maxSample, format: .fixed(precision: 3))]")
        }
        
        // Impulse detection (measure end-to-end latency) + one-shot silence warning.
        signalMonitor.detectImpulse(signalDBFS: signalDBFS, now: CFAbsoluteTimeGetCurrent())
        signalMonitor.logSilenceIfNeeded(signalDBFS: signalDBFS)
        
        // Append + downstream ring mutations are serialised against
        // `applyFFTConfiguration` / `setBlockSize` / `setWindowFunction` (which
        // also reset the ring under `processingLock` on main). Without this
        // guard a reconfigure during a tap callback races on Swift array
        // storage. Lock width is kept to the array operations themselves;
        // downstream FFT work already takes its own snapshots.
        processingLock.withLockUnchecked {
            sampleRing.append(newSamples)
        }

        // Lese aktuelle FFT-Größe thread-sicher.
        let currentFFTSize = processingLock.withLockUnchecked { fftSize }

        // Backlog (wie viel Audio noch in der Queue steckt)
        let bufferedSamples = processingLock.withLockUnchecked { sampleRing.bufferedCount }
        let bufferedSeconds = Double(bufferedSamples) / processingSampleRate
        if bufferedSeconds > maxBufferedSeconds {
            maxBufferedSeconds = bufferedSeconds
        }
        // Keep the visualization near real-time: if processing falls behind,
        // drop oldest queued samples instead of rendering stale history.
        // Never trim below one full FFT window (+ one hop), otherwise no frames can be processed.
        let hop = max(1, scrollSpeed.rawValue)
        let minRequiredBufferedSeconds = Double(currentFFTSize + hop) / processingSampleRate
        let effectiveBacklogLimitSeconds = max(maxRealtimeBacklogSeconds, minRequiredBufferedSeconds)
        if bufferedSeconds > effectiveBacklogLimitSeconds {
            let targetBufferedSamples = Int(effectiveBacklogLimitSeconds * processingSampleRate)
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
            fftProcessTimeAccumMs += (t1 - t0) * 1000.0
            fftProcessCount += 1
        }
    }
    
    private func processFFTFrame(samples: [Float], peakLevel: Float) {
        let signpostID = OSSignpostID(log: Self.performanceLog)
        os_signpost(.begin, log: Self.performanceLog, name: "FFTFrameProcessing", signpostID: signpostID)
        defer { os_signpost(.end, log: Self.performanceLog, name: "FFTFrameProcessing", signpostID: signpostID) }

        // R8: snapshot calibrationOffset once at the top of the frame so all
        // downstream uses (vDSP_vsadd, energy factor, LCpeak) see a consistent
        // value and the @Published property is not read multiple times on the
        // audio render thread.
        let cal = calibrationOffset

        // Thread-sichere FFT-Verarbeitung — snapshot all three lock-protected
        // fields in one critical section to keep them mutually consistent.
        let (currentFFTSize, localFFTProcessor, localWeightingProcessor) = processingLock.withLockUnchecked {
            (fftSize, fftProcessor, weightingProcessor)
        }

        // Prüfe ob Samples zur aktuellen FFT-Größe passen
        guard samples.count >= currentFFTSize else { return }

        // Gate A/C spectral tracks to data consumers that actually need them.
        // Z is always available; A/C are emitted only for the selected global
        // weighting, active widget overrides, or measurement recording.
        let requiredSpectralWeightings = requiredSpectralWeightingsForCurrentFrame()
        // Bark band aggregation — only when a widget requests it (zero-cost otherwise).
        let needsBark = widgetBarkBandsRequiredLock.withLockUnchecked { $0 }

        // Pure per-frame DSP runs in ProcessingPipeline (Phase 3, Task 3.3).
        // DCT/Mel pipeline removed from the real-time audio thread (M19 regression).
        // AE-5: Logger calls are not real-time safe — periodic FFT-range logging
        // stays off the audio render thread (use os_signpost / Instruments).
        let dsp = processingPipeline.computeFrame(
            samples: samples,
            fftProcessor: localFFTProcessor,
            weightingProcessor: localWeightingProcessor,
            spectrogramProcessor: spectrogramProcessor,
            sampleRate: processingSampleRate,
            gainBoost: gainBoost,
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
        let dt = Float(scrollSpeed.rawValue) / Float(processingSampleRate)
        spectrogramProcessor.hopDuration = dt
        // Derive recording duration on the audio thread from recordingStartTime
        // rather than reading the `@Published` `recording.recordingDuration` (main-only
        // writer). The same pattern is used a few lines below for the writer
        // timestamp.
        let audioThreadRecordingDuration: TimeInterval
        if let startTime = recordingStartTime {
            audioThreadRecordingDuration = Date().timeIntervalSince(startTime)
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
            loudnessReferenceKey: Self.loudnessLevelKey(for: frequencyWeighting)
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
                let timestampSeconds: Float
                if let startTime = recordingStartTime {
                    timestampSeconds = Float(Date().timeIntervalSince(startTime))
                } else {
                    timestampSeconds = Float(recording.recordingDuration)
                }
                let metricValues = recordingWriter.metricKeys.map { levels[$0] ?? -120.0 }
                do {
                    try writer.writeFrame(
                        timestamp: timestampSeconds,
                        metricValues: metricValues,
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
            sampleRate: processingSampleRate,
            timestamp: Date(timeIntervalSinceReferenceDate: lastAudioBufferTimestamp)
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

    private func requiredSpectralWeightingsForCurrentFrame() -> Set<FrequencyWeighting> {
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

        let bufferTs = lastAudioBufferTimestamp
        let processingLagMs = (processEndTime - bufferTs) * 1000.0
        DispatchQueue.main.async {
            self.latencyLogCounter += 1
            if self.latencyLogCounter % 120 == 0 {
                let uiLagMs = (CFAbsoluteTimeGetCurrent() - bufferTs) * 1000.0
                let mainThreadDelayMs = (CFAbsoluteTimeGetCurrent() - processEndTime) * 1000.0
                let avgFftMs = self.fftProcessCount > 0 ? (self.fftProcessTimeAccumMs / Double(self.fftProcessCount)) : 0
                let line = String(
                    format: "[Latency] processing %.0f ms, main-thread delay %.0f ms, UI %.0f ms, FFT avg %.1f ms, backlog %.2f s",
                    processingLagMs,
                    mainThreadDelayMs,
                    uiLagMs,
                    avgFftMs,
                    self.maxBufferedSeconds
                )
                print(line)
                self.fftProcessTimeAccumMs = 0
                self.fftProcessCount = 0
                self.maxBufferedSeconds = 0
            }

            self.signalMonitor.reportPendingImpulse(peakDbfs: peakLevel - self.calibrationOffset)

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
                let offset = self.calibrationOffset
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

    private func updateProcessingSampleRateIfNeeded(_ newSampleRate: Double, source: String) {
        guard newSampleRate > 1000 else { return }
        let normalized = (newSampleRate * 10).rounded() / 10
        guard abs(normalized - processingSampleRate) > 1.0 else { return }

        processingLock.withLockUnchecked {
            processingSampleRate = normalized
            sampleRing.reset()

            fftProcessor = FFTProcessor(
                fftSize: fftSize,
                sampleRate: normalized,
                windowFunction: currentWindowFunction
            )
            visualSpectrogramProcessor.reconfigure(
                transformSize: fftSize,
                sampleRate: normalized,
                windowFunction: currentWindowFunction
            )
            weightingProcessor = FrequencyWeightingProcessor(
                fftSize: fftSize,
                sampleRate: normalized
            )
        }

        Logger.audioEngine.info(
            "Reconfigured DSP sample rate (\(source)): \(normalized, format: .fixed(precision: 1)) Hz"
        )
    }
}
