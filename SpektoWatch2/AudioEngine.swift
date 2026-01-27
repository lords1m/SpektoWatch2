import Foundation
import AVFoundation
import Accelerate
import Combine

enum TimeWeighting: String, CaseIterable {
    case fast = "Fast"
    case slow = "Slow"
}

enum FrequencyWeighting: String, CaseIterable {
    case z = "Linear (Z)"
    case a = "A-Weighting"
    case c = "C-Weighting"
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
    private let fftSize: Int = 8192 // Maximale Frequenzauflösung (für mehr Details)
    private let tapBlockSize: AVAudioFrameCount = 512 // Sehr hohe Update-Rate (~86 FPS)
    private var sampleBuffer: [Float] = []
    private let fftSetup: vDSP_DFT_Setup
    private let sampleRate: Double = 44100.0
    private var dummyDataTimer: Timer?
    private var isUsingDummyData = false
    private var gainBoost: Float = 10.0 // Erhöht für bessere Sichtbarkeit normaler Signale
    private var hasLoggedSilence = false
    private var debugPrintCounter = 0
    private var lastWatchUpdate: TimeInterval = 0
    private let maxHistorySize = 1000

    // Recording time tracking
    private var recordingStartTime: Date?
    private var audioFile: AVAudioFile?
    var lastRecordingURL: URL?

    @Published var recordingDuration: TimeInterval = 0.0
    @Published var engineStatus: EngineStatus = .idle
    @Published var currentSpectrogramData: SpectrogramData?
    @Published var currentLevel: Float = -120.0
    @Published var levelHistory: [Float] = []
    @Published var currentPeakLevel: Float = -120.0
    @Published var currentStereoPhase: Float = 1.0 // +1 = Mono/In-Phase, -1 = Out-of-Phase, 0 = Stereo/Uncorrelated
    @Published var currentOctaveBands: [Float] = Array(repeating: -120.0, count: 31) // 1/3 Octave Bands
    @Published var currentSpectrum: [Float] = [] // Raw FFT for Frequency Display

    @Published var selectedTimeWeighting: TimeWeighting = .fast
    @Published var selectedFrequencyWeighting: FrequencyWeighting = .a
    @Published var scrollSpeed: ScrollSpeed = .fast

    // Level meter
    private var smoothedLevel: Float = -120.0

    // Level calculations (Energy accumulators)
    private var lafEnergy: Float = 1e-12
    private var lasEnergy: Float = 1e-12
    private var lcfEnergy: Float = 1e-12
    private var lcsEnergy: Float = 1e-12
    private var lzfEnergy: Float = 1e-12
    private var lzsEnergy: Float = 1e-12
    
    // Extended Metrics State
    private var laeqAccumulator: Double = 0.0
    private var laeqCount: Int = 0
    private var lafMin: Float = 1000.0
    private var lafMax: Float = -1000.0
    private var lcPeakHold: Float = -120.0
    
    // Histogram for Percentiles (Range -130dB to +10dB, 0.1dB resolution)
    private var lafHistogram = [Int](repeating: 0, count: 1401)
    private var lafTotalCounts: Int = 0
    private let histMinDB: Float = -130.0
    
    // Taktmaximalpegel (LAFT)
    private var currentTaktMax: Float = -1000.0
    private var lastTaktTime: TimeInterval = 0
    private var taktValues: [Float] = []
    
    // Microphone Selection
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

    // === Flexible Bandbildungs-Parameter ===

    /// Wie viele FFT-Bins werden zu einem angezeigten Balken zusammengefasst?
    /// 1 = kein Binning (volle FFT-Auflösung)
    /// 4 = alle 4 Bins werden gemittelt (breitere Balken)
    /// 16 = alle 16 Bins werden gemittelt (noch breiter)
    private let binningFactor: Int = 2

    /// 0 = keine Glättung, 0.7..0.9 = recht stark verwischt
    private var temporalSmoothingFactor: Float = 0.0

    /// Zwischenspeicher für zeitliche Glättung
    private var previousBandMagnitudes: [Float] = []

    // PERFORMANCE: Wiederverwendbare Puffer um Allokationen zu vermeiden
    private var realIn: [Float]
    private var imagIn: [Float]
    private var realOut: [Float]
    private var imagOut: [Float]
    private var window: [Float]
    private var fftMagnitudes: [Float]
    
    // Precomputed Weighting Curves (Linear scale)
    private var aWeights: [Float] = []
    private var cWeights: [Float] = []

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
        
