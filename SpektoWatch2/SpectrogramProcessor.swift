import Foundation
import Accelerate

class SpectrogramProcessor {
    var temporalSmoothingFactor: Float = 0.5
    var binningFactor: Int = 2
    
    private var previousBandMagnitudes: [Float] = []
    private let bandstopFilterManager: BandstopFilterManager

    init(bandstopFilterManager: BandstopFilterManager) {
        self.bandstopFilterManager = bandstopFilterManager
    }
    
    struct Result {
        let bandFrequencies: [Float]
        let bandMagnitudes: [Float]
        let spectrum: [Float]
        let octaveBands: [Float]
    }
    
    func process(
        frequencies: [Float],
        dbMagnitudes: [Float],
        sampleRate: Double
    ) -> Result {
        // 1. Bandstop Filters
        let filteredMagnitudes = applyBandstopFilters(frequencies: frequencies, magnitudes: dbMagnitudes)
        
        // 2. Octave Bands (on filtered data)
        let octaveBands = calculateOctaveBands(frequencies: frequencies, magnitudes: filteredMagnitudes, sampleRate: sampleRate)
        
        // 3. Spectrum (filtered)
        let spectrum = filteredMagnitudes
        
        // 4. Binning
        let (bandFreqs, bandMags) = aggregateByBinningFactor(frequencies: frequencies, magnitudes: filteredMagnitudes)
        
        // 5. Smoothing
        let smoothedMagnitudes = temporalSmoothing(currentMagnitudes: bandMags)
        
        return Result(
            bandFrequencies: bandFreqs,
            bandMagnitudes: smoothedMagnitudes,
            spectrum: spectrum,
            octaveBands: octaveBands
        )
    }
    
    private func applyBandstopFilters(frequencies: [Float], magnitudes: [Float]) -> [Float] {
        guard !bandstopFilterManager.enabledFilters.isEmpty else {
            return magnitudes
        }
        
        // Hole pre-computed Map (O(1) wenn gecached)
        let attenuationMap = bandstopFilterManager.getAttenuationMap(for: frequencies)
        var filtered = magnitudes
        
        // Wende Map an (O(n))
        for i in 0..<filtered.count {
            if attenuationMap[i] < 0.01 { // Praktisch 0
                filtered[i] = -120.0 // blockiert
            } else if attenuationMap[i] < 1.0 {
                // Dämpfung in dB-Domain
                filtered[i] += 20 * log10(attenuationMap[i])
            }
        }
        return filtered
    }
    
    private func calculateOctaveBands(frequencies: [Float], magnitudes: [Float], sampleRate: Double) -> [Float] {
        let centerFreqs: [Float] = [
            20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800,
            1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
        ]
        
        var bands = [Float](repeating: -120.0, count: centerFreqs.count)
        let nyquist = Float(sampleRate / 2.0)
        let resolution = nyquist / Float(magnitudes.count)
        
        for (i, center) in centerFreqs.enumerated() {
            let lower = center * 0.89
            let upper = center * 1.12
            
            let startIdx = Int(lower / resolution)
            let endIdx = Int(upper / resolution)
            
            if startIdx < magnitudes.count {
                let safeEnd = min(endIdx, magnitudes.count - 1)
                if startIdx <= safeEnd {
                    let bandMax = magnitudes[startIdx...safeEnd].max() ?? -120.0
                    bands[i] = bandMax
                }
            }
        }
        return bands
    }
    
    private func aggregateByBinningFactor(frequencies: [Float], magnitudes: [Float]) -> ([Float], [Float]) {
        guard binningFactor > 1 else { return (frequencies, magnitudes) }
        
        var bandFrequencies: [Float] = []
        var bandMagnitudes: [Float] = []
        var i = 0
        while i < frequencies.count {
            let endIndex = min(i + binningFactor, frequencies.count)
            let binCount = endIndex - i
            bandFrequencies.append(frequencies[i...endIndex-1].reduce(0, +) / Float(binCount))
            bandMagnitudes.append(magnitudes[i..<endIndex].reduce(0, +) / Float(binCount))
            i = endIndex
        }
        return (bandFrequencies, bandMagnitudes)
    }
    
    private func temporalSmoothing(currentMagnitudes: [Float]) -> [Float] {
        guard !previousBandMagnitudes.isEmpty, previousBandMagnitudes.count == currentMagnitudes.count else {
            previousBandMagnitudes = currentMagnitudes
            return currentMagnitudes
        }
        var smoothed = [Float](repeating: 0, count: currentMagnitudes.count)
        vDSP_vintb(previousBandMagnitudes, 1, currentMagnitudes, 1, &temporalSmoothingFactor, &smoothed, 1, vDSP_Length(currentMagnitudes.count))
        previousBandMagnitudes = smoothed
        return smoothed
    }
}