import Foundation
import AVFoundation
import Accelerate
import Combine
import OSLog

enum TimeWeighting: String, CaseIterable {
    case fast = "Fast"
    case slow = "Slow"
    
    var displayName: String { rawValue }
}

enum FrequencyWeighting: String, CaseIterable {
    case z = "Z"
    case a = "A"
    case c = "C"
    
    var displayName: String {
        switch self {
        case .z: return "Linear (Z)"
        case .a: return "A-Weighting"
        case .c: return "C-Weighting"
        }
    }
}

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

class AudioEngine: ObservableObject {

    private let config: AudioConfiguration
    private var audioEngine: AVAudioEngine
    private var sampleBuffer: [Float] = []
    private var dummyDataTimer: Timer?
    private var isUsingDummyData = false
    private var gainBoost: Float = 10.0
    private var hasLoggedSilence = false
    private var debugPrintCounter = 0
    private var lastWatchUpdate: TimeInterval = 0

    // Recording
    private var recordingStartTime: Date?
    private var audioFile: AVAudioFile?
    var lastRecordingURL: URL?

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

    @Published var timeWeighting: TimeWeighting = .fast
    @Published var frequencyWeighting: FrequencyWeighting = .a
    @Published var scrollSpeed: ScrollSpeed = .fast

    private var smoothedLevel: Float = -120.0

    // Processors
    private var fftProcessor: FFTProcessor
    private var weightingProcessor: FrequencyWeightingProcessor
    private var metricsCalculator: AcousticMetricsCalculator
    private var connectivityManager: WatchConnectivityManager
    
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

    private var spectrogramProcessor: SpectrogramProcessor

    init(config: AudioConfiguration = .default, filterManager: BandstopFilterManager, connectivityManager: WatchConnectivityManager) {
        self.config = config
        audioEngine = AVAudioEngine()
        self.connectivityManager = connectivityManager
        
        fftProcessor = FFTProcessor(fftSize: config.fftSize, sampleRate: config.sampleRate)
        weightingProcessor = FrequencyWeightingProcessor(fftSize: config.fftSize, sampleRate: config.sampleRate)
        metricsCalculator = AcousticMetricsCalculator()
        spectrogramProcessor = SpectrogramProcessor(bandstopFilterManager: filterManager)
    }

    deinit {
    }

    func setTimeWeighting(_ weighting: TimeWeighting) {
        timeWeighting = weighting
        spectrogramProcessor.temporalSmoothingFactor = (weighting == .fast) ? 0.5 : 0.9
    }

    func setFrequencyWeighting(_ weighting: FrequencyWeighting) {
        frequencyWeighting = weighting
    }

    func setGainBoost(_ gain: Float) {
        gainBoost = gain
    }
    

