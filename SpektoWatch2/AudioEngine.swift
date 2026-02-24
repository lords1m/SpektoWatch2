import Foundation
import AVFoundation
import Accelerate
import Combine
import os.signpost
#if canImport(UIKit)
import UIKit
#endif

enum ScrollSpeed: Int, CaseIterable {
    case verySlow = 4096  // ~10 FPS
    case slow = 2048      // ~21 FPS
    case normal = 1024    // ~43 FPS
    case fast = 512       // ~86 FPS
    
    var label: String {
        switch self {
        case .verySlow: return "Sehr Langsam"
        case .slow: return "Langsam"
        case .normal: return "Normal"
        case .fast: return "Schnell"
        }
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
    
    // MARK: - Processing Components

    private var fftProcessor: FFTProcessor
    private var weightingProcessor: FrequencyWeightingProcessor
    private let metricsCalculator: AcousticMetricsCalculator
    private let spectrogramProcessor: SpectrogramProcessor
    private let testGenerator: TestAudioGenerator
    private let bandstopFilterManager: BandstopFilterManager
    private let connectivityManager: WatchConnectivityManager

    // MARK: - Audio Engine

    private var audioEngine: AVAudioEngine
    private var fftSize: Int = 8192
    private let tapBlockSize: AVAudioFrameCount = 512
    private let sampleRate: Double = 44100.0

    // MARK: - FFT Configuration

    /// Aktuelle Fensterfunktion
    @Published var currentWindowFunction: WindowFunction = .hann
    /// Aktuelle Blockgröße
    @Published var currentBlockSize: FFTBlockSize = .size8192
    
    // MARK: - Buffer Management

    private var sampleBuffer: [Float] = []
    private var sampleBufferOffset: Int = 0  // Index-basierter Ansatz für O(1) "removeFirst"
    private var gainBoost: Float = 10.0

    // Lock für Thread-sichere FFT-Rekonfiguration
    private let processingLock = NSLock()

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
    private let enableVerboseLogs = false
    private let targetUIInterval: TimeInterval = 1.0 / 60.0
    private let maxRealtimeBacklogSeconds: Double = 0.12
    private let impulseThresholdDbfs: Float = -35.0
    private let impulseCooldownSeconds: TimeInterval = 1.0
    private var lastImpulseTime: TimeInterval = 0
    private var pendingImpulseLog = false

    // MARK: - Microphone Calibration
    // Basierend auf Studio Six Digital AudioTools Kalibrierungsdaten
    // Default iOS Mic Calibration: +7.0 dB (relativ zu 94 dB SPL Referenz)
    // dB SPL = dBFS + calibrationOffset
    @Published var calibrationOffset: Float = 94.0 {
        didSet {
            UserDefaults.standard.set(calibrationOffset, forKey: "calibrationOffset")
        }
    }
    private var currentInputGain: Float = 1.0

    // Gerätespezifische Kalibrierungswerte (Offset in dB)
    // Diese Werte basieren auf typischen Messungen und können manuell angepasst werden
    // Quelle: Studio Six Digital, Faber Acoustical
    private static let deviceCalibrationOffsets: [String: Float] = [
        // iPhone 12 Serie - empfindlichere Mikrofone
        "iPhone13,1": 91.0,  // iPhone 12 mini
        "iPhone13,2": 92.0,  // iPhone 12
        "iPhone13,3": 92.0,  // iPhone 12 Pro
        "iPhone13,4": 92.0,  // iPhone 12 Pro Max

        // iPhone 13 Serie
        "iPhone14,4": 91.0,  // iPhone 13 mini
        "iPhone14,5": 92.0,  // iPhone 13
        "iPhone14,2": 92.0,  // iPhone 13 Pro
        "iPhone14,3": 92.0,  // iPhone 13 Pro Max

        // iPhone 14 Serie
        "iPhone14,7": 92.0,  // iPhone 14
        "iPhone14,8": 92.0,  // iPhone 14 Plus
        "iPhone15,2": 93.0,  // iPhone 14 Pro
        "iPhone15,3": 93.0,  // iPhone 14 Pro Max

        // iPhone 15 Serie
        "iPhone15,4": 93.0,  // iPhone 15
        "iPhone15,5": 93.0,  // iPhone 15 Plus
        "iPhone16,1": 94.0,  // iPhone 15 Pro
        "iPhone16,2": 94.0,  // iPhone 15 Pro Max

        // iPhone 11 Serie
        "iPhone12,1": 94.0,  // iPhone 11
        "iPhone12,3": 94.0,  // iPhone 11 Pro
        "iPhone12,5": 94.0,  // iPhone 11 Pro Max

        // Ältere iPhones
        "iPhone11,2": 95.0,  // iPhone XS
        "iPhone11,4": 95.0,  // iPhone XS Max
        "iPhone11,6": 95.0,  // iPhone XS Max (China)
        "iPhone11,8": 95.0,  // iPhone XR
        "iPhone10,1": 96.0,  // iPhone 8
        "iPhone10,4": 96.0,  // iPhone 8
        "iPhone10,2": 96.0,  // iPhone 8 Plus
        "iPhone10,5": 96.0,  // iPhone 8 Plus
    ]

    /// Ermittelt das Gerätemodell (z.B. "iPhone13,1" für iPhone 12 mini)
    static func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    /// Gibt den empfohlenen Kalibrierungsoffset für das aktuelle Gerät zurück
    static func getRecommendedCalibrationOffset() -> Float {
        let model = getDeviceModel()
        Logger.audioEngine.info("Detected device model: \(model)")
        return deviceCalibrationOffsets[model] ?? 94.0  // Default: 94 dB
    }
    
    // MARK: - Recording
    
    private var recordingStartTime: Date?
    private var audioFile: AVAudioFile?
    var lastRecordingURL: URL?
    
    // MARK: - Published Properties

    /// Gibt an, ob Audio in eine Datei geschrieben wird (true) oder nur Live-Anzeige (false)
    @Published var isRecordingToFile: Bool = false
    @Published var recordingDuration: TimeInterval = 0.0
    @Published var engineStatus: EngineStatus = .idle
    @Published var lastError: SpektoWatchError?
    @Published var currentSpectrogramData: SpectrogramData?
    @Published var currentLevel: Float = -120.0
    @Published var maxLevel: Float = -120.0
    @Published var minLevel: Float = -120.0
    @Published var levelHistory: [Float] = []
    @Published var currentPeakLevel: Float = -120.0
    @Published var currentStereoPhase: Float = 1.0
    @Published var currentOctaveBands: [Float] = Array(repeating: -120.0, count: 31)
    @Published var currentSpectrum: [Float] = []
    
    @Published var timeWeighting: TimeWeighting = .fast {
        didSet {
            spectrogramProcessor.temporalSmoothingFactor = (timeWeighting == .fast) ? 0.5 : 0.9
        }
    }
    @Published var frequencyWeighting: FrequencyWeighting = .a
    @Published var scrollSpeed: ScrollSpeed = .fast
    
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
        fftProcessor = FFTProcessor(fftSize: fftSize, sampleRate: sampleRate)
        weightingProcessor = FrequencyWeightingProcessor(fftSize: fftSize, sampleRate: sampleRate)
        metricsCalculator = AcousticMetricsCalculator(sampleRate: sampleRate)
        spectrogramProcessor = SpectrogramProcessor(bandstopFilterManager: filterManager)
        testGenerator = TestAudioGenerator(sampleRate: sampleRate)
        
        // Setup test generator callback
        testGenerator.onDataGenerated = { [weak self] samples in
            self?.processSamples(samples)
        }

        // Load saved calibration offset or use device-specific default
        // Version 2: Gerätespezifische Kalibrierung
        let calibrationVersion = UserDefaults.standard.integer(forKey: "calibrationVersion")
        if calibrationVersion >= 2, let savedOffset = UserDefaults.standard.object(forKey: "calibrationOffset") as? Float {
            calibrationOffset = savedOffset
            Logger.audioEngine.info("Loaded saved calibration offset: \(self.calibrationOffset) dB")
        } else {
            // Verwende gerätespezifischen Kalibrierungswert (neu oder nach Update)
            calibrationOffset = AudioEngine.getRecommendedCalibrationOffset()
            UserDefaults.standard.set(2, forKey: "calibrationVersion")
            Logger.audioEngine.info("Using device-specific calibration offset: \(self.calibrationOffset) dB for \(AudioEngine.getDeviceModel())")
        }
    }
    
