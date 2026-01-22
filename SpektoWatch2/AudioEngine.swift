import Foundation
import AVFoundation
import Accelerate
import Combine

class AudioEngine: ObservableObject {
    private var audioEngine: AVAudioEngine
    private let bufferSize: AVAudioFrameCount = 8192  // Increased for better frequency resolution
    private let fftSetup: vDSP_DFT_Setup
    private let sampleRate: Double = 44100.0
    private var dummyDataTimer: Timer?
    private var isUsingDummyData = false
    private var gainBoost: Float = 30.0  // Higher default gain boost

    @Published var currentSpectrogramData: SpectrogramData?

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

    func startRecording() {
        #if targetEnvironment(simulator)
        // Simulator: Use dummy data
        print("Running on Simulator - using dummy audio data")
        startDummyDataGeneration()
        #else
        // Real device: Use actual microphone
        do {
            // Configure audio session for maximum sensitivity
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            
            // Try to set preferred input gain to maximum (if supported)
            if audioSession.isInputGainSettable {
                try audioSession.setInputGain(1.0)  // Maximum input gain
            }
            
            try audioSession.setActive(true)
            
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            // Validate the format before using it
            guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
                print("Invalid audio format - falling back to dummy data")
                startDummyDataGeneration()
                return
            }
            
            // Use the actual format if it's valid
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

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        let fftResult = performFFT(on: samples)
        let spectrogramData = SpectrogramData(
            frequencies: fftResult.frequencies,
            magnitudes: fftResult.magnitudes,
            sampleRate: sampleRate
        )

        DispatchQueue.main.async {
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

        // Apply Hann window to reduce spectral leakage
        var window = [Float](repeating: 0, count: Int(bufferSize))
        vDSP_hann_window(&window, vDSP_Length(bufferSize), Int32(vDSP_HANN_NORM))

        // Copy and window the samples
        for i in 0..<min(samples.count, Int(bufferSize)) {
            realIn[i] = samples[i] * window[i]
        }

        vDSP_DFT_Execute(fftSetup, &realIn, &imagIn, &realOut, &imagOut)

        var magnitudes = [Float](repeating: 0, count: Int(bufferSize / 2))

        // Calculate magnitude and convert to dB
        for i in 0..<Int(bufferSize / 2) {
            let real = realOut[i]
            let imag = imagOut[i]
            let magnitude = sqrt(real * real + imag * imag)
            
            // Calculate frequency for this bin
            let frequency = Float(i) * Float(sampleRate) / Float(bufferSize)
            
            // High-pass filter: iPhone mics don't work well below 100 Hz
            let highPassGain: Float
            if frequency < 100.0 {
                highPassGain = 0.0  // Complete cutoff
            } else if frequency < 200.0 {
                highPassGain = (frequency - 100.0) / 100.0  // Smooth rolloff 100-200 Hz
            } else {
                highPassGain = 1.0
            }
            
            // Normalize and apply gain boost
            let normalizedMagnitude = magnitude * (2.0 / Float(bufferSize)) * highPassGain
            
            // Apply adjustable gain boost
            let boostedMagnitude = normalizedMagnitude * gainBoost
            
            // Convert to dB
            let dB = 20.0 * log10(max(boostedMagnitude, 1e-10))
            let minDB: Float = -50.0
            let maxDB: Float = 20.0
            let normalizedDB = (dB - minDB) / (maxDB - minDB)
            
            // Apply power curve
            let gamma: Float = 0.4
            magnitudes[i] = pow(max(0, min(1, normalizedDB)), gamma)
        }

        let frequencies = (0..<magnitudes.count).map { i in
            Float(i) * Float(sampleRate) / Float(bufferSize)
        }

        return (frequencies, magnitudes)
    }
    
    // MARK: - Dummy Data Generation (for Simulator)
    
    private func startDummyDataGeneration() {
        isUsingDummyData = true
        
        // Generate dummy data at 120 Hz for ultra-smooth flow
        dummyDataTimer = Timer.scheduledTimer(withTimeInterval: 0.0083, repeats: true) { [weak self] _ in
            self?.generateDummyAudioData()
        }
    }
    
    private func stopDummyDataGeneration() {
        dummyDataTimer?.invalidate()
        dummyDataTimer = nil
        isUsingDummyData = false
    }
    
    private func generateDummyAudioData() {
        var samples = [Float](repeating: 0, count: Int(bufferSize))
        let time = Date().timeIntervalSinceReferenceDate

        // Generate a richer mix of frequencies to simulate interesting audio
        for i in 0..<Int(bufferSize) {
            let t = Float(i) / Float(sampleRate)

            // Mix of frequencies for visual interest
            samples[i] = sin(2.0 * .pi * 440.0 * t) * 0.5 +  // A4
                        sin(2.0 * .pi * 880.0 * t) * 0.4 +  // A5
                        sin(2.0 * .pi * 1320.0 * t) * 0.3 + // E6
                        sin(2.0 * .pi * 2640.0 * t) * 0.25 + // Higher harmonic
                        sin(2.0 * .pi * Float(220.0 + sin(time) * 100.0) * t) * 0.4 // Varying low frequency
        }

        // Add some random noise for realism
        for i in 0..<Int(bufferSize) {
            samples[i] += Float.random(in: -0.1...0.1)
        }

        // Process the dummy data through FFT
        let fftResult = performFFT(on: samples)
        let spectrogramData = SpectrogramData(
            frequencies: fftResult.frequencies,
            magnitudes: fftResult.magnitudes,
            sampleRate: sampleRate
        )

        DispatchQueue.main.async {
            self.currentSpectrogramData = spectrogramData
            WatchConnectivityManager.shared.sendSpectrogramData(spectrogramData)
        }
    }

    func processRemoteAudioData(_ audioData: AudioData) async {
        // Perform heavy FFT computation off the main thread
        let fftResult = performFFT(on: audioData.samples)
        let spectrogramData = SpectrogramData(
            frequencies: fftResult.frequencies,
            magnitudes: fftResult.magnitudes,
            sampleRate: audioData.sampleRate
        )

        await MainActor.run {
            self.currentSpectrogramData = spectrogramData
            WatchConnectivityManager.shared.sendSpectrogramData(spectrogramData)
        }
    }
}
