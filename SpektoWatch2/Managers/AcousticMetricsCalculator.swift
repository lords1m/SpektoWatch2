import Foundation

enum TimeWeighting: String, CaseIterable {
    case fast = "Fast"
    case slow = "Slow"
    
    var displayName: String { rawValue }
    
    /// Time constant in seconds according to IEC 61672
    var timeConstant: Float {
        switch self {
        case .fast: return 0.125  // 125 ms
        case .slow: return 1.0    // 1000 ms
        }
    }
}

/// Calculates acoustic metrics (LAF, LAS, LAeq, etc.) according to IEC 61672 standards
class AcousticMetricsCalculator {
    
    // MARK: - Properties
    
    private let sampleRate: Double
    
    // Energy accumulators for exponential averaging
    private var lafEnergy: Float = 1e-12
    private var lasEnergy: Float = 1e-12
    private var lcfEnergy: Float = 1e-12
    private var lcsEnergy: Float = 1e-12
    private var lzfEnergy: Float = 1e-12
    private var lzsEnergy: Float = 1e-12
    
    // Equivalent level calculation
    private var laeqAccumulator: Double = 0.0
    private var laeqCount: Int = 0
    
    // Min/Max tracking
    private var lafMin: Float = 1000.0
    private var lafMax: Float = -1000.0
    private var lcPeakHold: Float = -120.0
    
    // Histogram for percentile calculations
    private var lafHistogram = [Int](repeating: 0, count: 1401) // -130 dB to +10 dB in 0.1 dB steps
    private var lafTotalCounts: Int = 0
    private let histMinDB: Float = -130.0
    
    // Taktmaximal (5-second maximum)
    private var currentTaktMax: Float = -1000.0
    private var lastTaktTime: TimeInterval = 0
    private var taktValues: [Float] = []
    
    // MARK: - Initialization
    
    init(sampleRate: Double = 44100.0) {
        self.sampleRate = sampleRate
    }
    
    // MARK: - Public Methods
    
    /// Updates all acoustic metrics with new FFT energy data
    /// - Parameters:
    ///   - energyZ: Unweighted (Z) energy
    ///   - energyA: A-weighted energy
    ///   - energyC: C-weighted energy
    ///   - peakLevel: Peak level in dB
    ///   - dt: Time step since last update (in seconds)
    ///   - recordingDuration: Total recording duration for Taktmaximal calculation
    /// - Returns: Dictionary of current levels
    func updateMetrics(
        energyZ: Float,
        energyA: Float,
        energyC: Float,
        peakLevel: Float,
        dt: Float,
        recordingDuration: TimeInterval
    ) -> [String: Float] {
        
        // Calculate exponential averaging coefficients
        let alphaFast = 1.0 - exp(-dt / TimeWeighting.fast.timeConstant)
        let alphaSlow = 1.0 - exp(-dt / TimeWeighting.slow.timeConstant)
        
        // Update exponentially averaged energies
        lafEnergy = (1.0 - alphaFast) * lafEnergy + alphaFast * energyA
        lasEnergy = (1.0 - alphaSlow) * lasEnergy + alphaSlow * energyA
        
        lcfEnergy = (1.0 - alphaFast) * lcfEnergy + alphaFast * energyC
        lcsEnergy = (1.0 - alphaSlow) * lcsEnergy + alphaSlow * energyC
        
        lzfEnergy = (1.0 - alphaFast) * lzfEnergy + alphaFast * energyZ
        lzsEnergy = (1.0 - alphaSlow) * lzsEnergy + alphaSlow * energyZ
        
        // Update equivalent level accumulator
        laeqAccumulator += Double(energyA)
        laeqCount += 1
        
        // Calculate broadband level (LAF)
        let broadbandLevel = 10.0 * log10(lafEnergy + 1e-12)
        
        // Update min/max
        lafMin = min(lafMin, broadbandLevel)
        lafMax = max(lafMax, broadbandLevel)
        
        // Update peak hold
        lcPeakHold = max(lcPeakHold, peakLevel)
        
        // Update histogram
        let histIndex = Int((broadbandLevel - histMinDB) * 10.0)
        if histIndex >= 0 && histIndex < lafHistogram.count {
            lafHistogram[histIndex] += 1
            lafTotalCounts += 1
        }
        
        // Update Taktmaximal (5-second maximum)
        currentTaktMax = max(currentTaktMax, broadbandLevel)
        if recordingDuration - lastTaktTime >= 5.0 {
            taktValues.append(currentTaktMax)
            currentTaktMax = -1000.0
            lastTaktTime = recordingDuration
        }
        
        // Build levels dictionary
        var levels: [String: Float] = [
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
        
        // Add percentiles if we have enough data
        if lafTotalCounts > 0 {
            levels["LAF5"] = calculatePercentile(targetPercentage: 0.05)
            levels["LAF95"] = calculatePercentile(targetPercentage: 0.95)
        } else {
            levels["LAF5"] = -120.0
            levels["LAF95"] = -120.0
        }
        
        // Calculate Taktmaximal equivalent level
        if !taktValues.isEmpty {
            let sumEnergy = taktValues.reduce(0.0) { $0 + pow(10.0, Double($1) / 10.0) }
            levels["LAFTeq"] = Float(10.0 * log10(sumEnergy / Double(taktValues.count) + 1e-12))
        } else {
            levels["LAFTeq"] = currentTaktMax > -1000 ? currentTaktMax : -120.0
        }
        
        return levels
    }
    
    /// Resets all metrics to initial state
    func reset() {
        lafEnergy = 1e-12
        lasEnergy = 1e-12
        lcfEnergy = 1e-12
        lcsEnergy = 1e-12
        lzfEnergy = 1e-12
        lzsEnergy = 1e-12
        
        laeqAccumulator = 0.0
        laeqCount = 0
        
        lafMin = 1000.0
        lafMax = -1000.0
        lcPeakHold = -120.0
        
        lafHistogram = [Int](repeating: 0, count: 1401)
        lafTotalCounts = 0
        
        currentTaktMax = -1000.0
        lastTaktTime = 0
        taktValues = []
    }
    
    /// Returns current statistics summary
    func getStatistics() -> (laeqFast: Float, peak: Float, min: Float) {
        return (
            laeqFast: 10.0 * log10(lafEnergy + 1e-12),
            peak: lafMax,
            min: lafMin
        )
    }
    
    // MARK: - Private Methods
    
    /// Calculates percentile from histogram
    /// - Parameter targetPercentage: Percentile to calculate (0.0 to 1.0)
    /// - Returns: Level in dB at the specified percentile
    private func calculatePercentile(targetPercentage: Double) -> Float {
        let targetCount = Int(Double(lafTotalCounts) * targetPercentage)
        guard targetCount > 0 else { return histMinDB }
        var currentCount = 0

        // Iterate from high to low (counts levels exceeded >= targetPercentage of the time)
        for i in stride(from: lafHistogram.count - 1, through: 0, by: -1) {
            currentCount += lafHistogram[i]
            if currentCount >= targetCount {
                return histMinDB + Float(i) / 10.0
            }
        }

        return histMinDB
    }
}
