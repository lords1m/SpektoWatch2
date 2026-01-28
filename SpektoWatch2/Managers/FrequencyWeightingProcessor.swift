import Foundation
import Accelerate

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

/// Handles frequency weighting calculations (A, C, Z) according to IEC 61672
class FrequencyWeightingProcessor {
    
    // MARK: - Properties
    
    private let fftSize: Int
    private let sampleRate: Double
    
    private var aWeights: [Float] = []
    private var cWeights: [Float] = []
    
    // MARK: - Initialization
    
    init(fftSize: Int = 8192, sampleRate: Double = 44100.0) {
        self.fftSize = fftSize
        self.sampleRate = sampleRate
        
        precomputeWeightingCurves()
    }
    
    // MARK: - Public Methods
    
    /// Applies frequency weighting to magnitudes in dB scale
    /// - Parameters:
    ///   - magnitudes: Input magnitudes in dB
    ///   - frequencies: Corresponding frequencies in Hz
    ///   - weighting: Type of weighting to apply
    /// - Returns: Weighted magnitudes in dB
    func applyWeighting(
        to magnitudes: [Float],
        frequencies: [Float],
        weighting: FrequencyWeighting
    ) -> [Float] {
        
        guard weighting != .z else {
            return magnitudes // No weighting for Z (linear)
        }
        
        var weightedMagnitudes = magnitudes
        var weightingOffsets = [Float](repeating: 0.0, count: frequencies.count)
        
        for (i, f) in frequencies.enumerated() {
            let offset = calculateWeightingOffset(frequency: f, weighting: weighting)
            weightingOffsets[i] = Float(offset)
        }
        
        // Add weighting offsets to magnitudes (in dB domain)
        vDSP_vadd(magnitudes, 1, weightingOffsets, 1, &weightedMagnitudes, 1, vDSP_Length(magnitudes.count))
        
        return weightedMagnitudes
    }
    
    /// Returns pre-computed A-weighting gains (linear scale) for energy calculations
    func getAWeightingGains() -> [Float] {
        return aWeights
    }
    
    /// Returns pre-computed C-weighting gains (linear scale) for energy calculations
    func getCWeightingGains() -> [Float] {
        return cWeights
    }
    
    /// Returns weighting gains for specified type (linear scale)
    func getWeightingGains(for weighting: FrequencyWeighting) -> [Float] {
        switch weighting {
        case .z:
            return [Float](repeating: 1.0, count: fftSize / 2)
        case .a:
            return aWeights
        case .c:
            return cWeights
        }
    }
    
    // MARK: - Private Methods
    
    private func precomputeWeightingCurves() {
        let nyquist = Float(sampleRate / 2.0)
        let freqResolution = nyquist / Float(fftSize / 2)
        
        aWeights = [Float](repeating: 0.0, count: fftSize / 2)
        cWeights = [Float](repeating: 0.0, count: fftSize / 2)
        
        for i in 0..<(fftSize / 2) {
            let f = Float(i) * freqResolution
            
            // A-weighting
            aWeights[i] = calculateAWeightingGain(frequency: f)
            
            // C-weighting
            cWeights[i] = calculateCWeightingGain(frequency: f)
        }
    }
    
    /// Calculates A-weighting gain (linear scale) for a given frequency
    /// Based on IEC 61672-1:2013
    private func calculateAWeightingGain(frequency f: Float) -> Float {
        let f2 = f * f
        
        let num = 12194.0 * 12194.0 * f2 * f2
        let den = (f2 + 20.6 * 20.6) * sqrt((f2 + 107.7 * 107.7) * (f2 + 737.9 * 737.9)) * (f2 + 12194.0 * 12194.0)
        
        guard den > 0 else { return 0.0 }
        
        let mag = num / den
        // Apply 2.0 dB correction factor
        let gain = Float(mag * pow(10.0, 2.0 / 20.0))
        
        return gain
    }
    
    /// Calculates C-weighting gain (linear scale) for a given frequency
    /// Based on IEC 61672-1:2013
    private func calculateCWeightingGain(frequency f: Float) -> Float {
        let f2 = f * f
        
        let num = 12194.0 * 12194.0 * f2
        let den = (f2 + 20.6 * 20.6) * (f2 + 12194.0 * 12194.0)
        
        guard den > 0 else { return 0.0 }
        
        let mag = num / den
        // Apply 0.06 dB correction factor
        let gain = Float(mag * pow(10.0, 0.06 / 20.0))
        
        return gain
    }
    
    /// Calculates weighting offset in dB for a given frequency
    private func calculateWeightingOffset(frequency f: Float, weighting: FrequencyWeighting) -> Double {
        let f2 = f * f
        var offset: Double = 0.0
        
        switch weighting {
        case .z:
            offset = 0.0
            
        case .a:
            let num = 12194.0 * 12194.0 * f2 * f2
            let den = (f2 + 20.6 * 20.6) * sqrt((f2 + 107.7 * 107.7) * (f2 + 737.9 * 737.9)) * (f2 + 12194.0 * 12194.0)
            if den > 0 {
                offset = 20.0 * log10(num / den) + 2.0
            }
            
        case .c:
            let num = 12194.0 * 12194.0 * f2
            let den = (f2 + 20.6 * 20.6) * (f2 + 12194.0 * 12194.0)
            if den > 0 {
                offset = 20.0 * log10(num / den) + 0.06
            }
        }
        
        return offset
    }
}
