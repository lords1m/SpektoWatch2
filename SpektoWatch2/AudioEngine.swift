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

    // Recording time tracking
    private var recordingStartTime: Date?

    @Published var recordingDuration: TimeInterval = 0.0
    @Published var currentSpectrogramData: SpectrogramData?

    @Published var selectedTimeWeighting: TimeWeighting = .fast
    @Published var selectedFrequencyWeighting: FrequencyWeighting = .a
    @Published var scrollSpeed: ScrollSpeed = .fast

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

    func startRecording() {
        recordingStartTime = Date()
        recordingDuration = 0.0
        hasLoggedSilence = false

        #if targetEnvironment(simulator)
        print("Running on Simulator - using dummy audio data")
        startDummyDataGeneration()
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
                print("❌ Mikrofon-Berechtigung verweigert. Bitte in Einstellungen aktivieren.")
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

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
                print("Invalid audio format - falling back to dummy data")
                startDummyDataGeneration()
                return
            }

            inputNode.installTap(onBus: 0, bufferSize: tapBlockSize, format: recordingFormat) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer)
            }

            try audioEngine.start()
        } catch {
            print("Audio engine start error: \(error)")
            print("Falling back to dummy data")
            startDummyDataGeneration()
        }
        #endif
    }

    func stopRecording() {
        recordingStartTime = nil

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
    }

    // MARK: - Audio Processing

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let frameCount = Int(buffer.frameLength)
        let newSamples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        
        // DEBUG: Signalstärke prüfen (RMS)
        var rms: Float = 0
        // Prüfe nur die neuen Samples auf Stille
        vDSP_rmsqv(newSamples, 1, &rms, vDSP_Length(newSamples.count))
        let signalDB = 20 * log10(rms + 1e-9) // + Epsilon um log(0) zu vermeiden

        // DEBUG: Signalstärke ausgeben (gedrosselt)
        debugPrintCounter += 1
        if debugPrintCounter % 240 == 0 { // Seltener loggen da 8x mehr Updates
            print("🎤 Signalstärke: \(String(format: "%.1f", signalDB)) dB")
        }
        
        if signalDB < -120 {
            if !hasLoggedSilence {
                print("⚠️ Audio-Buffer ist still/leer: \(String(format: "%.1f", signalDB)) dB (Prüfe Berechtigungen)")
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
                print("📊 FFT Output (dB): min=\(String(format: "%.1f", minMag)), max=\(String(format: "%.1f", maxMag))")
            }

            // 2. Freie Aggregation mit binningFactor
            let (bandFreqs, bandMags) = aggregateByBinningFactor(
                frequencies: fftResult.frequencies,
                magnitudes: fftResult.magnitudes
            )

            // 3. Zeitliche Glättung (Verwischung)
            let smoothedMagnitudes = temporalSmoothing(currentMagnitudes: bandMags)

            let spectrogramData = SpectrogramData(
                frequencies: bandFreqs,
                magnitudes: smoothedMagnitudes,
                sampleRate: sampleRate
            )

            DispatchQueue.main.async {
                if let startTime = self.recordingStartTime {
                    self.recordingDuration = Date().timeIntervalSince(startTime)
                }

                self.currentSpectrogramData = spectrogramData
                
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

    private func performFFT(on samples: [Float]) -> (frequencies: [Float], magnitudes: [Float]) {
        let n = vDSP_Length(fftSize)

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