        // Puffer einmalig initialisieren
        realIn = [Float](repeating: 0, count: fftSize)
        imagIn = [Float](repeating: 0, count: fftSize)
        realOut = [Float](repeating: 0, count: fftSize)
        imagOut = [Float](repeating: 0, count: fftSize)
        window = [Float](repeating: 0, count: fftSize)
        fftMagnitudes = [Float](repeating: 0, count: fftSize / 2)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        
        // Precompute weighting curves
        precomputeWeightingCurves()
    }

    deinit {
        vDSP_DFT_DestroySetup(fftSetup)
    }

    func setTimeWeighting(_ weighting: TimeWeighting) {
        selectedTimeWeighting = weighting
        // Update-Rate ist jetzt ca. 11.6ms (512 / 44100)
        // Reduzierte Werte um "Schmieren" zu verhindern:
        // Fast -> 0.5 (sehr reaktiv), Slow -> 0.9 (ruhiger)
        temporalSmoothingFactor = (weighting == .fast) ? 0.5 : 0.9
    }

    func setFrequencyWeighting(_ weighting: FrequencyWeighting) {
        selectedFrequencyWeighting = weighting
    }

    func setGainBoost(_ gain: Float) {
        gainBoost = gain
    }

    /// Ändere die Breite der angezeigten Bänder (binningFactor)
    /// - Parameter factor: 1 = schmal, 4 = mittel, 16+ = breit
    func setBinningFactor(_ factor: Int) {
        // Hinweis: binningFactor ist private let, daher müsste es auf private var geändert werden
        // wenn du das zur Laufzeit ändern möchtest
    }

    /// Ändere die zeitliche Glättung
    /// - Parameter factor: 0 = keine, 1 = maximale Glättung
    func setSmoothingFactor(_ factor: Float) {
        // Hinweis: analog zu binningFactor
    }
    
    private func precomputeWeightingCurves() {
        let nyquist = Float(sampleRate / 2.0)
        let freqResolution = nyquist / Float(fftSize / 2)
        
        aWeights = [Float](repeating: 0.0, count: fftSize / 2)
        cWeights = [Float](repeating: 0.0, count: fftSize / 2)
        
        for i in 0..<(fftSize / 2) {
            let f = Float(i) * freqResolution
            let f2 = f * f
            
            // A-Weighting
            let aNum = 12194.0 * 12194.0 * f2 * f2
            let aDen = (f2 + 20.6 * 20.6) * sqrt((f2 + 107.7 * 107.7) * (f2 + 737.9 * 737.9)) * (f2 + 12194.0 * 12194.0)
            var aGain: Float = 0.0
            if aDen > 0 {
                let mag = aNum / aDen
                // Add 2.0 dB gain offset for A-weighting standard
                aGain = Float(mag * pow(10.0, 2.0 / 20.0))
            }
            aWeights[i] = aGain
            
            // C-Weighting
            let cNum = 12194.0 * 12194.0 * f2
            let cDen = (f2 + 20.6 * 20.6) * (f2 + 12194.0 * 12194.0)
            var cGain: Float = 0.0
            if cDen > 0 {
                let mag = cNum / cDen
                // Add 0.06 dB gain offset for C-weighting standard
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

        // Reset history
        DispatchQueue.main.async {
            self.levelHistory.removeAll()
            self.currentLevel = -120.0
            self.smoothedLevel = -120.0
            
            // Reset Metrics
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
            
            // Berechtigung prüfen
            if audioSession.recordPermission == .undetermined {
                audioSession.requestRecordPermission { [weak self] granted in
                    if granted { DispatchQueue.main.async { self?.startRecording() } }
                }
                return
            }
            if audioSession.recordPermission == .denied {
                print("[AudioEngine] Error: Microphone permission denied. Please enable in settings.")
                engineStatus = .error("Microphone permission denied")
                return
            }

            try audioSession.setCategory(.record, mode: .measurement, options: [])
            
            // LATENCY FIX: Set preferred buffer duration to match tapBlockSize (512 samples = ~11.6ms)
            // This ensures callbacks happen frequently (low latency) and at the expected 86Hz rate
            try audioSession.setPreferredIOBufferDuration(Double(tapBlockSize) / sampleRate)

            if audioSession.isInputGainSettable {
                try audioSession.setInputGain(1.0)
            }

            try audioSession.setActive(true)
            
            // Configure Microphone Data Source (Front/Back/Bottom)
            if let inputs = audioSession.availableInputs,
               let builtInMic = inputs.first(where: { $0.portType == .builtInMic }) {
                try audioSession.setPreferredInput(builtInMic)
                
                // Update available sources
                DispatchQueue.main.async {
                    self.availableDataSources = builtInMic.dataSources ?? []
                    
                    // Select default if none selected
                    if self.selectedDataSource == nil {
                        self.selectedDataSource = audioSession.inputDataSource ?? self.availableDataSources.first
                    }
                }
                
                // Apply selection
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

            // Setup Audio File for Recording
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
        audioFile = nil // Close file
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
        
        // Clear history on stop
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
            
            // Set stereo if supported
            if let supported = source.supportedPolarPatterns, supported.contains(.stereo) {
                try? source.setPreferredPolarPattern(.stereo)
            }
            
            // Update selectedDataSource
            DispatchQueue.main.async {
                if self.selectedDataSource?.dataSourceID != source.dataSourceID {
                    self.selectedDataSource = source
                }
            }
        }
    }

    // MARK: - Audio Processing

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        
        // Write to file
        if let audioFile = audioFile {
            try? audioFile.write(from: buffer)
        }
        
        let channels = Int(buffer.format.channelCount)
        
        // Channel 0 (Left/Mono)
        let newSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        
        // Stereo Phase Calculation
        var phase: Float = 1.0
        if channels > 1 {
            let rightSamples = Array(UnsafeBufferPointer(start: channelData[1], count: frameCount))
            // Simple correlation: sum(L*R) / sqrt(sum(L^2)*sum(R^2))
            var dotProd: Float = 0
            var sumSqL: Float = 0
            var sumSqR: Float = 0
            vDSP_dotpr(newSamples, 1, rightSamples, 1, &dotProd, vDSP_Length(frameCount))
            vDSP_svesq(newSamples, 1, &sumSqL, vDSP_Length(frameCount))
            vDSP_svesq(newSamples, 1, &sumSqR, vDSP_Length(frameCount))
            phase = dotProd / (sqrt(sumSqL * sumSqR) + 1e-9)
        }

        processSamples(newSamples)
        
        // Update Phase on Main Thread
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
        // DEBUG: Signalstärke prüfen (RMS)
        var rms: Float = 0
        // Prüfe nur die neuen Samples auf Stille
        vDSP_rmsqv(newSamples, 1, &rms, vDSP_Length(newSamples.count))
        let signalDB = 20 * log10(rms + 1e-9) // + Epsilon um log(0) zu vermeiden
        let peakVal = newSamples.max() ?? 0
        let peakDB = 20 * log10(abs(peakVal) + 1e-9)
        self.lcPeakHold = max(self.lcPeakHold, peakDB) // Using Z-Peak as approximation for C-Peak

        // DEBUG: Signalstärke ausgeben (gedrosselt)
        debugPrintCounter += 1
        if debugPrintCounter % 240 == 0 { // Seltener loggen da 8x mehr Updates
            let minSample = newSamples.min() ?? 0
            let maxSample = newSamples.max() ?? 0
            print("[AudioEngine] Input RMS: \(String(format: "%.1f", signalDB)) dB, Samples: [\(String(format: "%.3f", minSample)) ... \(String(format: "%.3f", maxSample))]")
        }
        
        if signalDB < -120 {
            if !hasLoggedSilence {
                print("[AudioEngine] WARNING: Audio buffer silent/empty: \(String(format: "%.1f", signalDB)) dB (Check permissions)")
                hasLoggedSilence = true
            }
        }

        // Sliding Window: Samples sammeln
        sampleBuffer.append(contentsOf: newSamples)
        
        // Process all complete windows
        while sampleBuffer.count >= fftSize {
            let samples = Array(sampleBuffer.prefix(fftSize))

            // 1. FFT
            let fftResult = performFFT(on: samples)

            // DEBUG: FFT Output Range prüfen
            if debugPrintCounter % 240 == 0 {
                let minMag = fftResult.magnitudes.min() ?? 0
                let maxMag = fftResult.magnitudes.max() ?? 0
                print("[AudioEngine] FFT Processed (dB): min=\(String(format: "%.1f", minMag)), max=\(String(format: "%.1f", maxMag))")
            }
            
            // Calculate 1/3 Octave Bands
            let octaveBands = calculateOctaveBands(frequencies: fftResult.frequencies, magnitudes: fftResult.magnitudes)
            let spectrum = fftResult.magnitudes // Raw spectrum

            // 2. Freie Aggregation mit binningFactor
            let (bandFreqs, bandMags) = aggregateByBinningFactor(
                frequencies: fftResult.frequencies,
                magnitudes: fftResult.magnitudes
            )

            // 3. Zeitliche Glättung (Verwischung)
            let smoothedMagnitudes = temporalSmoothing(currentMagnitudes: bandMags)

            // 4. Calculate Broadband Levels (A, C, Z / Fast, Slow)
            // Calculate instantaneous energy for this frame
            var energyZ: Float = 0.0
            var energyA: Float = 0.0
            var energyC: Float = 0.0
            
            // fftMagnitudes contains linear magnitudes (scaled) from performFFT
            // We use them directly to avoid double dB conversion
            for i in 0..<fftMagnitudes.count {
                let magSq = fftMagnitudes[i] * fftMagnitudes[i]
                energyZ += magSq
                energyA += magSq * aWeights[i] * aWeights[i]
                energyC += magSq * cWeights[i] * cWeights[i]
            }
            
            // Time Constants
            let dt = Float(scrollSpeed.rawValue) / Float(sampleRate)
            let alphaFast = 1.0 - exp(-dt / 0.125) // 125ms
            let alphaSlow = 1.0 - exp(-dt / 1.0)   // 1s
            
            // Update Energies
            lafEnergy = (1.0 - alphaFast) * lafEnergy + alphaFast * energyA
            lasEnergy = (1.0 - alphaSlow) * lasEnergy + alphaSlow * energyA
            
            lcfEnergy = (1.0 - alphaFast) * lcfEnergy + alphaFast * energyC
            lcsEnergy = (1.0 - alphaSlow) * lcsEnergy + alphaSlow * energyC
            
            lzfEnergy = (1.0 - alphaFast) * lzfEnergy + alphaFast * energyZ
            lzsEnergy = (1.0 - alphaSlow) * lzsEnergy + alphaSlow * energyZ
            
            // --- Extended Metrics Calculation ---
            
            // LAeq (Integrate instantaneous A-weighted energy)
            laeqAccumulator += Double(energyA)
            laeqCount += 1
            
            // LAF based metrics
            let broadbandLevel = 10.0 * log10(lafEnergy + 1e-12)
            
            // Min/Max
            lafMin = min(lafMin, broadbandLevel)
            lafMax = max(lafMax, broadbandLevel)
            
            // Histogram for Percentiles
            let histIndex = Int((broadbandLevel - histMinDB) * 10.0)
            if histIndex >= 0 && histIndex < lafHistogram.count {
                lafHistogram[histIndex] += 1
                lafTotalCounts += 1
            }
            
            // Taktmaximalpegel (LAFT5)
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
                // Percentiles and LAFTeq are calculated on demand in UI or periodically to save CPU here
                // but we can pass raw data or compute them if needed. For now, let's compute them here for simplicity.
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
                self.currentLevel = broadbandLevel // Use LAF as main level
                
                self.levelHistory.append(broadbandLevel)
                if self.levelHistory.count > self.maxHistorySize {
                    self.levelHistory.removeFirst(self.levelHistory.count - self.maxHistorySize)
                }
                
                // PERFORMANCE: Throttle Watch updates to ~10 FPS to reduce main thread latency
                let now = Date().timeIntervalSince1970
                if now - self.lastWatchUpdate > 0.1 {
                    WatchConnectivityManager.shared.sendSpectrogramData(spectrogramData)
                    self.lastWatchUpdate = now
                }
            }
            
            // Advance window by hop size
            sampleBuffer.removeFirst(scrollSpeed.rawValue)
        }
    }
    
    private func calculateExtendedLevels(baseLevels: [String: Float]) -> [String: Float] {
        var levels = baseLevels
        
        // Percentiles
        if lafTotalCounts > 0 {
            // LAF5 (5% percentile - exceeded 5% of time -> top 5%)
            levels["LAF5"] = calculatePercentile(targetPercentage: 0.05)
            // LAF95 (95% percentile - exceeded 95% of time -> top 95% / bottom 5%)
            levels["LAF95"] = calculatePercentile(targetPercentage: 0.95)
        } else {
            levels["LAF5"] = -120.0
            levels["LAF95"] = -120.0
        }
        
        // LAFTeq
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
        // Iterate from top (high dB) to bottom for "exceeded N% of time"
        // LAF5 means the level exceeded 5% of the time (so it's a high level)
        for i in stride(from: lafHistogram.count - 1, through: 0, by: -1) {
            currentCount += lafHistogram[i]
            if currentCount >= targetCount {
                return histMinDB + Float(i) / 10.0
            }
        }
        return histMinDB
    }

    private func performFFT(on samples: [Float]) -> (frequencies: [Float], magnitudes: [Float]) {

        // Reset imaginary parts (wichtig, da Puffer wiederverwendet werden)
        vDSP_vclr(&imagIn, 1, vDSP_Length(fftSize))

        // Copy and window the samples
        let maxIndex = min(samples.count, fftSize)
        for i in 0..<maxIndex {
            realIn[i] = samples[i] * window[i]
        }

        vDSP_DFT_Execute(fftSetup,
                         realIn, imagIn,
                         &realOut, &imagOut)

        // Compute magnitude spectrum
        // Nutze Member-Variable statt Neu-Allokation
        
        // Create DSPSplitComplex structure for magnitude calculation
        realOut.withUnsafeMutableBufferPointer { realPtr in
            imagOut.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvabs(&splitComplex, 1, &fftMagnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        // Apply gain boost and convert to dB
        // FIX: Normalisierung (2/N) um korrekte Amplitude zu erhalten
        let normalization = 2.0 / Float(fftSize)
        var scale = normalization * pow(10.0, gainBoost / 20.0)
        vDSP_vsmul(fftMagnitudes, 1, &scale, &fftMagnitudes, 1, vDSP_Length(fftMagnitudes.count))
        
        var epsilon: Float = 1e-9
        vDSP_vsadd(fftMagnitudes, 1, &epsilon, &fftMagnitudes, 1, vDSP_Length(fftMagnitudes.count))
        var reference: Float = 1.0
        // Wir nutzen fftMagnitudes direkt weiter für die dB Konversion (In-Place ist bei vdbcon nicht immer sicher, aber hier nutzen wir es als Source für die Rückgabe, wir brauchen aber einen dB Puffer)
        // Da wir fftMagnitudes als Member haben, nutzen wir es als Source und erstellen ein temporäres Array für die Rückgabe oder nutzen einen zweiten Puffer.
        // Um Allocations zu sparen, wäre ein dbBuffer gut. Aber die Rückgabe der Funktion erwartet [Float].
        // Swift Arrays sind COW. Wenn wir fftMagnitudes zurückgeben, wird kopiert, sobald wir es im nächsten Frame ändern.
        // Wir machen die dB Konversion direkt in einen neuen Puffer für die Rückgabe, das ist der saubere Weg für die API.
        var dbMagnitudes = [Float](repeating: 0, count: fftMagnitudes.count)
        vDSP_vdbcon(fftMagnitudes, 1, &reference, &dbMagnitudes, 1, vDSP_Length(fftMagnitudes.count), 1)

        // Frequency axis
        let nyquist = Float(sampleRate / 2.0)
        let freqResolution = nyquist / Float(dbMagnitudes.count)
        let frequencies = (0..<dbMagnitudes.count).map { Float($0) * freqResolution }

        // Apply Frequency Weighting
        if selectedFrequencyWeighting != .z {
            var weightingOffsets = [Float](repeating: 0.0, count: frequencies.count)
            
            for (i, f) in frequencies.enumerated() {
                let f2 = f * f
                var offset: Float = 0.0
                
                if selectedFrequencyWeighting == .a {
                    // A-Weighting Formula
                    let num = 12194.0 * 12194.0 * f2 * f2
                    let den = (f2 + 20.6 * 20.6) * sqrt((f2 + 107.7 * 107.7) * (f2 + 737.9 * 737.9)) * (f2 + 12194.0 * 12194.0)
                    if den > 0 {
                        offset = 20.0 * log10(num / den) + 2.0
                    }
                } else if selectedFrequencyWeighting == .c {
                    // C-Weighting Formula
                    let num = 12194.0 * 12194.0 * f2
                    let den = (f2 + 20.6 * 20.6) * (f2 + 12194.0 * 12194.0)
                    if den > 0 {
                        offset = 20.0 * log10(num / den) + 0.06
                    }
                }
                
                weightingOffsets[i] = Float(offset)
            }
            
            // Add offsets to dbMagnitudes
            vDSP_vadd(dbMagnitudes, 1, weightingOffsets, 1, &dbMagnitudes, 1, vDSP_Length(dbMagnitudes.count))
        }

        return (frequencies, dbMagnitudes)
    }

    // MARK: - Freie Aggregation mit binningFactor

    /// Aggregiert FFT-Bins frei nach Wunsch
    /// - Parameter binningFactor: 1 = keine Aggregation, 4 = je 4 Bins zusammenfassen, etc.
    private func aggregateByBinningFactor(
        frequencies: [Float],
        magnitudes: [Float]
    ) -> (frequencies: [Float], magnitudes: [Float]) {

        guard binningFactor > 0 else {
            return (frequencies, magnitudes)
        }

        // Binning = 1: keine Änderung
        if binningFactor == 1 {
            return (frequencies, magnitudes)
        }

        var bandFrequencies: [Float] = []
        var bandMagnitudes: [Float] = []

        var i = 0
        while i < frequencies.count {
            let endIndex = min(i + binningFactor, frequencies.count)
            let binCount = endIndex - i

            // Mittlere Frequenz dieses Bins
            let centerFreq = frequencies[i...endIndex-1].reduce(0, +) / Float(binCount)
            bandFrequencies.append(centerFreq)

            // Mittlere Magnitude dieses Bins
            let centerMag = magnitudes[i..<endIndex].reduce(0, +) / Float(binCount)
            bandMagnitudes.append(centerMag)

            i = endIndex
        }

        return (bandFrequencies, bandMagnitudes)
    }

    // MARK: - Zeitliche Glättung (Verwischung)

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
    
    // MARK: - 1/3 Octave Band Calculation
    
    private func calculateOctaveBands(frequencies: [Float], magnitudes: [Float]) -> [Float] {
        // Standard 1/3 Octave Center Frequencies
        let centerFreqs: [Float] = [
            20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800,
            1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
        ]
        
        var bands = [Float](repeating: -120.0, count: centerFreqs.count)
        
        // Simple mapping: Find max magnitude in the band range
        // Band edges are approx +/- 11% of center freq
        for (i, center) in centerFreqs.enumerated() {
            let lower = center * 0.89
            let upper = center * 1.12
            
            // Find indices in FFT
            // Assuming linear frequency distribution from 0 to Nyquist
            // Index = Freq / Resolution
            // Resolution = Nyquist / (magnitudes.count)
            let nyquist = Float(sampleRate / 2.0)
            let resolution = nyquist / Float(magnitudes.count)
            
            let startIdx = Int(lower / resolution)
            let endIdx = Int(upper / resolution)
            
            if startIdx < magnitudes.count {
                let safeEnd = min(endIdx, magnitudes.count - 1)
                if startIdx <= safeEnd {
                    // Energy Sum (Power)
                    var energySum: Float = 0.0
                    for j in startIdx...safeEnd {
                        energySum += pow(10.0, magnitudes[j] / 10.0)
                    }
                    // Average energy in band or Sum? Standard is Sum for bands.
                    // But magnitudes are already somewhat normalized. Let's take Max for peak visualization or Sum for energy.
                    // Let's use Max for cleaner visualization in this context, or Sum for correct physics.
                    // Using Max to avoid "noise accumulation" in display for now.
                    // Actually, let's use a safe max to represent the peak in that band.
                    let bandMax = magnitudes[startIdx...safeEnd].max() ?? -120.0
                    bands[i] = bandMax
                }
            }
        }
        return bands
    }

    // MARK: - Dummy-Daten

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

        // Dummy-FFT-Daten erzeugen
        let dummyFFTLength = 512
        let nyquist = Float(sampleRate / 2.0)
        let freqResolution = nyquist / Float(dummyFFTLength)

        var dummyFrequencies = [Float]()
        var dummyMagnitudes = [Float]()

        for i in 0..<dummyFFTLength {
            let freq = Float(i) * freqResolution
            dummyFrequencies.append(freq)

            // Ein paar wandernde Sinus-Peaks
            let phase1 = Float(t) * 0.3 + Float(i) * 0.01
            let phase2 = Float(t) * 0.5 + Float(i) * 0.02
            let peak1 = sin(phase1) * 15
            let peak2 = sin(phase2) * 10
            let noise = Float.random(in: -5...0)

            let mag = peak1 + peak2 + noise - 40
            dummyMagnitudes.append(mag)
        }

        // Aggregation anwenden
        let (bandFreqs, bandMags) = aggregateByBinningFactor(
            frequencies: dummyFrequencies,
            magnitudes: dummyMagnitudes
        )

        // Glättung anwenden
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
}
