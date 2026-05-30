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
        case .verySlow: return "Sehr Langsam"
        case .slow: return "Langsam"
        case .normal: return "Normal"
        case .fast: return "Schnell"
        case .veryFast: return "Sehr Schnell"
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
    case bottomBack = "Unten / Hinten"
    case frontBack = "Vorne / Hinten"
    case frontBottom = "Vorne / Unten"
}

/// Main audio engine coordinating FFT processing, frequency weighting, and acoustic metrics
class AudioEngine: ObservableObject {
    private static let performanceLog = OSLog(subsystem: "com.spektowatch", category: "performance.audio")
    // Canonical third-octave centers live in
    // `Managers/SpectrumBandAggregator.swift` (M13 task-6).
    private static let emptyThirdOctaveBands = [Float](
        repeating: -120.0,
        count: SpectrumBandAggregator.thirdOctaveCenters.count
    )
    
    // MARK: - Processing Components

    private var fftProcessor: FFTProcessor
    private var weightingProcessor: FrequencyWeightingProcessor
    private let metricsCalculator: AcousticMetricsCalculator
    private let spectrogramProcessor: SpectrogramProcessor
    private let visualSpectrogramProcessor: VisualSpectrogramProcessor
    private let testGenerator: TestAudioGenerator
    private let bandstopFilterManager: BandstopFilterManager
    private let connectivityManager: WatchConnectivityManager

    // MARK: - Audio Engine

    private var audioEngine: AVAudioEngine
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

    private var sampleBuffer: [Float] = []
    private var sampleBufferOffset: Int = 0  // Index-basierter Ansatz für O(1) "removeFirst"
    private var fftInputBuffer: [Float] = []
    private var fftLinearMagnitudesScratch: [Float] = []
    private var fftDBMagnitudesScratch: [Float] = []
    private var visualDBMagnitudesScratch: [Float] = []
    private var fftEnergyScratch: [Float] = []
    /// Scratch buffer for per-bin C-weighted amplitudes used in LCpeak computation.
    /// Resized alongside `fftEnergyScratch` when the FFT size changes.
    private var lcPeakScratch: [Float] = []
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
    private var hasLoggedSilence = false
    private var debugPrintCounter = 0
    private var lastWatchUpdate: TimeInterval = 0
    private let maxHistorySize = 1000
    private var lastAudioBufferTimestamp: TimeInterval = 0
    private var latencyLogCounter = 0
    private var fftProcessTimeAccumMs: Double = 0
    private var fftProcessCount: Int = 0
    private var maxBufferedSeconds: Double = 0
    private var lastUIEnqueueTime: TimeInterval = 0
    private var lastSpectrogramUIEnqueueTime: TimeInterval = 0
    private let enableVerboseLogs = false
    private let enableSpectrumDiagnostics = ProcessInfo.processInfo.environment["SPEKTO_DEBUG_SPECTRUM"] == "1"
    private let targetUIInterval: TimeInterval = 1.0 / 60.0
    private let targetSpectrogramUIInterval: TimeInterval = 1.0 / 15.0

    /// Direct high-rate subject for spectrogram renderers — does NOT trigger objectWillChange.
    let spectrogramSubject = PassthroughSubject<SpectrogramData, Never>()
    private let maxRealtimeBacklogSeconds: Double = 0.12
    private let impulseThresholdDbfs: Float = -35.0
    private let impulseCooldownSeconds: TimeInterval = 1.0
    private var lastImpulseTime: TimeInterval = 0
    private var pendingImpulseLog = false
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
    private let audioFileWriterLock = OSAllocatedUnfairLock<RealtimeAudioFileWriter?>(initialState: nil)
    private let measurementWriterLock = OSAllocatedUnfairLock<MeasurementDataWriter?>(initialState: nil)