    // MARK: - Public Configuration Methods
    
    func setTimeWeighting(_ weighting: TimeWeighting) {
        timeWeighting = weighting
    }
    
    func setFrequencyWeighting(_ weighting: FrequencyWeighting) {
        frequencyWeighting = weighting
    }
    
    func setGainBoost(_ gain: Float) {
        gainBoost = gain
    }

    // MARK: - FFT Configuration

    /// Wendet eine FFTConfiguration an
    func applyFFTConfiguration(_ config: FFTConfiguration) {
        let newSize = config.blockSize.rawValue
        let newWindow = config.windowFunction

        // Prüfe ob Änderungen nötig sind
        guard newSize != fftSize || newWindow != currentWindowFunction else { return }

        Logger.audioEngine.info("Applying FFT config: \(newWindow.rawValue), \(newSize) samples")

        // Thread-sichere Rekonfiguration
        processingLock.lock()

        // Buffer leeren um Race-Conditions zu vermeiden
        sampleBuffer.removeAll()
        sampleBufferOffset = 0

        // Aktualisiere interne Werte
        fftSize = newSize
        currentWindowFunction = newWindow
        currentBlockSize = config.blockSize

        // Rekonfiguriere den FFT Processor
        fftProcessor.reconfigure(fftSize: newSize, windowFunction: newWindow)

        // Erstelle neuen Weighting Processor (alter wird nach unlock freigegeben)
        let newWeightingProcessor = FrequencyWeightingProcessor(fftSize: newSize, sampleRate: sampleRate)
        weightingProcessor = newWeightingProcessor

        processingLock.unlock()

        // Veröffentliche Änderungen
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    /// Setzt nur die Fensterfunktion
    func setWindowFunction(_ function: WindowFunction) {
        guard function != currentWindowFunction else { return }

        processingLock.lock()
        defer { processingLock.unlock() }

        currentWindowFunction = function
        fftProcessor.setWindowFunction(function)
        Logger.audioEngine.info("Window function changed to: \(function.rawValue)")
    }

    /// Setzt nur die Blockgröße
    func setBlockSize(_ size: FFTBlockSize) {
        guard size.rawValue != fftSize else { return }

        processingLock.lock()

        // Buffer leeren um Race-Conditions zu vermeiden
        sampleBuffer.removeAll()
        sampleBufferOffset = 0

        fftSize = size.rawValue
        currentBlockSize = size
        fftProcessor.reconfigure(fftSize: size.rawValue, windowFunction: currentWindowFunction)

        // Erstelle neuen Weighting Processor
        let newWeightingProcessor = FrequencyWeightingProcessor(fftSize: size.rawValue, sampleRate: sampleRate)
        weightingProcessor = newWeightingProcessor

        processingLock.unlock()

        Logger.audioEngine.info("FFT size changed to: \(size.rawValue)")
    }

    /// Gibt die aktuelle Frequenzauflösung zurück
    var frequencyResolution: Float {
        return Float(sampleRate) / Float(fftSize)
    }

    /// Gibt die aktuelle Zeitauflösung in ms zurück
    var timeResolutionMs: Float {
        return Float(fftSize) / Float(sampleRate) * 1000.0
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
        isRecordingToFile = false
        print("[AudioEngine] Set isRecordingToFile = false")
        startAudioCapture()
    }

    /// Startet die Aufnahme (mit Speicherung in Datei)
    func startRecording() {
        print("[AudioEngine] startRecording called")
        print("[AudioEngine] Current engineStatus: \(engineStatus)")
        print("[AudioEngine] Current isRecordingToFile: \(isRecordingToFile)")

        if engineStatus == .starting {
            print("[AudioEngine] Engine is starting, ignoring startRecording")
            return
        }

        guard engineStatus != .running else {
            // Wenn bereits im Live-Modus, nur auf Aufnahme umschalten
            if !isRecordingToFile {
                Logger.audioEngine.info("Switching from LIVE to RECORDING mode")
                isRecordingToFile = true
                print("[AudioEngine] Set isRecordingToFile = true (switching from live)")
                recordingStartTime = Date()
                recordingDuration = 0.0
                resetMetrics()
                setupRecordingFile()
            }
            return
        }
        Logger.audioEngine.info("Starting AudioEngine in RECORDING mode")
        isRecordingToFile = true
        print("[AudioEngine] Set isRecordingToFile = true")
        startAudioCapture()
    }

    private func startAudioCapture() {
        print("[AudioEngine] startAudioCapture called")
        print("[AudioEngine] Current engineStatus: \(engineStatus)")
        print("[AudioEngine] Current isRecordingToFile: \(isRecordingToFile)")
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
        recordingDuration = 0.0
        hasLoggedSilence = false

        resetMetrics()

        #if targetEnvironment(simulator)
        Logger.audioEngine.info("Running on Simulator - using test audio generator")
        print("[AudioEngine] Starting test generator")
        testGenerator.start()
        DispatchQueue.main.async {
            print("[AudioEngine] Setting engineStatus to .running")
            self.engineStatus = .running
            self.isStartingCapture = false
            print("[AudioEngine] engineStatus is now: \(self.engineStatus)")
            print("[AudioEngine] isRecordingToFile: \(self.isRecordingToFile)")
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
        print("[AudioEngine] Current isRecordingToFile: \(isRecordingToFile)")
        Logger.audioEngine.info("Stopping AudioEngine recording")
        isRecordingToFile = false
        print("[AudioEngine] Set isRecordingToFile = false")
        stopAudioCapture()
    }

    private func stopAudioCapture() {
        print("[AudioEngine] stopAudioCapture called")
        print("[AudioEngine] Current engineStatus: \(engineStatus)")

        recordingStartTime = nil
        audioFile = nil
        DispatchQueue.main.async {
            print("[AudioEngine] Setting engineStatus to .idle")
            self.engineStatus = .idle
            print("[AudioEngine] Setting isRecordingToFile to false")
            self.isRecordingToFile = false
            self.isStartingCapture = false
            print("[AudioEngine] engineStatus is now: \(self.engineStatus)")
            print("[AudioEngine] isRecordingToFile is now: \(self.isRecordingToFile)")
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
            self.levelHistory.removeAll()
            self.currentLevel = -120.0
        }

        // Reset buffer state
        sampleBuffer.removeAll()
        sampleBufferOffset = 0
    }

    private func setupRecordingFile() {
        guard isRecordingToFile else { return }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("recording_\(Date().timeIntervalSince1970).caf")
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        self.audioFile = try? AVAudioFile(forWriting: tempURL, settings: recordingFormat.settings)
        self.lastRecordingURL = tempURL
        Logger.audioEngine.info("Recording file setup at: \(tempURL.lastPathComponent)")
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
    
    func processExternalAudio(_ samples: [Float]) {
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
        let recommendedOffset = AudioEngine.getRecommendedCalibrationOffset()
        calibrationOffset = recommendedOffset
        Logger.audioEngine.info("Calibration reset to device default: \(recommendedOffset) dB")
    }

    /// Gibt den aktuellen Kalibrierungs-Offset zurück
    func getCalibrationOffset() -> Float {
        return calibrationOffset
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
                    if granted { DispatchQueue.main.async { self?.startRecording() } }
                }
                return
            }
            if permission == .denied {
                Logger.audioEngine.error("Microphone permission denied")
                DispatchQueue.main.async {
                    self.engineStatus = .error("Microphone permission denied")
                }
                return
            }
        } else {
            if audioSession.recordPermission == .undetermined {
                audioSession.requestRecordPermission { [weak self] granted in
                    if granted { DispatchQueue.main.async { self?.startRecording() } }
                }
                return
            }
            if audioSession.recordPermission == .denied {
                Logger.audioEngine.error("Microphone permission denied")
                DispatchQueue.main.async {
                    self.engineStatus = .error("Microphone permission denied")
                }
                return
            }
        }
        #else
        if audioSession.recordPermission == .undetermined {
            audioSession.requestRecordPermission { [weak self] granted in
                if granted { DispatchQueue.main.async { self?.startRecording() } }
            }
            return
        }
        if audioSession.recordPermission == .denied {
            Logger.audioEngine.error("Microphone permission denied")
            DispatchQueue.main.async {
                self.engineStatus = .error("Microphone permission denied")
            }
            return
        }
        #endif

        // Capture state needed for background work
        let isRecording = self.isRecordingToFile
        let selectedSource = self.selectedDataSource
        let blockSize = self.tapBlockSize
        let rate = self.sampleRate

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

                    if let source = selectedSource {
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

            // Setup recording file only if recording to file
            if isRecording {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("recording_\(Date().timeIntervalSince1970).caf")
                self.audioFile = try? AVAudioFile(forWriting: tempURL, settings: recordingFormat.settings)
                self.lastRecordingURL = tempURL
                Logger.audioEngine.info("Recording to file: \(tempURL.lastPathComponent)")
            } else {
                self.audioFile = nil
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
            self.levelHistory.removeAll()
            self.currentLevel = -120.0
            self.maxLevel = -120.0
            self.minLevel = 0.0
        }
    }
    
    // MARK: - Audio Processing
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let signpostID = OSSignpostID(log: Self.performanceLog)
        os_signpost(.begin, log: Self.performanceLog, name: "AudioTapCallback", signpostID: signpostID)
        defer { os_signpost(.end, log: Self.performanceLog, name: "AudioTapCallback", signpostID: signpostID) }

        lastAudioBufferTimestamp = CFAbsoluteTimeGetCurrent()
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        
        // Write to file only if recording to file mode is active
        if isRecordingToFile, let audioFile = audioFile {
            try? audioFile.write(from: buffer)
        }
        
        // Extract samples and calculate stereo phase
        let channels = Int(buffer.format.channelCount)
        let newSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        
        var phase: Float = 1.0
        if channels > 1 {
            var dotProd: Float = 0
            var sumSqL: Float = 0
            var sumSqR: Float = 0
            vDSP_dotpr(newSamples, 1, channelData[1], 1, &dotProd, vDSP_Length(frameCount))
            vDSP_svesq(newSamples, 1, &sumSqL, vDSP_Length(frameCount))
            vDSP_svesq(channelData[1], 1, &sumSqR, vDSP_Length(frameCount))
            phase = dotProd / (sqrt(sumSqL * sumSqR) + 1e-9)
        }
        
        processSamples(newSamples)
        
        if channels > 1 {
            DispatchQueue.main.async {
                self.currentStereoPhase = phase
            }
        }
    }
    
