import Foundation
import Accelerate

/// Calculates acoustic metrics (LAF, LAS, LAeq, LCF, LZF, peak)
class AcousticMetricsCalculator {
    private let sampleRate: Double
    
    // Exponential averaging time constants
    private let fastTau: Float = 0.125  // 125ms for Fast (LAF)
    private let slowTau: Float = 1.0    // 1s for Slow (LAS)
    
    // Running averages
    private var lafLevel: Float = 0.0
    private var lasLevel: Float = 0.0
    private var lcfLevel: Float = 0.0
    private var lzfLevel: Float = 0.0
    
    // Statistics
    private var peakLevel: Float = -120.0
    private var minLevel: Float = 0.0
    private var energySum: Float = 0.0
    private var totalTime: Float = 0.0
    
    // MARK: - Initialization
    
    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }
    
    // MARK: - Metrics Update
    
    /// Updates all acoustic metrics with new energy measurements
    /// - Parameters:
    ///   - energyZ: Z-weighted energy (linear)
    ///   - energyA: A-weighted energy (linear)
    ///   - energyC: C-weighted energy (linear)
    ///   - peakLevel: Peak level in dB
    ///   - dt: Time delta in seconds
    ///   - recordingDuration: Total recording duration in seconds
    /// - Returns: Dictionary with all current levels
    func updateMetrics(
        energyZ: Float,
        energyA: Float,
        energyC: Float,
        peakLevel: Float,
        dt: Float,
        recordingDuration: TimeInterval
    ) -> [String: Float] {
        // Convert energies to dB
        let instantaneousA = 10.0 * log10(max(energyA, 1e-20))
        let instantaneousC = 10.0 * log10(max(energyC, 1e-20))
        let instantaneousZ = 10.0 * log10(max(energyZ, 1e-20))
        
        // Update exponential averages (Fast)
        let alphaFast = 1.0 - exp(-dt / fastTau)
        lafLevel = lafLevel + alphaFast * (instantaneousA - lafLevel)
        lcfLevel = lcfLevel + alphaFast * (instantaneousC - lcfLevel)
        lzfLevel = lzfLevel + alphaFast * (instantaneousZ - lzfLevel)
        
        // Update exponential averages (Slow)
        let alphaSlow = 1.0 - exp(-dt / slowTau)
        lasLevel = lasLevel + alphaSlow * (instantaneousA - lasLevel)
        
        // Update peak
        self.peakLevel = max(self.peakLevel, peakLevel)
        
        // Update LAeq (energy sum)
        energySum += energyA * dt
        totalTime += dt
        
        // Calculate LAeq
        let laeq = totalTime > 0 ? 10.0 * log10(max(energySum / totalTime, 1e-20)) : -120.0
        
        // Update min level (only for meaningful values)
        if lafLevel > -110 {
            if minLevel == 0 {
                minLevel = lafLevel
            } else {
                minLevel = min(minLevel, lafLevel)
            }
        }
        
        return [
            "LAF": lafLevel,
            "LAS": lasLevel,
            "LAeq": laeq,
            "LCF": lcfLevel,
            "LZF": lzfLevel,
            "LCpeak": self.peakLevel,
            "LAmin": minLevel
        ]
    }
    
    /// Resets all metrics to initial state
    func reset() {
        lafLevel = 0.0
        lasLevel = 0.0
        lcfLevel = 0.0
        lzfLevel = 0.0
        peakLevel = -120.0
        minLevel = 0.0
        energySum = 0.0
        totalTime = 0.0
    }
    
    /// Returns statistics summary
    func getStatistics() -> (laeqFast: Float, peak: Float, min: Float) {
        let laeq = totalTime > 0 ? 10.0 * log10(max(energySum / totalTime, 1e-20)) : -120.0
        return (laeq, peakLevel, minLevel)
    }
}