    /// Main-thread accessor for `audioFileWriter`. All main-thread sites use this;
    /// the audio thread loads directly from `audioFileWriterLock`.
    private var audioFileWriter: RealtimeAudioFileWriter? {
        get { audioFileWriterLock.withLockUnchecked { $0 } }
        set { audioFileWriterLock.withLock { $0 = newValue } }
    }
    /// Main-thread accessor for `measurementWriter`. Audio thread loads directly from
    /// `measurementWriterLock`.
    private var measurementWriter: MeasurementDataWriter? {
        get { measurementWriterLock.withLockUnchecked { $0 } }
        set { measurementWriterLock.withLock { $0 = newValue } }
    }
    private let measurementMetricKeys: [String] = [
        "LAF", "LAS", "LCF", "LCS", "LZF", "LZS",
        "LAeq", "LAFmin", "LAFmax", "LCpeak",
        "LAFT5", "LAF5", "LAF95", "LAFTeq"
    ]
    var lastRecordingURL: URL?
    var lastMeasurementDataURL: URL?
    
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
    @Published var spectrogramTemporalSmoothing: Float = 1.0 {
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
        audioEngine = AVAudioEngine()

        // Initialize processing components
        fftProcessor = FFTProcessor(fftSize: fftSize, sampleRate: processingSampleRate)
        weightingProcessor = FrequencyWeightingProcessor(fftSize: fftSize, sampleRate: processingSampleRate)
        metricsCalculator = AcousticMetricsCalculator(sampleRate: sampleRate)
        spectrogramProcessor = SpectrogramProcessor(bandstopFilterManager: filterManager)
        // Visualisierungspfad nach Apple "Visualizing Sound as an Audio
        // Spectrogram": DCT-II auf dem gefensterten Sample-Block, Mel-
        // Filterbank mit 128 Bändern (20 Hz – 20 kHz), anschließend 20·log10.
        // Mel-Bänder sind bereits perzeptuell skaliert; der Adapter respektiert
        // `visualFrequencies` und überlagert keine zweite Log-Achse mehr.
        visualSpectrogramProcessor = VisualSpectrogramProcessor(
            transformSize: fftSize,
            sampleRate: processingSampleRate,
            windowFunction: .hann,
            melBandCount: 128,
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
    }
    
    // MARK: - Public Configuration Methods
    
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
            sampleBuffer.removeAll()
            sampleBufferOffset = 0
            fftInputBuffer.removeAll()
            fftLinearMagnitudesScratch.removeAll()
            fftDBMagnitudesScratch.removeAll()
            visualDBMagnitudesScratch.removeAll()

            // AE-7: Pre-allocate energy scratch buffers to the new FFT bin count so
            // the audio render thread never hits the lazy-allocation branch in
            // processFFTFrame. energyCount == newSize/2 (half-spectrum bin count).
            let newEnergyCount = newSize / 2
            fftEnergyScratch = [Float](repeating: 0, count: newEnergyCount)
            lcPeakScratch = [Float](repeating: 0, count: newEnergyCount)

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
            sampleBuffer.removeAll()
            sampleBufferOffset = 0
            fftInputBuffer.removeAll()
            fftLinearMagnitudesScratch.removeAll()
            fftDBMagnitudesScratch.removeAll()
            visualDBMagnitudesScratch.removeAll()

            // AE-7: Pre-allocate energy scratch buffers.
            let newEnergyCount = size.rawValue / 2
            fftEnergyScratch = [Float](repeating: 0, count: newEnergyCount)
            lcPeakScratch = [Float](repeating: 0, count: newEnergyCount)

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
        print("[AudioEngine] startAudioCapture called")
        print("[AudioEngine] Current engineStatus: \(engineStatus)")
        print("[AudioEngine] Current recording.isRecordingToFile: \(recording.isRecordingToFile)")
        if isStartingCapture || engineStatus == .starting {
            print("[AudioEngine] Capture already starting, returning early")
            return
        }
        isStartingCapture = true

        DispatchQueue.main.async {
            print("[AudioEngine] Setting engineStatus to .starting")
            self.engineStatus = .starting
            print("[AudioEngine] engineStatus is now: \(self.engineStatus)")
        }
        recordingStartTime = Date()
        recording.recordingDuration = 0.0
        hasLoggedSilence = false

        resetMetrics()

        #if targetEnvironment(simulator)
        Logger.audioEngine.info("Running on Simulator - using test audio generator")
        print("[AudioEngine] Starting test generator")
        if recording.isRecordingToFile {
            setupRecordingFile()
            setupMeasurementDataFileIfNeeded()
        }
        testGenerator.start()
        DispatchQueue.main.async {
            print("[AudioEngine] Setting engineStatus to .running")
            self.engineStatus = .running
            self.isStartingCapture = false
            print("[AudioEngine] engineStatus is now: \(self.engineStatus)")
            print("[AudioEngine] recording.isRecordingToFile: \(self.recording.isRecordingToFile)")
        }
        #else
        startRealRecording()
        #endif
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

        #if targetEnvironment(simulator)
        testGenerator.stop()
        #else
        if !isUsingDummyData {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        } else {
            testGenerator.stop()
        }
        #endif

        DispatchQueue.main.async {
            self.live.levelHistory.removeAll()
            self.live.levelHistory.reserveCapacity(self.maxHistorySize + 64)
            self.live.currentLevel = -120.0
        }

        // Reset buffer state
        sampleBuffer.removeAll()
        sampleBufferOffset = 0
        fftInputBuffer.removeAll()
    }