    private func processSamples(_ newSamples: [Float]) {
        // Calculate peak level (dBFS → dB SPL mit Kalibrierung)
        var rms: Float = 0
        vDSP_rmsqv(newSamples, 1, &rms, vDSP_Length(newSamples.count))
        let signalDBFS = 20 * log10(rms + 1e-9)
        let signalDB = signalDBFS + calibrationOffset  // Konvertiere zu dB SPL
        let peakVal = newSamples.max() ?? 0
        let peakDBFS = 20 * log10(abs(peakVal) + 1e-9)
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
        
        // Add to sample buffer
        sampleBuffer.append(contentsOf: newSamples)

        // Lese aktuelle FFT-Größe thread-sicher
        processingLock.lock()
        let currentFFTSize = fftSize
        processingLock.unlock()

        // Backlog (wie viel Audio noch in der Queue steckt)
        let bufferedSamples = max(0, sampleBuffer.count - sampleBufferOffset)
        let bufferedSeconds = Double(bufferedSamples) / sampleRate
        if bufferedSeconds > maxBufferedSeconds {
            maxBufferedSeconds = bufferedSeconds
        }
        // Keep the visualization near real-time: if processing falls behind,
        // drop oldest queued samples instead of rendering stale history.
        // Never trim below one full FFT window (+ one hop), otherwise no frames can be processed.
        let minRequiredBufferedSeconds = Double(currentFFTSize + max(1, scrollSpeed.rawValue)) / sampleRate
        let effectiveBacklogLimitSeconds = max(maxRealtimeBacklogSeconds, minRequiredBufferedSeconds)
        if bufferedSeconds > effectiveBacklogLimitSeconds {
            let targetBufferedSamples = Int(effectiveBacklogLimitSeconds * sampleRate)
            var samplesToDrop = bufferedSamples - targetBufferedSamples
            if samplesToDrop > 0 {
                let hop = max(1, scrollSpeed.rawValue)
                samplesToDrop = (samplesToDrop / hop) * hop
                sampleBufferOffset += samplesToDrop
            }
        }

        // Process when we have enough samples (using offset for O(1) instead of O(n) removeFirst)
        while sampleBuffer.count - sampleBufferOffset >= currentFFTSize {
            let samples = Array(sampleBuffer[sampleBufferOffset..<(sampleBufferOffset + currentFFTSize)])
            let t0 = CFAbsoluteTimeGetCurrent()
            processFFTFrame(samples: samples, peakLevel: peakDB)
            let t1 = CFAbsoluteTimeGetCurrent()
            fftProcessTimeAccumMs += (t1 - t0) * 1000.0
            fftProcessCount += 1
            sampleBufferOffset += scrollSpeed.rawValue

            // Periodisch aufräumen wenn Offset zu groß wird (nur alle ~10 Iterationen)
            if sampleBufferOffset > currentFFTSize * 2 {
                sampleBuffer.removeFirst(sampleBufferOffset)
                sampleBufferOffset = 0
            }
        }
    }
    
