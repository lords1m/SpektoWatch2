import Foundation
import Accelerate

/// Generates test audio signals for simulator testing
class TestAudioGenerator {
    private let sampleRate: Double
    private var timer: Timer?
    private var phase: Float = 0.0
    
    var onDataGenerated: (([Float]) -> Void)?
    
    // MARK: - Initialization
    
    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }
    
    // MARK: - Control
    
    func start() {
        stop() // Ensure no duplicate timers
        
        // Generate audio at ~86 Hz (512 samples @ 44.1 kHz)
        let interval = 512.0 / sampleRate
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.generateAndEmitAudio()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        phase = 0.0
    }
    
    // MARK: - Audio Generation
    
    private func generateAndEmitAudio() {
        let sampleCount = 512
        var samples = [Float](repeating: 0, count: sampleCount)
        
        // Generate multi-tone test signal
        // 1. Fundamental at 440 Hz (A4)
        // 2. Second harmonic at 880 Hz
        // 3. Third harmonic at 1320 Hz
        // 4. Pink noise component
        
        let dt = Float(1.0 / sampleRate)
        
        for i in 0..<sampleCount {
            // Fundamental tone (440 Hz)
            let freq1: Float = 440.0
            let amp1: Float = 0.3
            let sample1 = amp1 * sin(2.0 * .pi * freq1 * phase)
            
            // Second harmonic (880 Hz)
            let freq2: Float = 880.0
            let amp2: Float = 0.15
            let sample2 = amp2 * sin(2.0 * .pi * freq2 * phase)
            
            // Third harmonic (1320 Hz)
            let freq3: Float = 1320.0
            let amp3: Float = 0.1
            let sample3 = amp3 * sin(2.0 * .pi * freq3 * phase)
            
            // Low-frequency component (50 Hz "mains hum")
            let freq50: Float = 50.0
            let amp50: Float = 0.05
            let sample50 = amp50 * sin(2.0 * .pi * freq50 * phase)
            
            // Pink noise (simple approximation)
            let noise = Float.random(in: -0.02...0.02)
            
            // Mix all components
            samples[i] = sample1 + sample2 + sample3 + sample50 + noise
            
            // Update phase
            phase += dt
            if phase >= 1.0 {
                phase -= 1.0
            }
        }
        
        // Emit generated audio
        onDataGenerated?(samples)
    }
    
    // MARK: - Test Signal Variants
    
    /// Generates a sweep from lowFreq to highFreq
    func generateSweep(sampleCount: Int, lowFreq: Float, highFreq: Float) -> [Float] {
        var samples = [Float](repeating: 0, count: sampleCount)
        let dt = Float(1.0 / sampleRate)
        var localPhase: Float = 0.0
        
        for i in 0..<sampleCount {
            let progress = Float(i) / Float(sampleCount)
            let freq = lowFreq + (highFreq - lowFreq) * progress
            
            samples[i] = 0.5 * sin(2.0 * .pi * freq * localPhase)
            
            localPhase += dt
            if localPhase >= 1.0 {
                localPhase -= 1.0
            }
        }
        
        return samples
    }
    
    /// Generates white noise
    func generateWhiteNoise(sampleCount: Int, amplitude: Float = 0.1) -> [Float] {
        return (0..<sampleCount).map { _ in Float.random(in: -amplitude...amplitude) }
    }
    
    /// Generates a pure tone
    func generateTone(sampleCount: Int, frequency: Float, amplitude: Float = 0.5) -> [Float] {
        var samples = [Float](repeating: 0, count: sampleCount)
        let dt = Float(1.0 / sampleRate)
        var localPhase: Float = 0.0
        
        for i in 0..<sampleCount {
            samples[i] = amplitude * sin(2.0 * .pi * frequency * localPhase)
            localPhase += dt
            if localPhase >= 1.0 {
                localPhase -= 1.0
            }
        }
        
        return samples
    }
}