    private func setupRecordingFile() {
        guard recording.isRecordingToFile else { return }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("recording_\(Date().timeIntervalSince1970).caf")
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        do {
            self.audioFileWriter = try RealtimeAudioFileWriter(
                fileURL: tempURL,
                format: recordingFormat,
                settings: recordingFormat.settings,
                frameCapacity: max(tapBlockSize, 4096)
            )
            self.lastRecordingURL = tempURL
            Logger.audioEngine.info("Recording file setup at: \(tempURL.lastPathComponent)")
        } catch {
            self.audioFileWriter = nil
            self.lastRecordingURL = nil
            Logger.audioEngine.error("Recording file setup failed: \(error.localizedDescription)")
        }
    }

    private func setupMeasurementDataFileIfNeeded() {
        guard recording.isRecordingToFile, recording.isMeasurementRecording else {
            closeMeasurementWriter()
            return
        }

        if measurementWriter != nil { return }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("measurement_\(Date().timeIntervalSince1970).spekto")
        let fps = Float(processingSampleRate / Double(max(1, scrollSpeed.rawValue)))

        do {
            let writer = try MeasurementDataWriter(
                fileURL: tempURL,
                metricKeys: measurementMetricKeys,
                sampleRate: processingSampleRate,
                fps: fps,
                fftBlockSize: fftSize,
                fftBinCount: max(1, fftSize / 2)
            )
            measurementWriter = writer
            lastMeasurementDataURL = tempURL
            Logger.audioEngine.info("Measurement file setup at: \(tempURL.lastPathComponent)")
        } catch {
            measurementWriter = nil
            lastMeasurementDataURL = nil
            Logger.audioEngine.error("Measurement writer setup failed: \(error.localizedDescription)")
        }
    }

    private func closeMeasurementWriter() {
        // Atomically swap nil so the audio thread sees nil before close() runs.
        let writer = measurementWriterLock.withLock { old -> MeasurementDataWriter? in
            let w = old; old = nil; return w
        }
        guard let writer else { return }
        do {
            try writer.close()
        } catch {
            Logger.audioEngine.error("Measurement writer close failed: \(error.localizedDescription)")
        }
    }