    private func processFFTFrame(samples: [Float], peakLevel: Float) {
        let signpostID = OSSignpostID(log: Self.performanceLog)
        os_signpost(.begin, log: Self.performanceLog, name: "FFTFrameProcessing", signpostID: signpostID)
        defer { os_signpost(.end, log: Self.performanceLog, name: "FFTFrameProcessing", signpostID: signpostID) }

        // Thread-sichere FFT-Verarbeitung
        processingLock.lock()
        let currentFFTSize = fftSize
        let localFFTProcessor = fftProcessor
        let localWeightingProcessor = weightingProcessor
        processingLock.unlock()

        // Prüfe ob Samples zur aktuellen FFT-Größe passen
        guard samples.count >= currentFFTSize else { return }

        // Perform FFT
        let linearMagnitudes = localFFTProcessor.performFFT(on: samples, gainBoost: gainBoost)
        
        if enableVerboseLogs && debugPrintCounter % 240 == 0 {
            let dbMags = localFFTProcessor.convertToDB(linearMagnitudes)
            let minMag = (dbMags.min() ?? 0) + calibrationOffset
            let maxMag = (dbMags.max() ?? 0) + calibrationOffset
            Logger.audioEngine.debug("FFT Processed (dB SPL): min=\(minMag, format: .fixed(precision: 1)), max=\(maxMag, format: .fixed(precision: 1))")
        }

        // Convert to dB for Spectrogram (dBFS → dB SPL mit Kalibrierung)
        var dbMagnitudes = localFFTProcessor.convertToDB(linearMagnitudes)
        // Wende Kalibrierungs-Offset an, um positive dB SPL Werte zu erhalten
        for i in 0..<dbMagnitudes.count {
            dbMagnitudes[i] += calibrationOffset
        }

        // Apply all frequency weightings for spectrogram display
        let dbZ = dbMagnitudes  // Z-weighted (linear/unweighted)
        let dbA = localWeightingProcessor.applyWeighting(
            to: dbMagnitudes,
            frequencies: localFFTProcessor.frequencies,
            weighting: .a
        )
        let dbC = localWeightingProcessor.applyWeighting(
            to: dbMagnitudes,
            frequencies: localFFTProcessor.frequencies,
            weighting: .c
        )

        // Spectrogram Processing (Filtering, Octaves, Binning, Smoothing)
        // Process all weightings for spectrogram
        let processedZ = spectrogramProcessor.process(
            frequencies: localFFTProcessor.frequencies,
            dbMagnitudes: dbZ,
            sampleRate: sampleRate
        )
        let processedA = spectrogramProcessor.process(
            frequencies: localFFTProcessor.frequencies,
            dbMagnitudes: dbA,
            sampleRate: sampleRate
        )
        let processedC = spectrogramProcessor.process(
            frequencies: localFFTProcessor.frequencies,
            dbMagnitudes: dbC,
            sampleRate: sampleRate
        )

        // Use selected weighting for octave bands and spectrum
        let processed: SpectrogramProcessor.Result
        switch frequencyWeighting {
        case .a:
            processed = processedA
        case .c:
            processed = processedC
        case .z:
            processed = processedZ
        }
        
        // Calculate energies for acoustic metrics
        let rawMagnitudes = linearMagnitudes
        let aWeights = localWeightingProcessor.getAWeightingGains()
        let cWeights = localWeightingProcessor.getCWeightingGains()

        // Kalibrierungsfaktor: wandelt dBFS-Energie zu dB SPL-Energie
        // calibrationOffset ist in dB, also multiplizieren wir Energie mit 10^(offset/10)
        let calibrationFactor = pow(10.0, calibrationOffset / 10.0)

        var energyZ: Float = 0.0
        var energyA: Float = 0.0
        var energyC: Float = 0.0

        // Sichere Iteration: min() verhindert Index-Out-of-Bounds wenn FFT-Größe geändert wurde
        let count = min(rawMagnitudes.count, min(aWeights.count, cWeights.count))
        for i in 0..<count {
            let magSq = rawMagnitudes[i] * rawMagnitudes[i]
            energyZ += magSq
            energyA += magSq * aWeights[i] * aWeights[i]
            energyC += magSq * cWeights[i] * cWeights[i]
        }

        // Wende Kalibrierung auf alle Energiewerte an
        energyZ *= calibrationFactor
        energyA *= calibrationFactor
        energyC *= calibrationFactor
        
        // Update acoustic metrics
        let dt = Float(scrollSpeed.rawValue) / Float(sampleRate)
        let levels = metricsCalculator.updateMetrics(
            energyZ: energyZ,
            energyA: energyA,
            energyC: energyC,
            peakLevel: peakLevel,
            dt: dt,
            recordingDuration: recordingDuration
        )
        
        let broadbandLevel = levels["LAF"] ?? -120.0
        
        if debugPrintCounter % 240 == 0 {
            Logger.audioEngine.debug("Broadband Level: \(broadbandLevel, format: .fixed(precision: 1)) dB")
        }
        
        // Create spectrogram data with all weightings
        let spectrogramData = SpectrogramData(
            frequencies: processedZ.bandFrequencies,
            magnitudes: processedZ.bandMagnitudes,      // Z-weighted (linear)
            magnitudesA: processedA.bandMagnitudes,     // A-weighted
            magnitudesC: processedC.bandMagnitudes,     // C-weighted
            broadbandLevel: broadbandLevel,
            levels: levels,
            sampleRate: sampleRate,
            timestamp: Date(timeIntervalSinceReferenceDate: lastAudioBufferTimestamp)
        )
        
        // Update UI on main thread
        updateUI(
            spectrogramData: spectrogramData,
            octaveBands: processed.octaveBands,
            spectrum: processed.spectrum,
            broadbandLevel: broadbandLevel,
            peakLevel: peakLevel,
            processEndTime: CFAbsoluteTimeGetCurrent()
        )
    }
    
    private func updateUI(
        spectrogramData: SpectrogramData,
        octaveBands: [Float],
        spectrum: [Float],
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

            // Update recording duration
            if let startTime = self.recordingStartTime {
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
            
            // Update data
            self.currentSpectrogramData = spectrogramData
            self.currentOctaveBands = octaveBands
            self.currentSpectrum = spectrum
            self.currentPeakLevel = peakLevel
            self.currentLevel = broadbandLevel
            
            // Update min/max
            self.maxLevel = max(self.maxLevel, broadbandLevel)
            if broadbandLevel > -110 {
                self.minLevel = min(self.minLevel == 0 ? broadbandLevel : self.minLevel, broadbandLevel)
            }
            
            // Update history (nur einzelnes Element entfernen wenn nötig - O(n) aber selten)
            self.levelHistory.append(broadbandLevel)
            if self.levelHistory.count > self.maxHistorySize {
                self.levelHistory.removeFirst()  // Nur 1 Element statt vieler
            }
            
            // Send to watch (throttled)
            let now = Date().timeIntervalSince1970
            if now - self.lastWatchUpdate > 0.1 {
                self.connectivityManager.sendSpectrogramData(spectrogramData)
                self.lastWatchUpdate = now
            }
        }
    }
}
