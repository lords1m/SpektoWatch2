import Foundation
import AVFoundation
import Accelerate
import Combine

class AudioEngine: ObservableObject {

    private var audioEngine: AVAudioEngine
    private let bufferSize: AVAudioFrameCount = 8192
    private let fftSetup: vDSP_DFT_Setup
    private let sampleRate: Double = 44100.0
    private var dummyDataTimer: Timer?
    private var isUsingDummyData = false
    private var gainBoost: Float = 30.0

    // Recording time tracking
    private var recordingStartTime: Date?

    @Published var recordingDuration: TimeInterval = 0.0
    @Published var currentSpectrogramData: SpectrogramData?

    // === Flexible Bandbildungs-Parameter ===

    /// Wie viele FFT-Bins werden zu einem angezeigten Balken zusammengefasst?
    /// 1 = kein Binning (volle FFT-Auflösung)
    /// 4 = alle 4 Bins werden gemittelt (breitere Balken)
    /// 16 = alle 16 Bins werden gemittelt (noch breiter)
    private let binningFactor: Int = 4

    /// 0 = keine Glättung, 0.7..0.9 = recht stark verwischt
    private let temporalSmoothingFactor: Float = 0.7

    /// Zwischenspeicher für zeitliche Glättung
    private var previousBandMagnitudes: [Float] = []

    init() {
        audioEngine = AVAudioEngine()
        guard let setup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(bufferSize),
            vDSP_DFT_Direction.FORWARD
        ) else {
            fatalError("Failed to create FFT setup")
        }
        fftSetup = setup
    }

    deinit {
        vDSP_DFT_DestroySetup(fftSetup)
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

        #if targetEnvironment(simulator)
        print("Running on Simulator - using dummy audio data")
        startDummyDataGeneration()
        #else
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [])

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

            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) { [weak self] buffer, _ in
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
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        // 1. FFT
        let fftResult = performFFT(on: samples)

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
            WatchConnectivityManager.shared.sendSpectrogramData(spectrogramData)
        }
    }

    private func performFFT(on samples: [Float]) -> (frequencies: [Float], magnitudes: [Float]) {
        let n = vDSP_Length(bufferSize)

        var realIn = [Float](repeating: 0, count: Int(bufferSize))
        var imagIn = [Float](repeating: 0, count: Int(bufferSize))
        var realOut = [Float](repeating: 0, count: Int(bufferSize))
        var imagOut = [Float](repeating: 0, count: Int(bufferSize))

        // Apply Hann window
        var window = [Float](repeating: 0, count: Int(bufferSize))
        vDSP_hann_window(&window, vDSP_Length(bufferSize), Int32(vDSP_HANN_NORM))

        // Copy and window the samples
        let maxIndex = min(samples.count, Int(bufferSize))
        for i in 0..<maxIndex {
            realIn[i] = samples[i] * window[i]
        }

        vDSP_DFT_Execute(fftSetup,
                         realIn, imagIn,
                         &realOut, &imagOut)

        // Compute magnitude spectrum
        var magnitudes = [Float](repeating: 0, count: Int(bufferSize / 2))
        
        // Create DSPSplitComplex structure for magnitude calculation
        realOut.withUnsafeMutableBufferPointer { realPtr in
            imagOut.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(bufferSize / 2))
            }
        }

        // Apply gain boost and convert to dB
        var gainLinear: Float = pow(10.0, gainBoost / 20.0)
        vDSP_vsmul(magnitudes, 1, &gainLinear, &magnitudes, 1, vDSP_Length(magnitudes.count))
        var one: Float = 1.0
        vDSP_vsadd(magnitudes, 1, &one, &magnitudes, 1, vDSP_Length(magnitudes.count))
        var zero: Float = 1.0
        var dbMagnitudes = [Float](repeating: 0, count: magnitudes.count)
        vDSP_vdbcon(magnitudes, 1, &zero, &dbMagnitudes, 1, vDSP_Length(magnitudes.count), 0)

        // Frequency axis
        let nyquist = Float(sampleRate / 2.0)
        let freqResolution = nyquist / Float(magnitudes.count)
        let frequencies = (0..<magnitudes.count).map { Float($0) * freqResolution }

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
