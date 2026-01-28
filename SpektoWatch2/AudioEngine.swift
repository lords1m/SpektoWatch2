import Foundation
import AVFoundation
import Accelerate
import Combine

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
    
    // MARK: - Processing Components
    
    private let fftProcessor: FFTProcessor
    private let weightingProcessor: FrequencyWeightingProcessor
    private let metricsCalculator: AcousticMetricsCalculator
    private let spectrogramProcessor: SpectrogramProcessor
    private let testGenerator: TestAudioGenerator
    private let bandstopFilterManager: BandstopFilterManager
    private let connectivityManager: WatchConnectivityManager
    
    // MARK: - Audio Engine
    
    private var audioEngine: AVAudioEngine
    private let fftSize: Int = 8192
    private let tapBlockSize: AVAudioFrameCount = 512
    private let sampleRate: Double = 44100.0
    
    // MARK: - Buffer Management
    
    private var sampleBuffer: [Float] = []
    private var gainBoost: Float = 10.0
    
    // MARK: - State Management
    
    private var isUsingDummyData = false
    private var hasLoggedSilence = false
    private var debugPrintCounter = 0
    private var lastWatchUpdate: TimeInterval = 0
    private let maxHistorySize = 1000
    
    // MARK: - Recording
    
    private var recordingStartTime: Date?
    private var audioFile: AVAudioFile?
    var lastRecordingURL: URL?
    
    // MARK: - Published Properties
    
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
    
    // MARK: - Recording Control
    
    func startRecording() {
        Logger.audioEngine.info("Starting AudioEngine recording")
        engineStatus = .starting
        recordingStartTime = Date()
        recordingDuration = 0.0
        hasLoggedSilence = false
        
        resetMetrics()
        
        #if targetEnvironment(simulator)
        print("Running on Simulator - using dummy audio data")
        testGenerator.start()
        engineStatus = .running
        #else
        startRealRecording()
        #endif
    }
    
    func stopRecording() {
        Logger.audioEngine.info("Stopping AudioEngine recording")
        recordingStartTime = nil
        audioFile = nil
        engineStatus = .idle
        
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
        processSamples(samples)
    }
    
    func getRecordingStatistics() -> (laeqFast: Float, peak: Float, min: Float) {
        return metricsCalculator.getStatistics()
    }
    
    // MARK: - Private Recording Methods
    
    private func startRealRecording() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Check permissions
            if audioSession.recordPermission == .undetermined {
                audioSession.requestRecordPermission { [weak self] granted in
                    if granted { DispatchQueue.main.async { self?.startRecording() } }
                }
                return
            }
            if audioSession.recordPermission == .denied {
                print("[AudioEngine] Error: Microphone permission denied")
                engineStatus = .error("Microphone permission denied")
                return
            }
            
            // Configure audio session
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setPreferredIOBufferDuration(Double(tapBlockSize) / sampleRate)
            
            if audioSession.isInputGainSettable {
                try audioSession.setInputGain(1.0)
            }
            
            try audioSession.setActive(true)
            
            // Configure microphone input
            if let inputs = audioSession.availableInputs,
               let builtInMic = inputs.first(where: { $0.portType == .builtInMic }) {
                try audioSession.setPreferredInput(builtInMic)
                
                DispatchQueue.main.async {
                    self.availableDataSources = builtInMic.dataSources ?? []
                    if self.selectedDataSource == nil {
                        self.selectedDataSource = audioSession.inputDataSource ?? self.availableDataSources.first
                    }
                }
                
                if let source = self.selectedDataSource {
                    try audioSession.setInputDataSource(source)
                }
            }
            
            // Setup audio engine
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
                print("Invalid audio format - falling back to dummy data")
                testGenerator.start()
                engineStatus = .running
                isUsingDummyData = true
                return
            }
            
            // Setup recording file
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("recording_\(Date().timeIntervalSince1970).caf")
            self.audioFile = try? AVAudioFile(forWriting: tempURL, settings: recordingFormat.settings)
            self.lastRecordingURL = tempURL
            
            // Install audio tap
            inputNode.installTap(onBus: 0, bufferSize: tapBlockSize, format: recordingFormat) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer)
            }
            
            try audioEngine.start()
            engineStatus = .running
            
        } catch {
            print("Audio engine start error: \(error)")
            engineStatus = .error(error.localizedDescription)
            print("Falling back to dummy data")
            testGenerator.start()
            engineStatus = .running
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
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        
        // Write to file if recording
        if let audioFile = audioFile {
            try? audioFile.write(from: buffer)
        }
        
        // Extract samples and calculate stereo phase
        let channels = Int(buffer.format.channelCount)
        let newSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        
        var phase: Float = 1.0
        if channels > 1 {
            let rightSamples = Array(UnsafeBufferPointer(start: channelData[1], count: frameCount))
            var dotProd: Float = 0
            var sumSqL: Float = 0
            var sumSqR: Float = 0
            vDSP_dotpr(newSamples, 1, rightSamples, 1, &dotProd, vDSP_Length(frameCount))
            vDSP_svesq(newSamples, 1, &sumSqL, vDSP_Length(frameCount))
            vDSP_svesq(rightSamples, 1, &sumSqR, vDSP_Length(frameCount))
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
        // Calculate peak level
        var rms: Float = 0
        vDSP_rmsqv(newSamples, 1, &rms, vDSP_Length(newSamples.count))
        let signalDB = 20 * log10(rms + 1e-9)
        let peakVal = newSamples.max() ?? 0
        let peakDB = 20 * log10(abs(peakVal) + 1e-9)
        
        // Debug logging
        debugPrintCounter += 1
        if debugPrintCounter % 240 == 0 {
            let minSample = newSamples.min() ?? 0
            let maxSample = newSamples.max() ?? 0
            Logger.audioEngine.debug("Input RMS: \(signalDB, format: .fixed(precision: 1)) dB, Samples: [\(minSample, format: .fixed(precision: 3)) ... \(maxSample, format: .fixed(precision: 3))]")
        }
        
        if signalDB < -120 && !hasLoggedSilence {
            print("[AudioEngine] WARNING: Audio buffer silent/empty: \(String(format: "%.1f", signalDB)) dB")
            hasLoggedSilence = true
        }
        
        // Add to sample buffer
        sampleBuffer.append(contentsOf: newSamples)
        
        // Process when we have enough samples
        while sampleBuffer.count >= fftSize {
            let samples = Array(sampleBuffer.prefix(fftSize))
            processFFTFrame(samples: samples, peakLevel: peakDB)
            sampleBuffer.removeFirst(scrollSpeed.rawValue)
        }
    }
    
    private func processFFTFrame(samples: [Float], peakLevel: Float) {
        // Perform FFT
        let linearMagnitudes = fftProcessor.performFFT(on: samples, gainBoost: gainBoost)
        
        if debugPrintCounter % 240 == 0 {
            let dbMags = fftProcessor.convertToDB(linearMagnitudes)
            let minMag = dbMags.min() ?? 0
            let maxMag = dbMags.max() ?? 0
            print("[AudioEngine] FFT Processed (dB): min=\(String(format: "%.1f", minMag)), max=\(String(format: "%.1f", maxMag))")
        }
        
        // Convert to dB for Spectrogram
        let dbMagnitudes = fftProcessor.convertToDB(linearMagnitudes)
        
        // Apply frequency weighting
        let weightedDB = weightingProcessor.applyWeighting(
            dbMagnitudes,
            type: frequencyWeighting
        )
        
        // Spectrogram Processing (Filtering, Octaves, Binning, Smoothing)
        let processed = spectrogramProcessor.process(
            frequencies: fftProcessor.frequencies,
            dbMagnitudes: weightedDB,
            sampleRate: sampleRate
        )
        
        // Calculate energies for acoustic metrics
        let rawMagnitudes = linearMagnitudes
        let aWeights = weightingProcessor.getAWeightingGains()
        let cWeights = weightingProcessor.getCWeightingGains()
        
        var energyZ: Float = 0.0
        var energyA: Float = 0.0
        var energyC: Float = 0.0
        
        for i in 0..<rawMagnitudes.count {
            let magSq = rawMagnitudes[i] * rawMagnitudes[i]
            energyZ += magSq
            energyA += magSq * aWeights[i] * aWeights[i]
            energyC += magSq * cWeights[i] * cWeights[i]
        }
        
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
            print("[AudioEngine] Broadband Level: \(String(format: "%.1f", broadbandLevel)) dB")
        }
        
        // Create spectrogram data
        let spectrogramData = SpectrogramData(
            frequencies: processed.bandFrequencies,
            magnitudes: processed.bandMagnitudes,
            broadbandLevel: broadbandLevel,
            levels: levels,
            sampleRate: sampleRate
        )
        
        // Update UI on main thread
        updateUI(spectrogramData: spectrogramData, octaveBands: processed.octaveBands, spectrum: processed.spectrum, broadbandLevel: broadbandLevel, peakLevel: peakLevel)
    }
    
    private func updateUI(spectrogramData: SpectrogramData, octaveBands: [Float], spectrum: [Float], broadbandLevel: Float, peakLevel: Float) {
        DispatchQueue.main.async {
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
            
            // Update history
            self.levelHistory.append(broadbandLevel)
            if self.levelHistory.count > self.maxHistorySize {
                self.levelHistory.removeFirst(self.levelHistory.count - self.maxHistorySize)
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
