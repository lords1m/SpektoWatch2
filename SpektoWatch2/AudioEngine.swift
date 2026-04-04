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
    private static let thirdOctaveCenters: [Float] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800,
        1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
    ]
    
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
    private var measurementWriter: MeasurementDataWriter?
    private let measurementMetricKeys: [String] = [
        "LAF", "LAS", "LCF", "LCS", "LZF", "LZS",
        "LAeq", "LAFmin", "LAFmax", "LCpeak",
        "LAFT5", "LAF5", "LAF95", "LAFTeq"
    ]
    var lastRecordingURL: URL?
    var lastMeasurementDataURL: URL?
    
    // MARK: - Published Properties

    /// Gibt an, ob Audio in eine Datei geschrieben wird (true) oder nur Live-Anzeige (false)
    @Published var isRecordingToFile: Bool = false
    @Published var isMeasurementRecording: Bool = false {
        didSet {
            if isRecordingToFile {
                if isMeasurementRecording {
                    setupMeasurementDataFileIfNeeded()
                } else {
                    lastMeasurementDataURL = nil
                    closeMeasurementWriter()
                }
            }
        }
    }
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
    @Published var isStereoActive: Bool = false
    @Published var currentOctaveBands: [Float] = Array(repeating: -120.0, count: 31)
    @Published var currentOctaveBandsZ: [Float] = Array(repeating: -120.0, count: 31)
    @Published var currentOctaveBandsA: [Float] = Array(repeating: -120.0, count: 31)
    @Published var currentOctaveBandsC: [Float] = Array(repeating: -120.0, count: 31)
    @Published var currentSpectrum: [Float] = []
    
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
            UserDefaults.standard.set(Double(clamped), forKey: "spectrogramFrequencySmoothing")
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
            UserDefaults.standard.set(Double(clamped), forKey: "spectrogramTemporalSmoothing")
        }
    }
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
        fftProcessor = FFTProcessor(fftSize: fftSize, sampleRate: processingSampleRate)
        weightingProcessor = FrequencyWeightingProcessor(fftSize: fftSize, sampleRate: processingSampleRate)
        metricsCalculator = AcousticMetricsCalculator(sampleRate: sampleRate)
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

        if let savedFrequencySmoothing = UserDefaults.standard.object(forKey: "spectrogramFrequencySmoothing") as? Double {
            spectrogramFrequencySmoothing = Float(savedFrequencySmoothing)
        }
        if let savedTemporalSmoothing = UserDefaults.standard.object(forKey: "spectrogramTemporalSmoothing") as? Double {
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
        processingLock.lock()

        // Buffer leeren um Race-Conditions zu vermeiden
        sampleBuffer.removeAll()
        sampleBufferOffset = 0
        fftInputBuffer.removeAll()

        // Aktualisiere interne Werte
        fftSize = newSize
        currentWindowFunction = newWindow
        currentBlockSize = config.blockSize

        // Rekonfiguriere den FFT Processor
        fftProcessor.reconfigure(fftSize: newSize, windowFunction: newWindow)

        // Erstelle neuen Weighting Processor (alter wird nach unlock freigegeben)
        let newWeightingProcessor = FrequencyWeightingProcessor(fftSize: newSize, sampleRate: processingSampleRate)
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
        fftInputBuffer.removeAll()

        fftSize = size.rawValue
        currentBlockSize = size
        fftProcessor.reconfigure(fftSize: size.rawValue, windowFunction: currentWindowFunction)

        // Erstelle neuen Weighting Processor
        let newWeightingProcessor = FrequencyWeightingProcessor(fftSize: size.rawValue, sampleRate: processingSampleRate)
        weightingProcessor = newWeightingProcessor

        processingLock.unlock()

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

        // Always capture measurement data when starting a recording.
        if !isMeasurementRecording {
            isMeasurementRecording = true
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
                if isMeasurementRecording {
                    setupMeasurementDataFileIfNeeded()
                } else {
                    lastMeasurementDataURL = nil
                    closeMeasurementWriter()
                }
            }
            return
        }
        Logger.audioEngine.info("Starting AudioEngine in RECORDING mode")
        isRecordingToFile = true
        if !isMeasurementRecording {
            lastMeasurementDataURL = nil
            closeMeasurementWriter()
        }
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
        if isRecordingToFile {
            setupRecordingFile()
            setupMeasurementDataFileIfNeeded()
        }
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
        closeMeasurementWriter()
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
        fftInputBuffer.removeAll()
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

    private func setupMeasurementDataFileIfNeeded() {
        guard isRecordingToFile, isMeasurementRecording else {
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
        guard let writer = measurementWriter else { return }
        do {
            try writer.close()
        } catch {
            Logger.audioEngine.error("Measurement writer close failed: \(error.localizedDescription)")
        }
        measurementWriter = nil
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
                            self.isRecordingToFile = false
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
                    self.isRecordingToFile = false
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
                            self.isRecordingToFile = false
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
                    self.isRecordingToFile = false
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
                        self.isRecordingToFile = false
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
                self.isRecordingToFile = false
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
                self.audioFile = try? AVAudioFile(forWriting: tempURL, settings: recordingFormat.settings)
                self.lastRecordingURL = tempURL
                Logger.audioEngine.info("Recording to file: \(tempURL.lastPathComponent)")
                setupMeasurementDataFileIfNeeded()
            } else {
                self.audioFile = nil
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
            self.levelHistory.removeAll()
            self.currentLevel = -120.0
            self.maxLevel = -120.0
            self.minLevel = -120.0
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

        let isStereo = channels > 1
        DispatchQueue.main.async {
            self.isStereoActive = isStereo
            self.currentStereoPhase = phase  // 1.0 for mono (no stereo data)
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
        let bufferedSeconds = Double(bufferedSamples) / processingSampleRate
        if bufferedSeconds > maxBufferedSeconds {
            maxBufferedSeconds = bufferedSeconds
        }
        // Keep the visualization near real-time: if processing falls behind,
        // drop oldest queued samples instead of rendering stale history.
        // Never trim below one full FFT window (+ one hop), otherwise no frames can be processed.
        let minRequiredBufferedSeconds = Double(currentFFTSize + max(1, scrollSpeed.rawValue)) / processingSampleRate
        let effectiveBacklogLimitSeconds = max(maxRealtimeBacklogSeconds, minRequiredBufferedSeconds)
        if bufferedSeconds > effectiveBacklogLimitSeconds {
            let targetBufferedSamples = Int(effectiveBacklogLimitSeconds * processingSampleRate)
            var samplesToDrop = bufferedSamples - targetBufferedSamples
            if samplesToDrop > 0 {
                let hop = max(1, scrollSpeed.rawValue)
                samplesToDrop = (samplesToDrop / hop) * hop
                sampleBufferOffset += samplesToDrop
            }
        }

        // Process when we have enough samples (using offset for O(1) instead of O(n) removeFirst)
        while sampleBuffer.count - sampleBufferOffset >= currentFFTSize {
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
            let t0 = CFAbsoluteTimeGetCurrent()
            processFFTFrame(samples: fftInputBuffer, peakLevel: peakDB)
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
            sampleRate: processingSampleRate,
            smoothingTrack: .z
        )
        let processedA = spectrogramProcessor.process(
            frequencies: localFFTProcessor.frequencies,
            dbMagnitudes: dbA,
            sampleRate: processingSampleRate,
            smoothingTrack: .a
        )
        let processedC = spectrogramProcessor.process(
            frequencies: localFFTProcessor.frequencies,
            dbMagnitudes: dbC,
            sampleRate: processingSampleRate,
            smoothingTrack: .c
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

        let displayOctaveBandsZ = computeDisplayThirdOctaveBands(
            frequencies: processedZ.bandFrequencies,
            magnitudes: processedZ.bandMagnitudes
        )
        let displayOctaveBandsA = computeDisplayThirdOctaveBands(
            frequencies: processedA.bandFrequencies,
            magnitudes: processedA.bandMagnitudes
        )
        let displayOctaveBandsC = computeDisplayThirdOctaveBands(
            frequencies: processedC.bandFrequencies,
            magnitudes: processedC.bandMagnitudes
        )
        let displayOctaveBands: [Float]
        switch frequencyWeighting {
        case .a:
            displayOctaveBands = displayOctaveBandsA
        case .c:
            displayOctaveBands = displayOctaveBandsC
        case .z:
            displayOctaveBands = displayOctaveBandsZ
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
        let dt = Float(scrollSpeed.rawValue) / Float(processingSampleRate)
        spectrogramProcessor.hopDuration = dt
        let levels = metricsCalculator.updateMetrics(
            energyZ: energyZ,
            energyA: energyA,
            energyC: energyC,
            peakLevel: peakLevel,
            dt: dt,
            recordingDuration: recordingDuration
        )
        
        let broadbandLevel = levels["LAF"] ?? -120.0

        if isRecordingToFile && isMeasurementRecording {
            setupMeasurementDataFileIfNeeded()
            if let writer = measurementWriter {
                let timestampSeconds: Float
                if let startTime = recordingStartTime {
                    timestampSeconds = Float(Date().timeIntervalSince(startTime))
                } else {
                    timestampSeconds = Float(recordingDuration)
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
                    Logger.audioEngine.error("Measurement frame write failed: \(error.localizedDescription)")
                }
            }
        }
        
        if debugPrintCounter % 240 == 0 {
            Logger.audioEngine.debug("Broadband Level: \(broadbandLevel, format: .fixed(precision: 1)) dB")
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
            magnitudesA: processedA.bandMagnitudes,     // A-weighted
            magnitudesC: processedC.bandMagnitudes,     // C-weighted
            broadbandLevel: broadbandLevel,
            levels: levels,
            sampleRate: processingSampleRate,
            timestamp: Date(timeIntervalSinceReferenceDate: lastAudioBufferTimestamp)
        )
        
        // Feed spectrogram renderers directly — bypasses objectWillChange, no SwiftUI re-render.
        spectrogramSubject.send(spectrogramData)

        // Update UI on main thread
        updateUI(
            spectrogramData: spectrogramData,
            octaveBands: displayOctaveBands,
            octaveBandsZ: displayOctaveBandsZ,
            octaveBandsA: displayOctaveBandsA,
            octaveBandsC: displayOctaveBandsC,
            spectrum: processed.spectrum,
            broadbandLevel: broadbandLevel,
            peakLevel: peakLevel,
            processEndTime: CFAbsoluteTimeGetCurrent()
        )
    }
    
    private func updateUI(
        spectrogramData: SpectrogramData,
        octaveBands: [Float],
        octaveBandsZ: [Float],
        octaveBandsA: [Float],
        octaveBandsC: [Float],
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
            
            // Update data — currentSpectrogramData throttled to 15 Hz to reduce
            // objectWillChange pressure on the SwiftUI hierarchy (spectrogram
            // renderers get data at full rate via spectrogramSubject).
            let nowMain = CFAbsoluteTimeGetCurrent()
            if nowMain - self.lastSpectrogramUIEnqueueTime >= self.targetSpectrogramUIInterval {
                self.lastSpectrogramUIEnqueueTime = nowMain
                self.currentSpectrogramData = spectrogramData
            }
            self.currentOctaveBands = octaveBands
            self.currentOctaveBandsZ = octaveBandsZ
            self.currentOctaveBandsA = octaveBandsA
            self.currentOctaveBandsC = octaveBandsC
            self.currentSpectrum = spectrum
            self.currentPeakLevel = peakLevel
            self.currentLevel = broadbandLevel
            
            // Update min/max
            self.maxLevel = max(self.maxLevel, broadbandLevel)
            if broadbandLevel > -110 {
                self.minLevel = min(self.minLevel, broadbandLevel)
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

    private func computeDisplayThirdOctaveBands(frequencies: [Float], magnitudes: [Float]) -> [Float] {
        let pairCount = min(frequencies.count, magnitudes.count)
        guard pairCount > 0 else {
            return [Float](repeating: -120.0, count: Self.thirdOctaveCenters.count)
        }

        let usableIndices = (0..<pairCount).filter { frequencies[$0] >= 0.0 && frequencies[$0] <= 20000.0 }
        guard !usableIndices.isEmpty else {
            return [Float](repeating: -120.0, count: Self.thirdOctaveCenters.count)
        }

        let lowerFactor = pow(2.0 as Float, -1.0 / 6.0)
        let upperFactor = pow(2.0 as Float, 1.0 / 6.0)
        var bands = [Float](repeating: -120.0, count: Self.thirdOctaveCenters.count)

        for (i, center) in Self.thirdOctaveCenters.enumerated() {
            let lower = center * lowerFactor
            let upper = center * upperFactor
            var hasDirectBin = false
            var bandLinearSum: Float = 0.0
            var bandBinCount = 0

            for idx in usableIndices {
                let f = frequencies[idx]
                guard f >= lower, f < upper else { continue }
                hasDirectBin = true
                bandLinearSum += pow(10.0, magnitudes[idx] / 10.0)
                bandBinCount += 1
            }

            if hasDirectBin, bandBinCount > 0 {
                // Robuste Bandenergie statt Peak-Hold:
                // verhindert künstlich stabile Spitzen im obersten Band (z.B. 20 kHz).
                let meanLinear = bandLinearSum / Float(bandBinCount)
                bands[i] = 10.0 * log10(max(meanLinear, 1e-12))
            } else {
                // Nur im unteren Bereich interpolieren (coarse FFT kann dort Bänder verfehlen).
                // Für hohe Bänder keine künstlichen Werte erzeugen.
                if center <= 250.0 {
                    bands[i] = interpolatedMagnitudeAtFrequency(
                        center,
                        frequencies: frequencies,
                        magnitudes: magnitudes,
                        usableIndices: usableIndices
                    )
                } else {
                    bands[i] = -120.0
                }
            }
        }

        return bands
    }

    private func interpolatedMagnitudeAtFrequency(
        _ targetFrequency: Float,
        frequencies: [Float],
        magnitudes: [Float],
        usableIndices: [Int]
    ) -> Float {
        guard let first = usableIndices.first, let last = usableIndices.last else { return -120.0 }
        if targetFrequency <= frequencies[first] { return magnitudes[first] }
        if targetFrequency >= frequencies[last] { return magnitudes[last] }

        var upperIdx = first
        for idx in usableIndices where frequencies[idx] >= targetFrequency {
            upperIdx = idx
            break
        }

        guard let position = usableIndices.firstIndex(of: upperIdx), position > 0 else {
            return magnitudes[upperIdx]
        }

        let lowerIdx = usableIndices[position - 1]
        let f0 = frequencies[lowerIdx]
        let f1 = frequencies[upperIdx]
        guard abs(f1 - f0) > 0.001 else {
            return max(magnitudes[lowerIdx], magnitudes[upperIdx])
        }

        let t = (targetFrequency - f0) / (f1 - f0)
        return magnitudes[lowerIdx] * (1.0 - t) + magnitudes[upperIdx] * t
    }

    private func updateProcessingSampleRateIfNeeded(_ newSampleRate: Double, source: String) {
        guard newSampleRate > 1000 else { return }
        let normalized = (newSampleRate * 10).rounded() / 10
        guard abs(normalized - processingSampleRate) > 1.0 else { return }

        processingLock.lock()

        processingSampleRate = normalized
        sampleBuffer.removeAll()
        sampleBufferOffset = 0
        fftInputBuffer.removeAll()

        fftProcessor = FFTProcessor(
            fftSize: fftSize,
            sampleRate: normalized,
            windowFunction: currentWindowFunction
        )
        weightingProcessor = FrequencyWeightingProcessor(
            fftSize: fftSize,
            sampleRate: normalized
        )

        processingLock.unlock()

        Logger.audioEngine.info(
            "Reconfigured DSP sample rate (\(source)): \(normalized, format: .fixed(precision: 1)) Hz"
        )
    }
}
