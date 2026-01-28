import Foundation

/// Generates dummy audio data for testing in the simulator
class TestAudioGenerator {
    
    // MARK: - Properties
    
    private let sampleRate: Double
    private var timer: Timer?
    private var startTime: Date?
    
    var isGenerating: Bool {
        return timer != nil
    }
    
    // Callback for generated data
    var onDataGenerated: (([Float]) -> Void)?
    
    // MARK: - Initialization
    
    init(sampleRate: Double = 44100.0) {
        self.sampleRate = sampleRate
    }
    
    // MARK: - Public Methods
    
    /// Starts generating dummy audio data at regular intervals
    /// - Parameter updateInterval: Time between updates in seconds
    func start(updateInterval: TimeInterval = 0.05) {
        guard !isGenerating else { return }
        
        startTime = Date()
        
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.generateAndDeliverSamples()
        }
    }
    
    /// Stops generating dummy audio data
    func stop() {
        timer?.invalidate()
        timer = nil
        startTime = nil
    }
    
    /// Generates a single buffer of dummy audio samples
    /// - Parameter bufferSize: Number of samples to generate
    /// - Returns: Array of dummy audio samples
    func generateSamples(bufferSize: Int = 512) -> [Float] {
        let t = Date().timeIntervalSince1970
        var samples = [Float]()
        samples.reserveCapacity(bufferSize)
        
        for i in 0..<bufferSize {
            let sampleTime = t + Double(i) / sampleRate
            
            // Generate a complex test signal with multiple frequency components
            // 440 Hz (A4) sine wave
            let freq1 = 440.0
            let phase1 = 2.0 * .pi * freq1 * sampleTime
            let amp1 = 0.2
            
            // 880 Hz (A5) sine wave
            let freq2 = 880.0
            let phase2 = 2.0 * .pi * freq2 * sampleTime
            let amp2 = 0.15
            
            // 1760 Hz (A6) sine wave
            let freq3 = 1760.0
            let phase3 = 2.0 * .pi * freq3 * sampleTime
            let amp3 = 0.1
            
            // Slow amplitude modulation
            let modFreq = 0.5
            let modPhase = 2.0 * .pi * modFreq * sampleTime
            let modulation = 0.5 + 0.5 * sin(modPhase)
            
            // Add some noise
            let noise = Float.random(in: -0.02...0.02)
            
            // Combine all components
            let sample = Float(
                (amp1 * sin(phase1) +
                 amp2 * sin(phase2) +
                 amp3 * sin(phase3)) * modulation
            ) + noise
            
            samples.append(sample)
        }
        
        return samples
    }
    
    /// Generates spectrogram-style dummy data (frequencies and magnitudes)
    /// - Parameter fftSize: FFT size to simulate
    /// - Returns: Tuple of frequencies and magnitudes in dB
    func generateSpectrogramData(fftSize: Int = 512) -> (frequencies: [Float], magnitudes: [Float]) {
        let t = Date().timeIntervalSince1970
        
        let nyquist = Float(sampleRate / 2.0)
        let freqResolution = nyquist / Float(fftSize)
        
        var frequencies = [Float]()
        var magnitudes = [Float]()
        
        frequencies.reserveCapacity(fftSize)
        magnitudes.reserveCapacity(fftSize)
        
        for i in 0..<fftSize {
            let freq = Float(i) * freqResolution
            frequencies.append(freq)
            
            // Create animated peaks at specific frequencies
            let phase1 = Float(t) * 0.3 + Float(i) * 0.01
            let phase2 = Float(t) * 0.5 + Float(i) * 0.02
            
            let peak1 = sin(phase1) * 15
            let peak2 = sin(phase2) * 10
            let noise = Float.random(in: -5...0)
            
            let mag = peak1 + peak2 + noise - 40
            magnitudes.append(mag)
        }
        
        return (frequencies, magnitudes)
    }
    
    // MARK: - Private Methods
    
    private func generateAndDeliverSamples() {
        let samples = generateSamples()
        onDataGenerated?(samples)
    }
}

// MARK: - Preset Test Signals

extension TestAudioGenerator {
    
    /// Generates a pure sine wave at specified frequency
    /// - Parameters:
    ///   - frequency: Frequency in Hz
    ///   - amplitude: Amplitude (0.0 to 1.0)
    ///   - duration: Duration in seconds
    /// - Returns: Array of audio samples
    func generateSineWave(frequency: Double, amplitude: Double = 0.5, duration: Double = 1.0) -> [Float] {
        let numSamples = Int(sampleRate * duration)
        var samples = [Float]()
        samples.reserveCapacity(numSamples)
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let phase = 2.0 * .pi * frequency * t
            let sample = Float(amplitude * sin(phase))
            samples.append(sample)
        }
        
        return samples
    }
    
    /// Generates pink noise (1/f noise)
    /// - Parameters:
    ///   - amplitude: Amplitude (0.0 to 1.0)
    ///   - duration: Duration in seconds
    /// - Returns: Array of audio samples
    func generatePinkNoise(amplitude: Double = 0.3, duration: Double = 1.0) -> [Float] {
        let numSamples = Int(sampleRate * duration)
        var samples = [Float]()
        samples.reserveCapacity(numSamples)
        
        // Simple pink noise approximation using white noise and filtering
        var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
        
        for _ in 0..<numSamples {
            let white = Float.random(in: -1...1)
            
            b0 = 0.99886 * b0 + white * 0.0555179
            b1 = 0.99332 * b1 + white * 0.0750759
            b2 = 0.96900 * b2 + white * 0.1538520
            b3 = 0.86650 * b3 + white * 0.3104856
            b4 = 0.55000 * b4 + white * 0.5329522
            b5 = -0.7616 * b5 - white * 0.0168980
            
            let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
            b6 = white * 0.115926
            
            samples.append(Float(amplitude) * pink * 0.11)
        }
        
        return samples
    }
    
    /// Generates a frequency sweep (chirp)
    /// - Parameters:
    ///   - startFreq: Starting frequency in Hz
    ///   - endFreq: Ending frequency in Hz
    ///   - amplitude: Amplitude (0.0 to 1.0)
    ///   - duration: Duration in seconds
    /// - Returns: Array of audio samples
    func generateSweep(startFreq: Double, endFreq: Double, amplitude: Double = 0.5, duration: Double = 2.0) -> [Float] {
        let numSamples = Int(sampleRate * duration)
        var samples = [Float]()
        samples.reserveCapacity(numSamples)
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let progress = t / duration
            
            // Linear frequency sweep
            let freq = startFreq + (endFreq - startFreq) * progress
            let phase = 2.0 * .pi * freq * t
            let sample = Float(amplitude * sin(phase))
            samples.append(sample)
        }
        
        return samples
    }
}
