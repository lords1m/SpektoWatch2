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
/// Thread-safe immutable value type - all data is computed at init time
/// NOTE: Changed from class to struct to avoid Swift Concurrency deallocation issues
struct FrequencyWeightingProcessor: Sendable {
    private let fftSize: Int
    private let sampleRate: Double

    // Pre-computed weighting curves (linear gain factors) - immutable after init
    private let aWeightingGains: [Float]
    private let cWeightingGains: [Float]
    private let zWeightingGains: [Float]

    // Pre-computed dB equivalents (20·log10 of linear gains) for vectorized applyWeighting
    private let aWeightingGainsDB: [Float]
    private let cWeightingGainsDB: [Float]

    // Pre-computed squared gains for vectorized energy accumulation in AudioEngine
    let aWeightingGainsSq: [Float]
    let cWeightingGainsSq: [Float]

    // Frequency array - immutable after init
    private let frequencies: [Float]

    // MARK: - Initialization

    init(fftSize: Int, sampleRate: Double) {
        self.fftSize = fftSize
        self.sampleRate = sampleRate

        let nyquist = Float(sampleRate / 2.0)
        let binCount = fftSize / 2
        let freqs = (0..<binCount).map { Float($0) * nyquist / Float(binCount) }
        self.frequencies = freqs

        // Pre-compute all weighting curves
        let aGains = Self.computeAWeighting(frequencies: freqs)
        let cGains = Self.computeCWeighting(frequencies: freqs)
        self.aWeightingGains = aGains
        self.cWeightingGains = cGains
        self.zWeightingGains = [Float](repeating: 1.0, count: binCount)

        // Pre-compute dB equivalents so applyWeighting only needs vDSP_vadd
        self.aWeightingGainsDB = aGains.map { 20.0 * log10(max($0, 1e-10)) }
        self.cWeightingGainsDB = cGains.map { 20.0 * log10(max($0, 1e-10)) }

        // Pre-compute squared gains for the energy dot-product in AudioEngine
        var aSq = [Float](repeating: 0, count: binCount)
        vDSP_vsq(aGains, 1, &aSq, 1, vDSP_Length(binCount))
        self.aWeightingGainsSq = aSq

        var cSq = [Float](repeating: 0, count: binCount)
        vDSP_vsq(cGains, 1, &cSq, 1, vDSP_Length(binCount))
        self.cWeightingGainsSq = cSq
    }

    // MARK: - Public Methods

    /// Applies frequency weighting to dB magnitudes using vectorized addition
    func applyWeighting(to dbMagnitudes: [Float], frequencies: [Float], weighting: FrequencyWeighting) -> [Float] {
        switch weighting {
        case .z:
            // Z-weighting is 0 dB everywhere — return input unchanged
            return dbMagnitudes
        case .a:
            let count = min(dbMagnitudes.count, aWeightingGainsDB.count)
            var weighted = [Float](repeating: -120.0, count: dbMagnitudes.count)
            vDSP_vadd(dbMagnitudes, 1, aWeightingGainsDB, 1, &weighted, 1, vDSP_Length(count))
            return weighted
        case .c:
            let count = min(dbMagnitudes.count, cWeightingGainsDB.count)
            var weighted = [Float](repeating: -120.0, count: dbMagnitudes.count)
            vDSP_vadd(dbMagnitudes, 1, cWeightingGainsDB, 1, &weighted, 1, vDSP_Length(count))
            return weighted
        }
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

            // IEC 61672-1:2013 C-weighting poles
            let f1 = 20.60
            let f4 = 12194.0

            // Normalization offset to ensure 0 dB at 1 kHz
            let offset = -0.062

            // C-weighting in dB (compute in dB space first)
            let cDb = 20.0 * log10((f4 * f4 * f2) / ((f2 + f1 * f1) * (f2 + f4 * f4))) - offset

            // Convert to linear gain
            let linearGain = pow(10.0, cDb / 20.0)

            return Float(linearGain)
        }
    }
}
