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

/// Applies frequency weighting curves (A, C, Z) to spectral data
class FrequencyWeightingProcessor {
    private let fftSize: Int
    private let sampleRate: Double
    
    // Pre-computed weighting curves (linear gain factors)
    private var aWeightingGains: [Float]
    private var cWeightingGains: [Float]
    private var zWeightingGains: [Float]
    
    // Frequency array
    private let frequencies: [Float]
    
    // MARK: - Initialization
    
    init(fftSize: Int, sampleRate: Double) {
        self.fftSize = fftSize
        self.sampleRate = sampleRate
        
        let nyquist = Float(sampleRate / 2.0)
        let binCount = fftSize / 2
        self.frequencies = (0..<binCount).map { Float($0) * nyquist / Float(binCount) }
        
        // Pre-compute all weighting curves
        self.aWeightingGains = Self.computeAWeighting(frequencies: frequencies)
        self.cWeightingGains = Self.computeCWeighting(frequencies: frequencies)
        self.zWeightingGains = [Float](repeating: 1.0, count: binCount) // Z = flat
    }
    
    // MARK: - Public Methods
    
    /// Applies frequency weighting to dB magnitudes
    /// - Parameters:
    ///   - dbMagnitudes: Input magnitudes in dB
    ///   - frequencies: Frequency array (must match dbMagnitudes length)
    ///   - weighting: Weighting type to apply
    /// - Returns: Weighted dB magnitudes
    func applyWeighting(to dbMagnitudes: [Float], frequencies: [Float], weighting: FrequencyWeighting) -> [Float] {
        let gains = getWeightingGains(for: weighting)
        var weighted = [Float](repeating: -120.0, count: dbMagnitudes.count)

        // Sichere Iteration: min() verhindert Index-Out-of-Bounds wenn FFT-Größe geändert wurde
        let count = min(dbMagnitudes.count, gains.count)

        // Convert gains to dB and add
        for i in 0..<count {
            let gainDB = 20.0 * log10(max(gains[i], 1e-10))
            weighted[i] = dbMagnitudes[i] + gainDB
        }

        return weighted
    }
    
    /// Returns linear gain factors for a specific weighting
    func getWeightingGains(for weighting: FrequencyWeighting) -> [Float] {
        switch weighting {
        case .a: return aWeightingGains
        case .c: return cWeightingGains
        case .z: return zWeightingGains
        }
    }
    
    /// Returns A-weighting gains (for legacy API compatibility)
    func getAWeightingGains() -> [Float] {
        return aWeightingGains
    }
    
    /// Returns C-weighting gains (for legacy API compatibility)
    func getCWeightingGains() -> [Float] {
        return cWeightingGains
    }
    
    // MARK: - A-Weighting Computation (IEC 61672-1:2013)
    
    private static func computeAWeighting(frequencies: [Float]) -> [Float] {
        return frequencies.map { freq -> Float in
            guard freq > 0 else { return 0.0 }
            
            let f = Double(freq)
            let f2 = f * f
            let f4 = f2 * f2
            
            // IEC 61672-1:2013 A-weighting formula
            let numerator = 12194.0 * 12194.0 * f4
            let denominator = (f2 + 20.6 * 20.6) *
                              sqrt((f2 + 107.7 * 107.7) * (f2 + 737.9 * 737.9)) *
                              (f2 + 12194.0 * 12194.0)
            
            let linearGain = Float(numerator / denominator)
            
            // Normalize to 0 dB at 1 kHz
            let normalizationFactor: Float = 1.25893 // Makes 1kHz = 1.0
            return linearGain * normalizationFactor
        }
    }
    
    // MARK: - C-Weighting Computation (IEC 61672-1:2013)
    
    private static func computeCWeighting(frequencies: [Float]) -> [Float] {
        return frequencies.map { freq -> Float in
            guard freq > 0 else { return 0.0 }
            
            let f = Double(freq)
            let f2 = f * f
            let f4 = f2 * f2
            
            // IEC 61672-1:2013 C-weighting formula
            let numerator = 12194.0 * 12194.0 * f4
            let denominator = (f2 + 20.6 * 20.6) * (f2 + 12194.0 * 12194.0)
            
            let linearGain = Float(numerator / denominator)
            
            // Normalize to 0 dB at 1 kHz
            let normalizationFactor: Float = 1.00659 // Makes 1kHz = 1.0
            return linearGain * normalizationFactor
        }
    }
}