    func startRecording() {
        Logger.audioEngine.info("Starting AudioEngine recording")
        engineStatus = .starting
        recordingStartTime = Date()
        recordingDuration = 0.0
        hasLoggedSilence = false
        lastError = nil

        DispatchQueue.main.async {
            self.levelHistory.removeAll()
            self.currentLevel = -120.0
            self.maxLevel = -120.0
            self.metricsCalculator.reset()
        }

        #if targetEnvironment(simulator)
        Logger.audioEngine.notice("Running on Simulator - using dummy audio data")
        startDummyDataGeneration()
        engineStatus = .running
        #else
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            if audioSession.recordPermission == .undetermined {
                audioSession.requestRecordPermission { [weak self] granted in
                    if granted { DispatchQueue.main.async { self?.startRecording() } }
                }
                return
            }
            if audioSession.recordPermission == .denied {
                Logger.audioEngine.error("Microphone permission denied")
                let error = SpektoWatchError.microphonePermissionDenied
                lastError = error
                engineStatus = .error("Microphone permission denied")
                return
            }

            do {
                try audioSession.setCategory(.record, mode: .measurement, options: [])
                try audioSession.setPreferredIOBufferDuration(Double(config.tapBlockSize) / config.sampleRate)
            } catch {
                let err = SpektoWatchError.audioEngineFailure(reason: "Audio Session Konfiguration fehlgeschlagen: \(error.localizedDescription)")
                lastError = err
                engineStatus = .error(err.localizedDescription)
                return
            }

            if audioSession.isInputGainSettable {
                try audioSession.setInputGain(1.0)
            }

            do {
                try audioSession.setActive(true)
            } catch {
                let err = SpektoWatchError.audioEngineFailure(reason: "Audio Session konnte nicht aktiviert werden: \(error.localizedDescription)")
                lastError = err
                engineStatus = .error(err.localizedDescription)
                return
            }
            
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
                    try? audioSession.setInputDataSource(source)
                }
            }

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
                Logger.audioEngine.error("Invalid audio format - falling back to dummy data")
                let err = SpektoWatchError.invalidAudioFormat
                lastError = err
                startDummyDataGeneration()
                engineStatus = .error(err.localizedDescription)
                return
            }

            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("recording_\(Date().timeIntervalSince1970).caf")
            do {
                self.audioFile = try AVAudioFile(forWriting: tempURL, settings: recordingFormat.settings)
            } catch {
                Logger.audioEngine.error("Failed to create audio file: \(error.localizedDescription)")
                // Non-fatal, we just won't save to disk
            }
            self.lastRecordingURL = tempURL

            inputNode.installTap(onBus: 0, bufferSize: config.tapBlockSize, format: recordingFormat) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer)
            }

            try audioEngine.start()
            engineStatus = .running
        } catch {
            Logger.audioEngine.error("Audio engine start error: \(error.localizedDescription)")
            let err = SpektoWatchError.audioEngineFailure(reason: error.localizedDescription)
            lastError = err
            engineStatus = .error(error.localizedDescription)
            Logger.audioEngine.notice("Falling back to dummy data due to error")
            startDummyDataGeneration()
            engineStatus = .running
        }
        #endif
    }

    func stopRecording() {
        Logger.audioEngine.info("Stopping AudioEngine recording")
        recordingStartTime = nil
        audioFile = nil
        engineStatus = .idle

        #if targetEnvironment(simulator)
        stopDummyDataGeneration()
        #else
        if !isUsingDummyData {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        } else {
            stopDummyDataGeneration()
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

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        
        if let audioFile = audioFile {
            try? audioFile.write(from: buffer)
        }
        
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
            vDSP_svesq(newSamples, 1, &sumSqR, vDSP_Length(frameCount))
            phase = dotProd / (sqrt(sumSqL * sumSqR) + 1e-9)
        }

        processSamples(newSamples)
        
        if channels > 1 {
            DispatchQueue.main.async {
                self.currentStereoPhase = phase
            }
        }
    }
    
    func processExternalAudio(_ samples: [Float]) {
        processSamples(samples)
    }
    
    private func processSamples(_ newSamples: [Float]) {
        var rms: Float = 0
        vDSP_rmsqv(newSamples, 1, &rms, vDSP_Length(newSamples.count))
        let signalDB = 20 * log10(rms + 1e-9)
        let peakVal = newSamples.max() ?? 0
        let peakDB = 20 * log10(abs(peakVal) + 1e-9)
        metricsCalculator.updatePeak(samples: newSamples)

        debugPrintCounter += 1
        if debugPrintCounter % 240 == 0 {
            let minSample = newSamples.min() ?? 0
            let maxSample = newSamples.max() ?? 0
            Logger.audioEngine.debug("Input RMS: \(signalDB, format: .fixed(precision: 1)) dB, Samples: [\(minSample, format: .fixed(precision: 3)) ... \(maxSample, format: .fixed(precision: 3))]")
        }
        
        if signalDB < -120 {
            if !hasLoggedSilence {
                Logger.audioEngine.warning("Audio buffer silent/empty: \(signalDB, format: .fixed(precision: 1)) dB")
                hasLoggedSilence = true
            }
        }

        sampleBuffer.append(contentsOf: newSamples)
        
        while sampleBuffer.count >= config.fftSize {
            let samples = Array(sampleBuffer.prefix(config.fftSize))

            // 1. Perform FFT (Linear Magnitudes)
            let linearMagnitudes = fftProcessor.performFFT(on: samples, gainBoost: gainBoost)
            
            // 2. Convert to dB for Spectrogram
            var dbMagnitudes = fftProcessor.convertToDB(linearMagnitudes)
            
            // 3. Apply Frequency Weighting (Offsets) for Display
            dbMagnitudes = weightingProcessor.applyWeighting(dbMagnitudes, type: frequencyWeighting)

            if debugPrintCounter % 240 == 0 {
                let minMag = dbMagnitudes.min() ?? 0
                let maxMag = dbMagnitudes.max() ?? 0
                Logger.audioEngine.debug("FFT Processed (dB): min=\(minMag, format: .fixed(precision: 1)), max=\(maxMag, format: .fixed(precision: 1))")
            }
            
            // 4. Spectrogram Processing (Filtering, Binning, Smoothing, Octave Bands)
            let processed = spectrogramProcessor.process(
                frequencies: fftProcessor.frequencies,
                dbMagnitudes: dbMagnitudes,
                sampleRate: config.sampleRate
            )

            let levels = metricsCalculator.calculateMetrics(
                linearMagnitudes: linearMagnitudes,
                aWeightsSq: weightingProcessor.aWeightsLinearSq,
                cWeightsSq: weightingProcessor.cWeightsLinearSq,
                scrollSpeed: scrollSpeed,
                sampleRate: config.sampleRate,
                recordingDuration: recordingDuration
            )
            
            let broadbandLevel = levels["LAF"] ?? -120.0

            if debugPrintCounter % 240 == 0 {
                Logger.audioEngine.debug("Broadband Level: \(broadbandLevel, format: .fixed(precision: 1)) dB")
            }

            let spectrogramData = SpectrogramData(
                frequencies: processed.bandFrequencies,
                magnitudes: processed.bandMagnitudes,
                broadbandLevel: broadbandLevel,
                levels: levels,
                sampleRate: config.sampleRate
            )

            DispatchQueue.main.async {
                if let startTime = self.recordingStartTime {
                    self.recordingDuration = Date().timeIntervalSince(startTime)
                }

                self.currentSpectrogramData = spectrogramData
                
                self.currentOctaveBands = processed.octaveBands
                self.currentSpectrum = processed.spectrum
                self.currentPeakLevel = peakDB
                self.currentLevel = broadbandLevel
                
                self.maxLevel = max(self.maxLevel, broadbandLevel)
                if broadbandLevel > -110 {
                    self.minLevel = min(self.minLevel == 0 ? broadbandLevel : self.minLevel, broadbandLevel)
                }
                
                self.levelHistory.append(broadbandLevel)
                if self.levelHistory.count > self.config.maxHistorySize {
                    self.levelHistory.removeFirst(self.levelHistory.count - self.config.maxHistorySize)
                }
                
                let now = Date().timeIntervalSince1970
                if now - self.lastWatchUpdate > 0.1 {
                    self.connectivityManager.sendSpectrogramData(spectrogramData)
                    self.lastWatchUpdate = now
                }
            }
            
            sampleBuffer.removeFirst(scrollSpeed.rawValue)
        }
    }
    
    private func startDummyDataGeneration() {
        isUsingDummyData = true

        let updateInterval: TimeInterval = 0.05
        dummyDataTimer?.invalidate()
        dummyDataTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.generateDummySpectrogramData()
        }
    }

    private func stopDummyDataGeneration() {
        isUsingDummyData = false
        dummyDataTimer?.invalidate()
        dummyDataTimer = nil
    }

    private func generateDummySpectrogramData() {
        let t = Date().timeIntervalSince1970

        let dummyFFTLength = 512
        let nyquist = Float(config.sampleRate / 2.0)
        let freqResolution = nyquist / Float(dummyFFTLength)

        var dummyFrequencies = [Float]()
        var dummyMagnitudes = [Float]()

        for i in 0..<dummyFFTLength {
            let freq = Float(i) * freqResolution
            dummyFrequencies.append(freq)

            let phase1 = Float(t) * 0.3 + Float(i) * 0.01
            let phase2 = Float(t) * 0.5 + Float(i) * 0.02
            let peak1 = sin(phase1) * 15
            let peak2 = sin(phase2) * 10
            let noise = Float.random(in: -5...0)

            let mag = peak1 + peak2 + noise - 40
            dummyMagnitudes.append(mag)
        }

        let processed = spectrogramProcessor.process(
            frequencies: dummyFrequencies,
            dbMagnitudes: dummyMagnitudes,
            sampleRate: config.sampleRate
        )

        let data = SpectrogramData(
            frequencies: processed.bandFrequencies,
            magnitudes: processed.bandMagnitudes,
            broadbandLevel: -40.0 + Float.random(in: -5...5),
            levels: ["LAF": -40.0 + Float.random(in: -5...5)],
            sampleRate: config.sampleRate
        )

        DispatchQueue.main.async {
            if let startTime = self.recordingStartTime {
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
            self.currentSpectrogramData = data
            self.connectivityManager.sendSpectrogramData(data)
        }
    }
    
    func getRecordingStatistics() -> (laeqFast: Float, peak: Float, min: Float) {
        return (
            laeqFast: currentLevel,
            peak: maxLevel,
            min: minLevel
        )
    }
}
