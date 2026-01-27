import Foundation
import AVFoundation
import Accelerate
import Combine

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

    private var audioEngine: AVAudioEngine
    private let fftSize: Int = 8192
    private let tapBlockSize: AVAudioFrameCount = 512
    private var sampleBuffer: [Float] = []
    private let fftSetup: vDSP_DFT_Setup
    private let sampleRate: Double = 44100.0
    private var dummyDataTimer: Timer?
    private var isUsingDummyData = false
    private var gainBoost: Float = 10.0
    private var hasLoggedSilence = false
    private var debugPrintCounter = 0
    private var lastWatchUpdate: TimeInterval = 0
    private let maxHistorySize = 1000

    // Recording
    private var recordingStartTime: Date?
    private var audioFile: AVAudioFile?
    var lastRecordingURL: URL?

    @Published var recordingDuration: TimeInterval = 0.0
    @Published var engineStatus: EngineStatus = .idle
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

    // Level calculations
    private var lafEnergy: Float = 1e-12
    private var lasEnergy: Float = 1e-12
    private var lcfEnergy: Float = 1e-12
    private var lcsEnergy: Float = 1e-12
    private var lzfEnergy: Float = 1e-12
    private var lzsEnergy: Float = 1e-12
    
    private var laeqAccumulator: Double = 0.0
    private var laeqCount: Int = 0
    private var lafMin: Float = 1000.0
    private var lafMax: Float = -1000.0
    private var lcPeakHold: Float = -120.0
    
    private var lafHistogram = [Int](repeating: 0, count: 1401)
    private var lafTotalCounts: Int = 0
    private let histMinDB: Float = -130.0
    
    private var currentTaktMax: Float = -1000.0
    private var lastTaktTime: TimeInterval = 0
    private var taktValues: [Float] = []
    
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

    private let binningFactor: Int = 2
    private var temporalSmoothingFactor: Float = 0.0
    private var previousBandMagnitudes: [Float] = []

    private var realIn: [Float]
    private var imagIn: [Float]
    private var realOut: [Float]
    private var imagOut: [Float]
    private var window: [Float]
    private var fftMagnitudes: [Float]
    
    private var aWeights: [Float] = []
    private var cWeights: [Float] = []
    
    // BANDSTOP FILTER INTEGRATION
    private var bandstopFilterManager = BandstopFilterManager.shared

    init() {
        audioEngine = AVAudioEngine()
        guard let setup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            vDSP_DFT_Direction.FORWARD
        ) else {
            fatalError("Failed to create FFT setup")
        }
        fftSetup = setup
        
        realIn = [Float](repeating: 0, count: fftSize)
        imagIn = [Float](repeating: 0, count: fftSize)
        realOut = [Float](repeating: 0, count: fftSize)
        imagOut = [Float](repeating: 0, count: fftSize)
        window = [Float](repeating: 0, count: fftSize)
        fftMagnitudes = [Float](repeating: 0, count: fftSize / 2)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        
        precomputeWeightingCurves()
    }

    deinit {
        vDSP_DFT_DestroySetup(fftSetup)
    }

    func setTimeWeighting(_ weighting: TimeWeighting) {
        timeWeighting = weighting
        temporalSmoothingFactor = (weighting == .fast) ? 0.5 : 0.9
    }

    func setFrequencyWeighting(_ weighting: FrequencyWeighting) {
        frequencyWeighting = weighting
    }

    func setGainBoost(_ gain: Float) {
        gainBoost = gain
    }
    
    private func precomputeWeightingCurves() {
        let nyquist = Float(sampleRate / 2.0)
        let freqResolution = nyquist / Float(fftSize / 2)
        
        aWeights = [Float](repeating: 0.0, count: fftSize / 2)
        cWeights = [Float](repeating: 0.0, count: fftSize / 2)
        
        for i in 0..<(fftSize / 2) {
            let f = Float(i) * freqResolution
            let f2 = f * f
            
            let aNum = 12194.0 * 12194.0 * f2 * f2
            let aDen = (f2 + 20.6 * 20.6) * sqrt((f2 + 107.7 * 107.7) * (f2 + 737.9 * 737.9)) * (f2 + 12194.0 * 12194.0)
            var aGain: Float = 0.0
            if aDen > 0 {
                let mag = aNum / aDen
                aGain = Float(mag * pow(10.0, 2.0 / 20.0))
            }
            aWeights[i] = aGain
            
            let cNum = 12194.0 * 12194.0 * f2
            let cDen = (f2 + 20.6 * 20.6) * (f2 + 12194.0 * 12194.0)
            var cGain: Float = 0.0
            if cDen > 0 {
                let mag = cNum / cDen
                cGain = Float(mag * pow(10.0, 0.06 / 20.0))
            }
            cWeights[i] = cGain
        }
    }

    func startRecording() {
        print("[AudioEngine] Start")
        engineStatus = .starting
        recordingStartTime = Date()
        recordingDuration = 0.0
        hasLoggedSilence = false

        DispatchQueue.main.async {
            self.levelHistory.removeAll()
            self.currentLevel = -120.0
            self.maxLevel = -120.0
            self.minLevel = 0.0
            self.smoothedLevel = -120.0
            
            self.laeqAccumulator = 0.0
            self.laeqCount = 0
            self.lafMin = 1000.0
            self.lafMax = -1000.0
            self.lcPeakHold = -120.0
            self.lafHistogram = [Int](repeating: 0, count: 1401)
            self.lafTotalCounts = 0
            self.currentTaktMax = -1000.0
            self.lastTaktTime = 0
            self.taktValues = []
        }

        #if targetEnvironment(simulator)
        print("Running on Simulator - using dummy audio data")
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
                print("[AudioEngine] Error: Microphone permission denied")
                engineStatus = .error("Microphone permission denied")
                return
            }

            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setPreferredIOBufferDuration(Double(tapBlockSize) / sampleRate)

            if audioSession.isInputGainSettable {
                try audioSession.setInputGain(1.0)
            }

            try audioSession.setActive(true)
            
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

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
                print("Invalid audio format - falling back to dummy data")
                startDummyDataGeneration()
                engineStatus = .running
                return
            }

            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("recording_\(Date().timeIntervalSince1970).caf")
            self.audioFile = try? AVAudioFile(forWriting: tempURL, settings: recordingFormat.settings)
            self.lastRecordingURL = tempURL

            inputNode.installTap(onBus: 0, bufferSize: tapBlockSize, format: recordingFormat) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer)
            }

            try audioEngine.start()
            engineStatus = .running
        } catch {
            print("Audio engine start error: \(error)")
            engineStatus = .error(error.localizedDescription)
            print("Falling back to dummy data")
            startDummyDataGeneration()
            engineStatus = .running
        }
        #endif
    }

    func stopRecording() {
        print("[AudioEngine] Stop")
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
        self.lcPeakHold = max(self.lcPeakHold, peakDB)

        debugPrintCounter += 1
        if debugPrintCounter % 240 == 0 {
            let minSample = newSamples.min() ?? 0
            let maxSample = newSamples.max() ?? 0
            print("[AudioEngine] Input RMS: \(String(format: "%.1f", signalDB)) dB, Samples: [\(String(format: "%.3f", minSample)) ... \(String(format: "%.3f", maxSample))]")
        }
        
        if signalDB < -120 {
            if !hasLoggedSilence {
                print("[AudioEngine] WARNING: Audio buffer silent/empty: \(String(format: "%.1f", signalDB)) dB")
                hasLoggedSilence = true
            }
        }

        sampleBuffer.append(contentsOf: newSamples)
        
        while sampleBuffer.count >= fftSize {
            let samples = Array(sampleBuffer.prefix(fftSize))

            let fftResult = performFFT(on: samples)

            if debugPrintCounter % 240 == 0 {
                let minMag = fftResult.magnitudes.min() ?? 0
                let maxMag = fftResult.magnitudes.max() ?? 0
                print("[AudioEngine] FFT Processed (dB): min=\(String(format: "%.1f", minMag)), max=\(String(format: "%.1f", maxMag))")
            }
            
            // APPLY BANDSTOP FILTERS HERE
            let filteredMagnitudes = applyBandstopFilters(
                frequencies: fftResult.frequencies,
                magnitudes: fftResult.magnitudes
            )
            
            let octaveBands = calculateOctaveBands(frequencies: fftResult.frequencies, magnitudes: filteredMagnitudes)
            let spectrum = filteredMagnitudes

            let (bandFreqs, bandMags) = aggregateByBinningFactor(
                frequencies: fftResult.frequencies,
                magnitudes: filteredMagnitudes
            )

            let smoothedMagnitudes = temporalSmoothing(currentMagnitudes: bandMags)

            var energyZ: Float = 0.0
            var energyA: Float = 0.0
            var energyC: Float = 0.0
            
            for i in 0..<fftMagnitudes.count {
                let magSq = fftMagnitudes[i] * fftMagnitudes[i]
                energyZ += magSq
                energyA += magSq * aWeights[i] * aWeights[i]
                energyC += magSq * cWeights[i] * cWeights[i]
            }
            
            let dt = Float(scrollSpeed.rawValue) / Float(sampleRate)
            let alphaFast = 1.0 - exp(-dt / 0.125)
            let alphaSlow = 1.0 - exp(-dt / 1.0)
            
            lafEnergy = (1.0 - alphaFast) * lafEnergy + alphaFast * energyA
            lasEnergy = (1.0 - alphaSlow) * lasEnergy + alphaSlow * energyA
            
            lcfEnergy = (1.0 - alphaFast) * lcfEnergy + alphaFast * energyC
            lcsEnergy = (1.0 - alphaSlow) * lcsEnergy + alphaSlow * energyC
            
            lzfEnergy = (1.0 - alphaFast) * lzfEnergy + alphaFast * energyZ
            lzsEnergy = (1.0 - alphaSlow) * lzsEnergy + alphaSlow * energyZ
            
            laeqAccumulator += Double(energyA)
            laeqCount += 1
            
            let broadbandLevel = 10.0 * log10(lafEnergy + 1e-12)
            
            lafMin = min(lafMin, broadbandLevel)
            lafMax = max(lafMax, broadbandLevel)
            
            let histIndex = Int((broadbandLevel - histMinDB) * 10.0)
            if histIndex >= 0 && histIndex < lafHistogram.count {
                lafHistogram[histIndex] += 1
                lafTotalCounts += 1
            }
            
            currentTaktMax = max(currentTaktMax, broadbandLevel)
            if recordingDuration - lastTaktTime >= 5.0 {
                taktValues.append(currentTaktMax)
                currentTaktMax = -1000.0
                lastTaktTime = recordingDuration
            }
            
            let levels: [String: Float] = [
                "LAF": 10.0 * log10(lafEnergy + 1e-12),
                "LAS": 10.0 * log10(lasEnergy + 1e-12),
                "LCF": 10.0 * log10(lcfEnergy + 1e-12),
                "LCS": 10.0 * log10(lcsEnergy + 1e-12),
                "LZF": 10.0 * log10(lzfEnergy + 1e-12),
                "LZS": 10.0 * log10(lzsEnergy + 1e-12),
                "LAeq": laeqCount > 0 ? Float(10.0 * log10(laeqAccumulator / Double(laeqCount) + 1e-12)) : -120.0,
                "LAFmin": lafMin,
                "LAFmax": lafMax,
                "LCpeak": lcPeakHold,
                "LAFT5": currentTaktMax,
            ]

            if debugPrintCounter % 240 == 0 {
                print("[AudioEngine] Broadband Level: \(String(format: "%.1f", broadbandLevel)) dB")
            }

            let spectrogramData = SpectrogramData(
                frequencies: bandFreqs,
                magnitudes: smoothedMagnitudes,
                broadbandLevel: broadbandLevel,
                levels: calculateExtendedLevels(baseLevels: levels),
                sampleRate: sampleRate
            )

            DispatchQueue.main.async {
                if let startTime = self.recordingStartTime {
                    self.recordingDuration = Date().timeIntervalSince(startTime)
                }

                self.currentSpectrogramData = spectrogramData
                
                self.currentOctaveBands = octaveBands
                self.currentSpectrum = spectrum
                self.currentPeakLevel = peakDB
                self.currentLevel = broadbandLevel
                
                self.maxLevel = max(self.maxLevel, broadbandLevel)
                if broadbandLevel > -110 {
                    self.minLevel = min(self.minLevel == 0 ? broadbandLevel : self.minLevel, broadbandLevel)
                }
                
                self.levelHistory.append(broadbandLevel)
                if self.levelHistory.count > self.maxHistorySize {
                    self.levelHistory.removeFirst(self.levelHistory.count - self.maxHistorySize)
                }
                
                let now = Date().timeIntervalSince1970
                if now - self.lastWatchUpdate > 0.1 {
                    WatchConnectivityManager.shared.sendSpectrogramData(spectrogramData)
                    self.lastWatchUpdate = now
                }
            }
            
            sampleBuffer.removeFirst(scrollSpeed.rawValue)
        }
    }
    
    // MARK: - Bandstop Filter Application
    
    /// Wendet alle aktiven Bandstop-Filter auf die FFT-Magnitudes an
    private func applyBandstopFilters(frequencies: [Float], magnitudes: [Float]) -> [Float] {
        guard !bandstopFilterManager.enabledFilters.isEmpty else {
            return magnitudes // Keine Filter aktiv
        }
        
        var filtered = magnitudes
        
        for (i, freq) in frequencies.enumerated() {
            let attenuation = bandstopFilterManager.attenuationFactor(for: freq)
            
            // Attenuation: 0 = vollständig gedämpft, 1 = nicht gedämpft
            // Wir dämpfen in dB-Skala
            if attenuation < 1.0 {
                // Konvertiere zu Linear, dämpfe, zurück zu dB
                let linearMag = pow(10.0, filtered[i] / 20.0)
                let attenuatedLinear = linearMag * attenuation
                filtered[i] = 20.0 * log10(attenuatedLinear + 1e-9)
            }
        }
        
        return filtered
    }
    
    private func calculateExtendedLevels(baseLevels: [String: Float]) -> [String: Float] {
        var levels = baseLevels
        
        if lafTotalCounts > 0 {
            levels["LAF5"] = calculatePercentile(targetPercentage: 0.05)
            levels["LAF95"] = calculatePercentile(targetPercentage: 0.95)
        } else {
            levels["LAF5"] = -120.0
            levels["LAF95"] = -120.0
        }
        
        if !taktValues.isEmpty {
            let sumEnergy = taktValues.reduce(0.0) { $0 + pow(10.0, Double($1) / 10.0) }
            levels["LAFTeq"] = Float(10.0 * log10(sumEnergy / Double(taktValues.count) + 1e-12))
        } else {
            levels["LAFTeq"] = currentTaktMax > -1000 ? currentTaktMax : -120.0
        }
        
        return levels
    }
    
    private func calculatePercentile(targetPercentage: Double) -> Float {
        let targetCount = Int(Double(lafTotalCounts) * targetPercentage)
        var currentCount = 0
        for i in stride(from: lafHistogram.count - 1, through: 0, by: -1) {
            currentCount += lafHistogram[i]
            if currentCount >= targetCount {
                return histMinDB + Float(i) / 10.0
            }
        }
        return histMinDB
    }

    private func performFFT(on samples: [Float]) -> (frequencies: [Float], magnitudes: [Float]) {

        vDSP_vclr(&imagIn, 1, vDSP_Length(fftSize))

        let maxIndex = min(samples.count, fftSize)
        for i in 0..<maxIndex {
            realIn[i] = samples[i] * window[i]
        }

        vDSP_DFT_Execute(fftSetup,
                         realIn, imagIn,
                         &realOut, &imagOut)
        
        realOut.withUnsafeMutableBufferPointer { realPtr in
            imagOut.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvabs(&splitComplex, 1, &fftMagnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        let normalization = 2.0 / Float(fftSize)
        var scale = normalization * pow(10.0, gainBoost / 20.0)
        vDSP_vsmul(fftMagnitudes, 1, &scale, &fftMagnitudes, 1, vDSP_Length(fftMagnitudes.count))
        
        var epsilon: Float = 1e-9
        vDSP_vsadd(fftMagnitudes, 1, &epsilon, &fftMagnitudes, 1, vDSP_Length(fftMagnitudes.count))
        var reference: Float = 1.0
        var dbMagnitudes = [Float](repeating: 0, count: fftMagnitudes.count)
        vDSP_vdbcon(fftMagnitudes, 1, &reference, &dbMagnitudes, 1, vDSP_Length(fftMagnitudes.count), 1)

        let nyquist = Float(sampleRate / 2.0)
        let freqResolution = nyquist / Float(dbMagnitudes.count)
        let frequencies = (0..<dbMagnitudes.count).map { Float($0) * freqResolution }

        if frequencyWeighting != .z {
            var weightingOffsets = [Float](repeating: 0.0, count: frequencies.count)
            
            for (i, f) in frequencies.enumerated() {
                let f2 = f * f
                var offset: Float = 0.0
                
                if frequencyWeighting == .a {
                    let num = 12194.0 * 12194.0 * f2 * f2
                    let den = (f2 + 20.6 * 20.6) * sqrt((f2 + 107.7 * 107.7) * (f2 + 737.9 * 737.9)) * (f2 + 12194.0 * 12194.0)
                    if den > 0 {
                        offset = 20.0 * log10(num / den) + 2.0
                    }
                } else if frequencyWeighting == .c {
                    let num = 12194.0 * 12194.0 * f2
                    let den = (f2 + 20.6 * 20.6) * (f2 + 12194.0 * 12194.0)
                    if den > 0 {
                        offset = 20.0 * log10(num / den) + 0.06
                    }
                }
                
                weightingOffsets[i] = Float(offset)
            }
            
            vDSP_vadd(dbMagnitudes, 1, weightingOffsets, 1, &dbMagnitudes, 1, vDSP_Length(dbMagnitudes.count))
        }

        return (frequencies, dbMagnitudes)
    }

    private func aggregateByBinningFactor(
        frequencies: [Float],
        magnitudes: [Float]
    ) -> (frequencies: [Float], magnitudes: [Float]) {

        guard binningFactor > 0 else {
            return (frequencies, magnitudes)
        }

        if binningFactor == 1 {
            return (frequencies, magnitudes)
        }

        var bandFrequencies: [Float] = []
        var bandMagnitudes: [Float] = []

        var i = 0
        while i < frequencies.count {
            let endIndex = min(i + binningFactor, frequencies.count)
            let binCount = endIndex - i

            let centerFreq = frequencies[i...endIndex-1].reduce(0, +) / Float(binCount)
            bandFrequencies.append(centerFreq)

            let centerMag = magnitudes[i..<endIndex].reduce(0, +) / Float(binCount)
            bandMagnitudes.append(centerMag)

            i = endIndex
        }

        return (bandFrequencies, bandMagnitudes)
    }

    private func temporalSmoothing(currentMagnitudes: [Float]) -> [Float] {
        guard !previousBandMagnitudes.isEmpty,
              previousBandMagnitudes.count == currentMagnitudes.count else {
            previousBandMagnitudes = currentMagnitudes
            return currentMagnitudes
        }

        var smoothed = [Float](repeating: 0, count: currentMagnitudes.count)

        for i in 0..<currentMagnitudes.count {
            smoothed[i] =
                temporalSmoothingFactor * previousBandMagnitudes[i] +
                (1 - temporalSmoothingFactor) * currentMagnitudes[i]
        }

        previousBandMagnitudes = smoothed
        return smoothed
    }
    
    private func calculateOctaveBands(frequencies: [Float], magnitudes: [Float]) -> [Float] {
        let centerFreqs: [Float] = [
            20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800,
            1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
        ]
        
        var bands = [Float](repeating: -120.0, count: centerFreqs.count)
        
        for (i, center) in centerFreqs.enumerated() {
            let lower = center * 0.89
            let upper = center * 1.12
            
            let nyquist = Float(sampleRate / 2.0)
            let resolution = nyquist / Float(magnitudes.count)
            
            let startIdx = Int(lower / resolution)
            let endIdx = Int(upper / resolution)
            
            if startIdx < magnitudes.count {
                let safeEnd = min(endIdx, magnitudes.count - 1)
                if startIdx <= safeEnd {
                    let bandMax = magnitudes[startIdx...safeEnd].max() ?? -120.0
                    bands[i] = bandMax
                }
            }
        }
        return bands
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
        let nyquist = Float(sampleRate / 2.0)
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

        let (bandFreqs, bandMags) = aggregateByBinningFactor(
            frequencies: dummyFrequencies,
            magnitudes: dummyMagnitudes
        )

        let smoothed = temporalSmoothing(currentMagnitudes: bandMags)

        let data = SpectrogramData(
            frequencies: bandFreqs,
            magnitudes: smoothed,
            broadbandLevel: -40.0 + Float.random(in: -5...5),
            levels: ["LAF": -40.0 + Float.random(in: -5...5)],
            sampleRate: sampleRate
        )

        DispatchQueue.main.async {
            if let startTime = self.recordingStartTime {
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
            self.currentSpectrogramData = data
            WatchConnectivityManager.shared.sendSpectrogramData(data)
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