    private func closeAudioFileWriter() {
        // Atomically swap nil into the lock so the audio thread sees nil immediately,
        // then call close() outside the lock (close() may block briefly).
        let writer = audioFileWriterLock.withLock { old -> RealtimeAudioFileWriter? in
            let w = old; old = nil; return w
        }
        writer?.close()
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
        let audioSession = AVAudioSession.sharedInstance()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try audioSession.setCategory(.record, mode: .measurement, options: [])
                try audioSession.setPreferredIOBufferDuration(Double(self.tapBlockSize) / self.sampleRate)
                try audioSession.setActive(true)
            } catch {
                Logger.audioEngine.warning("Prewarm failed: \(error.localizedDescription)")
            }
        }
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
        let blockSize = self.tapBlockSize
        let rate = self.sampleRate
        let stereoMode = self.selectedStereoMode

        // Move blocking audio session setup to background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                // Configure audio session (blocking operations)
                try audioSession.setCategory(.record, mode: .measurement, options: [])
                try audioSession.setPreferredIOBufferDuration(Double(blockSize) / rate)

                if audioSession.isInputGainSettable {
                    try audioSession.setInputGain(1.0)
                }

                try audioSession.setActive(true)

                // Configure microphone input
                var dataSources: [AVAudioSessionDataSourceDescription] = []
                if let inputs = audioSession.availableInputs,
                   let builtInMic = inputs.first(where: { $0.portType == .builtInMic }) {
                    try audioSession.setPreferredInput(builtInMic)
                    dataSources = builtInMic.dataSources ?? []

                    // Apply stereo polar pattern BEFORE reading inputNode.outputFormat.
                    // The format is only 2-channel if the pattern is set beforehand.
                    let targetOrientation: AVAudioSession.Orientation
                    switch stereoMode {
                    case .frontBottom: targetOrientation = .front
                    case .bottomBack:  targetOrientation = .back
                    case .frontBack:   targetOrientation = .bottom
                    }
                    if let stereoSource = dataSources.first(where: { $0.orientation == targetOrientation }),
                       stereoSource.supportedPolarPatterns?.contains(.stereo) == true {
                        try stereoSource.setPreferredPolarPattern(.stereo)
                        try audioSession.setInputDataSource(stereoSource)
                        Logger.audioEngine.info("Stereo mic configured: orientation=\(String(describing: targetOrientation))")
                    } else if let source = selectedSource {
                        // Fallback: use the previously selected source
                        try audioSession.setInputDataSource(source)
                    }
                }

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
        // Update calibration based on current audio session settings
        updateCalibration()

        // Update available data sources
        self.availableDataSources = dataSources
        if self.selectedDataSource == nil {
            self.selectedDataSource = audioSession.inputDataSource ?? dataSources.first
        }

        do {
            // Setup audio engine
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

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
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("recording_\(Date().timeIntervalSince1970).caf")
                do {
                    self.audioFileWriter = try RealtimeAudioFileWriter(
                        fileURL: tempURL,
                        format: recordingFormat,
                        settings: recordingFormat.settings,
                        frameCapacity: max(tapBlockSize, 4096)
                    )
                    self.lastRecordingURL = tempURL
                    Logger.audioEngine.info("Recording to file: \(tempURL.lastPathComponent)")
                } catch {
                    self.audioFileWriter = nil
                    self.lastRecordingURL = nil
                    Logger.audioEngine.error("Recording file setup failed: \(error.localizedDescription)")
                }
                setupMeasurementDataFileIfNeeded()
            } else {
                closeAudioFileWriter()
                closeMeasurementWriter()
                Logger.audioEngine.info("Live mode - no file recording")
            }

            // Install audio tap
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: tapBlockSize, format: recordingFormat) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer)
            }

            try audioEngine.start()
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
        let octaveBandsZ = computeDisplayThirdOctaveBands(frequencies: data.frequencies, magnitudes: data.magnitudes)
        let octaveBandsA = data.magnitudesA.map { computeDisplayThirdOctaveBands(frequencies: data.frequencies, magnitudes: $0) } ?? octaveBandsZ
        let octaveBandsC = data.magnitudesC.map { computeDisplayThirdOctaveBands(frequencies: data.frequencies, magnitudes: $0) } ?? octaveBandsZ

        DispatchQueue.main.async {
            if let startTime = self.recordingStartTime {
                self.recording.recordingDuration = Date().timeIntervalSince(startTime)
            }

            self.live.currentSpectrogramData = data
            self.live.currentOctaveBandsZ = octaveBandsZ
            self.live.currentOctaveBandsA = octaveBandsA
            self.live.currentOctaveBandsC = octaveBandsC
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
           let writer = audioFileWriterLock.withLockUnchecked({ $0 }) {
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
        
        // Impulse detection (measure end-to-end latency)
        let now = CFAbsoluteTimeGetCurrent()
        if signalDBFS > impulseThresholdDbfs && (now - lastImpulseTime) > impulseCooldownSeconds {
            lastImpulseTime = now
            pendingImpulseLog = true
        }
        

        if signalDBFS < -120 && !hasLoggedSilence {
            Logger.audioEngine.warning("Audio buffer silent/empty: \(signalDBFS, format: .fixed(precision: 1)) dBFS")
            hasLoggedSilence = true
        }
        
        // Append + downstream sampleBuffer/sampleBufferOffset mutations are
        // serialised against `applyFFTConfiguration` / `setBlockSize` /
        // `setWindowFunction` (which also reset the buffer under
        // `processingLock` on main). Without this guard a reconfigure
        // during a tap callback races on Swift array storage. Lock width is
        // kept to the array operations themselves; downstream FFT work
        // already takes its own snapshots.
        processingLock.withLockUnchecked {
            sampleBuffer.append(contentsOf: newSamples)
        }

        // Lese aktuelle FFT-Größe thread-sicher.
        let currentFFTSize = processingLock.withLockUnchecked { fftSize }

        // Backlog (wie viel Audio noch in der Queue steckt)
        let bufferedSamples = processingLock.withLockUnchecked {
            max(0, sampleBuffer.count - sampleBufferOffset)
        }
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
                    sampleBufferOffset += samplesToDrop
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
            if sampleBufferOffset > absoluteCompactionThreshold {
                sampleBuffer.removeFirst(sampleBufferOffset)
                sampleBufferOffset = 0
            }
        }

        // Process when we have enough samples (using offset for O(1) instead of O(n) removeFirst).
        // Lock spans the read+copy+offset advance; processFFTFrame runs outside
        // the lock so we don't hold it across FFT/weighting work.
        while true {
            let frameReady: Bool = processingLock.withLockUnchecked {
                guard sampleBuffer.count - sampleBufferOffset >= currentFFTSize else { return false }
                if fftInputBuffer.count != currentFFTSize {
                    fftInputBuffer = [Float](repeating: 0, count: currentFFTSize)
                }
                sampleBuffer.withUnsafeBufferPointer { source in
                    fftInputBuffer.withUnsafeMutableBufferPointer { target in
                        guard let sourceBase = source.baseAddress, let targetBase = target.baseAddress else { return }
                        memcpy(
                            targetBase,
                            sourceBase.advanced(by: sampleBufferOffset),
                            currentFFTSize * MemoryLayout<Float>.stride
                        )
                    }
                }
                sampleBufferOffset += hop
                if sampleBufferOffset > currentFFTSize * 2 {
                    sampleBuffer.removeFirst(sampleBufferOffset)
                    sampleBufferOffset = 0
                }
                return true
            }
            if !frameReady { break }

            let t0 = CFAbsoluteTimeGetCurrent()
            processFFTFrame(samples: fftInputBuffer, peakLevel: peakDB)
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

        // Perform FFT into reusable buffers to avoid per-frame result arrays.
        localFFTProcessor.performFFT(on: samples, gainBoost: gainBoost, into: &fftLinearMagnitudesScratch)
        localFFTProcessor.convertToDB(fftLinearMagnitudesScratch, into: &fftDBMagnitudesScratch)
        // DCT/Mel pipeline removed from the real-time audio thread (M19 regression):
        // cblas_sgemv(128×1024) at 86 Hz was causing audio-thread overrun and a
        // blurry mel-scale display. The spectrogram now uses the FFT path exclusively.
        let visualFrequencies: [Float]? = nil
        
        // AE-5: Logger calls are not real-time safe (acquire internal locks, may
        // malloc on first category call). Periodic FFT-range logging removed from
        // the audio render thread. Use os_signpost or Instruments if spectrum
        // diagnostics are needed.

        // Convert to dB for Spectrogram (dBFS → dB SPL mit Kalibrierung)
        var calOffset = cal
        vDSP_vsadd(fftDBMagnitudesScratch, 1, &calOffset, &fftDBMagnitudesScratch, 1, vDSP_Length(fftDBMagnitudesScratch.count))

        // Gate A/C spectral tracks to data consumers that actually need them.
        // Z is always available; A/C are emitted only for the selected global
        // weighting, active widget overrides, or measurement recording.
        let requiredSpectralWeightings = requiredSpectralWeightingsForCurrentFrame()
        let dbZ = fftDBMagnitudesScratch
        let needsA = requiredSpectralWeightings.contains(.a)
        let needsC = requiredSpectralWeightings.contains(.c)

        let dbA = needsA ? localWeightingProcessor.applyWeighting(
            to: fftDBMagnitudesScratch, frequencies: localFFTProcessor.frequencies, weighting: .a) : nil
        let dbC = needsC ? localWeightingProcessor.applyWeighting(
            to: fftDBMagnitudesScratch, frequencies: localFFTProcessor.frequencies, weighting: .c) : nil

        // Spectrogram Processing (Filtering, Octaves, Binning, Smoothing)
        let processedZ = spectrogramProcessor.process(
            frequencies: localFFTProcessor.frequencies,
            dbMagnitudes: dbZ,
            sampleRate: processingSampleRate,
            smoothingTrack: .z
        )
        let processedA = dbA.map {
            spectrogramProcessor.process(
                frequencies: localFFTProcessor.frequencies,
                dbMagnitudes: $0,
                sampleRate: processingSampleRate,
                smoothingTrack: .a
            )
        }
        let processedC = dbC.map {
            spectrogramProcessor.process(
                frequencies: localFFTProcessor.frequencies,
                dbMagnitudes: $0,
                sampleRate: processingSampleRate,
                smoothingTrack: .c
            )
        }

        // Use selected weighting for octave bands and spectrum
        let processed: SpectrogramProcessor.Result
        switch frequencyWeighting {
        case .a: processed = processedA ?? processedZ
        case .c: processed = processedC ?? processedZ
        case .z: processed = processedZ
        }

        let displayOctaveBandsZ = computeDisplayThirdOctaveBands(
            frequencies: processedZ.bandFrequencies,
            magnitudes: processedZ.bandMagnitudes
        )
        let displayOctaveBandsA = processedA.map {
            computeDisplayThirdOctaveBands(
                frequencies: $0.bandFrequencies,
                magnitudes: $0.bandMagnitudes
            )
        } ?? Self.emptyThirdOctaveBands
        let displayOctaveBandsC = processedC.map {
            computeDisplayThirdOctaveBands(
                frequencies: $0.bandFrequencies,
                magnitudes: $0.bandMagnitudes
            )
        } ?? Self.emptyThirdOctaveBands

        // Bark band aggregation — only when a widget requests it (zero-cost otherwise).
        // Uses the same binned band data as third-octave so no extra FFT pass is needed.
        let needsBark = widgetBarkBandsRequiredLock.withLockUnchecked { $0 }
        let displayBarkBandsZ: [Float]
        let displayBarkBandsA: [Float]
        let displayBarkBandsC: [Float]
        if needsBark {
            displayBarkBandsZ = SpectrumBandAggregator.barkBands(
                frequencies: processedZ.bandFrequencies,
                spectrum: processedZ.bandMagnitudes
            )
            displayBarkBandsA = processedA.map {
                SpectrumBandAggregator.barkBands(frequencies: $0.bandFrequencies, spectrum: $0.bandMagnitudes)
            } ?? []
            displayBarkBandsC = processedC.map {
                SpectrumBandAggregator.barkBands(frequencies: $0.bandFrequencies, spectrum: $0.bandMagnitudes)
            } ?? []
        } else {
            displayBarkBandsZ = []
            displayBarkBandsA = []
            displayBarkBandsC = []
        }

        // Calculate energies for acoustic metrics using vectorized Accelerate ops
        let calibrationFactor = pow(10.0, cal / 10.0)
        let energyCount = min(fftLinearMagnitudesScratch.count,
                              min(localWeightingProcessor.aWeightingGainsSq.count,
                                  localWeightingProcessor.cWeightingGainsSq.count))
        if fftEnergyScratch.count != energyCount {
            fftEnergyScratch = [Float](repeating: 0, count: energyCount)
            lcPeakScratch = [Float](repeating: 0, count: energyCount)
        }
        vDSP_vsq(fftLinearMagnitudesScratch, 1, &fftEnergyScratch, 1, vDSP_Length(energyCount))

        var energyZ: Float = 0.0
        var energyA: Float = 0.0
        var energyC: Float = 0.0
        vDSP_sve(fftEnergyScratch, 1, &energyZ, vDSP_Length(energyCount))
        vDSP_dotpr(fftEnergyScratch, 1, localWeightingProcessor.aWeightingGainsSq, 1, &energyA, vDSP_Length(energyCount))
        vDSP_dotpr(fftEnergyScratch, 1, localWeightingProcessor.cWeightingGainsSq, 1, &energyC, vDSP_Length(energyCount))

        energyZ *= calibrationFactor
        energyA *= calibrationFactor
        energyC *= calibrationFactor

        // --- LCpeak (IEC 61672) ---
        // LCpeak must be derived from the C-weighted signal, not from the raw
        // broadband sample peak. We approximate the instantaneous peak of the
        // C-weighted signal by finding the maximum per-bin C-weighted amplitude
        // across the FFT frame and converting that to dB SPL.
        //
        // C-weighted amplitude for bin i = fftLinearMagnitudesScratch[i] * cGain[i]
        // (amplitude-domain multiply; cGains are amplitude-domain linear factors).
        //
        // This is Approach A from the task spec (frequency-domain peak detector),
        // chosen because cWeightingGains are already precomputed in the weighting
        // processor and no IFFT or separate time-domain filter pass is required.
        let cGains = localWeightingProcessor.getWeightingGains(for: .c)
        let lcPeakCount = min(fftLinearMagnitudesScratch.count, cGains.count)
        if lcPeakScratch.count != lcPeakCount {
            lcPeakScratch = [Float](repeating: 0, count: lcPeakCount)
        }
        vDSP_vmul(fftLinearMagnitudesScratch, 1, cGains, 1, &lcPeakScratch, 1, vDSP_Length(lcPeakCount))
        var cPeakLinear: Float = 0.0
        vDSP_maxv(lcPeakScratch, 1, &cPeakLinear, vDSP_Length(lcPeakCount))
        // 20·log10 (amplitude domain) → dBFS, then add calibration → dB SPL
        let lcPeak = 20.0 * log10(cPeakLinear + 1e-9) + cal

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
            energyZ: energyZ,
            energyA: energyA,
            energyC: energyC,
            peakLevel: lcPeak,
            dt: dt,
            recordingDuration: audioThreadRecordingDuration,
            frequencies: localFFTProcessor.frequencies,
            magnitudes: fftDBMagnitudesScratch,
            bandsZ: displayOctaveBandsZ,
            bandsA: processedA != nil ? displayOctaveBandsA : [],
            bandsC: processedC != nil ? displayOctaveBandsC : []
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
            if let writer = measurementWriterLock.withLockUnchecked({ $0 }) {
                let timestampSeconds: Float
                if let startTime = recordingStartTime {
                    timestampSeconds = Float(Date().timeIntervalSince(startTime))
                } else {
                    timestampSeconds = Float(recording.recordingDuration)
                }
                let metricValues = measurementMetricKeys.map { levels[$0] ?? -120.0 }
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
            binnedFrequencies: processedZ.bandFrequencies,
            binnedMagnitudes: processedZ.bandMagnitudes
        )
        
        // Create spectrogram data with all weightings
        let spectrogramData = SpectrogramData(
            frequencies: processedZ.bandFrequencies,
            magnitudes: processedZ.bandMagnitudes,      // Z-weighted (linear)
            magnitudesA: processedA?.bandMagnitudes,    // A-weighted when requested
            magnitudesC: processedC?.bandMagnitudes,    // C-weighted when requested
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
        if processEndTime - lastUIEnqueueTime < targetUIInterval {
            return
        }
        lastUIEnqueueTime = processEndTime

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

            if self.pendingImpulseLog {
                let peakDbfs = peakLevel - self.calibrationOffset
                if peakDbfs > self.impulseThresholdDbfs {
                    let dtMs = (CFAbsoluteTimeGetCurrent() - self.lastImpulseTime) * 1000.0
                    let impulseLine = String(format: "[Impulse] end-to-end %.0f ms (threshold %.0f dBFS)", dtMs, self.impulseThresholdDbfs)
                    print(impulseLine)
                    self.pendingImpulseLog = false
                }
            }

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
            let nowMain = CFAbsoluteTimeGetCurrent()
            if nowMain - self.lastSpectrogramUIEnqueueTime >= self.targetSpectrogramUIInterval {
                self.lastSpectrogramUIEnqueueTime = nowMain
                self.live.currentSpectrogramData = spectrogramData
            }
            self.live.currentOctaveBandsZ = octaveBandsZ
            self.live.currentOctaveBandsA = octaveBandsA
            self.live.currentOctaveBandsC = octaveBandsC
            if !bandLeqZ.isEmpty { self.live.bandLeqZ = bandLeqZ }
            if !bandLeqA.isEmpty { self.live.bandLeqA = bandLeqA }
            if !bandLeqC.isEmpty { self.live.bandLeqC = bandLeqC }
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
            let now = Date().timeIntervalSince1970
            if now - self.lastWatchUpdate > 0.1 {
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
                self.lastWatchUpdate = now
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

    private func updateProcessingSampleRateIfNeeded(_ newSampleRate: Double, source: String) {
        guard newSampleRate > 1000 else { return }
        let normalized = (newSampleRate * 10).rounded() / 10
        guard abs(normalized - processingSampleRate) > 1.0 else { return }

        processingLock.withLockUnchecked {
            processingSampleRate = normalized
            sampleBuffer.removeAll()
            sampleBufferOffset = 0
            fftInputBuffer.removeAll()

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
