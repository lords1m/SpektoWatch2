import Foundation
import Accelerate
import os.signpost

class SpectrogramProcessor {
    private static let performanceLog = OSLog(subsystem: "com.spektowatch", category: "performance.spectrogram")
    private static let thirdOctaveCenters: [Float] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800,
        1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
    ]

    enum SmoothingTrack: Hashable {
        case z
        case a
        case c
    }

    /// IEC 61672 time weighting applied to the spectrogram (Fast = 125 ms, Slow = 1 s).
    var spectrogramTimeWeighting: TimeWeighting = .fast
    /// Duration of one FFT hop in seconds – must be kept in sync with the audio engine.
    var hopDuration: Float = 512.0 / 44100.0
    /// 0 = no temporal smoothing, 1 = full IEC time weighting smoothing.
    var temporalSmoothingIntensity: Float = 1.0

    var binningFactor: Int = 2
    
    private var previousBandMagnitudesByTrack: [SmoothingTrack: [Float]] = [:]
    private let bandstopFilterManager: BandstopFilterManager
    private let octaveCenterFrequencies = SpectrogramProcessor.thirdOctaveCenters
    private var cachedOctaveRanges: [(start: Int, end: Int)] = []
    private var cachedRangeMagnitudeCount: Int = 0
    private var cachedRangeSampleRate: Double = 0.0

    struct RangeDiagnostic {
        let label: String
        let lowerHz: Float
        let upperHz: Float
        let totalBins: Int
        let energeticBins: Int
        let maxDb: Float
    }

    struct DiagnosticSnapshot {
        let rangeDiagnostics: [RangeDiagnostic]
        let emptyThirdOctaveBands: [Float]
        let highestEnergeticFrequencyHz: Float
    }

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
        sampleRate: Double,
        smoothingTrack: SmoothingTrack
    ) -> Result {
        let signpostID = OSSignpostID(log: Self.performanceLog)
        os_signpost(.begin, log: Self.performanceLog, name: "SpectrogramProcess", signpostID: signpostID)
        defer { os_signpost(.end, log: Self.performanceLog, name: "SpectrogramProcess", signpostID: signpostID) }

        // 1. Bandstop Filters
        let filteredMagnitudes = applyBandstopFilters(frequencies: frequencies, magnitudes: dbMagnitudes)
        
        // 2. Octave Bands (on filtered data)
        let octaveBands = calculateOctaveBands(frequencies: frequencies, magnitudes: filteredMagnitudes, sampleRate: sampleRate)
        
        // 3. Spectrum (filtered)
        let spectrum = filteredMagnitudes
        
        // 4. Binning
        let (bandFreqs, bandMags) = aggregateByBinningFactor(frequencies: frequencies, magnitudes: filteredMagnitudes)
        
        // 5. Smoothing
        let smoothedMagnitudes = temporalSmoothing(currentMagnitudes: bandMags, track: smoothingTrack)
        
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
        guard !magnitudes.isEmpty else {
            return [Float](repeating: -120.0, count: octaveCenterFrequencies.count)
        }

        ensureOctaveBandRanges(magnitudeCount: magnitudes.count, sampleRate: sampleRate)
        var bands = [Float](repeating: -120.0, count: octaveCenterFrequencies.count)

        let magCount = magnitudes.count
        for (i, range) in cachedOctaveRanges.enumerated() {
            guard range.start <= range.end, range.end < magCount else { continue }
            var bandMax: Float = -120.0
            for idx in range.start...range.end {
                if magnitudes[idx] > bandMax {
                    bandMax = magnitudes[idx]
                }
            }
            bands[i] = bandMax
        }
        return bands
    }
    
    private func aggregateByBinningFactor(frequencies: [Float], magnitudes: [Float]) -> ([Float], [Float]) {
        guard binningFactor > 1 else { return (frequencies, magnitudes) }
        
        var bandFrequencies: [Float] = []
        var bandMagnitudes: [Float] = []
        bandFrequencies.reserveCapacity((frequencies.count + binningFactor - 1) / binningFactor)
        bandMagnitudes.reserveCapacity((magnitudes.count + binningFactor - 1) / binningFactor)
        var i = 0
        while i < frequencies.count {
            let endIndex = min(i + binningFactor, frequencies.count)
            let binCount = endIndex - i
            var frequencySum: Float = 0.0
            var magnitudeSum: Float = 0.0
            for idx in i..<endIndex {
                frequencySum += frequencies[idx]
                magnitudeSum += magnitudes[idx]
            }
            bandFrequencies.append(frequencySum / Float(binCount))
            bandMagnitudes.append(magnitudeSum / Float(binCount))
            i = endIndex
        }
        return (bandFrequencies, bandMagnitudes)
    }

    private func ensureOctaveBandRanges(magnitudeCount: Int, sampleRate: Double) {
        guard magnitudeCount != cachedRangeMagnitudeCount || sampleRate != cachedRangeSampleRate else {
            return
        }

        let nyquist = Float(sampleRate / 2.0)
        let resolution = nyquist / Float(magnitudeCount)
        var ranges: [(start: Int, end: Int)] = []
        ranges.reserveCapacity(octaveCenterFrequencies.count)

        for center in octaveCenterFrequencies {
            let lower = center * 0.89
            let upper = center * 1.12
            let rawStart = Int(lower / resolution)
            let rawEnd = Int(upper / resolution)
            let start = max(0, min(rawStart, magnitudeCount - 1))
            let end = max(0, min(rawEnd, magnitudeCount - 1))
            if start <= end {
                ranges.append((start, end))
            } else {
                ranges.append((0, -1))
            }
        }

        cachedOctaveRanges = ranges
        cachedRangeMagnitudeCount = magnitudeCount
        cachedRangeSampleRate = sampleRate
    }
    
    private func temporalSmoothing(currentMagnitudes: [Float], track: SmoothingTrack) -> [Float] {
        guard let previousBandMagnitudes = previousBandMagnitudesByTrack[track],
              previousBandMagnitudes.count == currentMagnitudes.count else {
            previousBandMagnitudesByTrack[track] = currentMagnitudes
            return currentMagnitudes
        }
        // IEC 61672 exponential time weighting: α = 1 − exp(−dt / τ)
        // τ = 0.125 s (Fast) or 1.0 s (Slow)
        let baseAlpha = 1.0 - exp(-hopDuration / spectrogramTimeWeighting.timeConstant)
        let intensity = max(0.0, min(1.0, temporalSmoothingIntensity))
        var alpha = (1.0 - intensity) + intensity * baseAlpha
        alpha = max(0.0, min(1.0, alpha))
        var oneMinusAlpha = 1.0 - alpha
        var smoothed = [Float](repeating: 0, count: currentMagnitudes.count)
        // EMA: smoothed = previous × (1−α) + current × α
        vDSP_vsmsma(previousBandMagnitudes, 1, &oneMinusAlpha, currentMagnitudes, 1, &alpha, &smoothed, 1, vDSP_Length(currentMagnitudes.count))
        previousBandMagnitudesByTrack[track] = smoothed
        return smoothed
    }

    /// Erzeugt eine kompakte Diagnosesicht für Logging und Tests.
    /// energeticThresholdDb beschreibt ab welchem Pegel ein Bin als "aktiv" zählt.
    static func makeDiagnosticSnapshot(
        frequencies: [Float],
        magnitudes: [Float],
        energeticThresholdDb: Float = 25.0
    ) -> DiagnosticSnapshot {
        let pairedCount = min(frequencies.count, magnitudes.count)
        guard pairedCount > 0 else {
            return DiagnosticSnapshot(
                rangeDiagnostics: [
                    RangeDiagnostic(label: "20-125", lowerHz: 20, upperHz: 125, totalBins: 0, energeticBins: 0, maxDb: -120),
                    RangeDiagnostic(label: "125-250", lowerHz: 125, upperHz: 250, totalBins: 0, energeticBins: 0, maxDb: -120),
                    RangeDiagnostic(label: "250-8k", lowerHz: 250, upperHz: 8000, totalBins: 0, energeticBins: 0, maxDb: -120),
                    RangeDiagnostic(label: "8k-16k", lowerHz: 8000, upperHz: 16000, totalBins: 0, energeticBins: 0, maxDb: -120)
                ],
                emptyThirdOctaveBands: Self.thirdOctaveCenters,
                highestEnergeticFrequencyHz: 0
            )
        }

        let ranges: [(label: String, lower: Float, upper: Float)] = [
            ("20-125", 20, 125),
            ("125-250", 125, 250),
            ("250-8k", 250, 8000),
            ("8k-16k", 8000, 16000)
        ]

        var rangeDiagnostics: [RangeDiagnostic] = []
        rangeDiagnostics.reserveCapacity(ranges.count)

        for range in ranges {
            var total = 0
            var energetic = 0
            var peak: Float = -120.0
            for i in 0..<pairedCount {
                let f = frequencies[i]
                guard f >= range.lower, f < range.upper else { continue }
                total += 1
                let m = magnitudes[i]
                peak = max(peak, m)
                if m >= energeticThresholdDb {
                    energetic += 1
                }
            }
            rangeDiagnostics.append(
                RangeDiagnostic(
                    label: range.label,
                    lowerHz: range.lower,
                    upperHz: range.upper,
                    totalBins: total,
                    energeticBins: energetic,
                    maxDb: peak
                )
            )
        }

        let lowerFactor = pow(2.0 as Float, -1.0 / 6.0)
        let upperFactor = pow(2.0 as Float, 1.0 / 6.0)
        var emptyBands: [Float] = []
        for center in Self.thirdOctaveCenters {
            let lower = center * lowerFactor
            let upper = center * upperFactor
            var bandHasBin = false
            for i in 0..<pairedCount {
                let f = frequencies[i]
                if f >= lower && f < upper {
                    bandHasBin = true
                    break
                }
            }
            if !bandHasBin {
                emptyBands.append(center)
            }
        }

        var highestEnergeticFrequency: Float = 0
        for i in 0..<pairedCount where magnitudes[i] >= energeticThresholdDb {
            highestEnergeticFrequency = max(highestEnergeticFrequency, frequencies[i])
        }

        return DiagnosticSnapshot(
            rangeDiagnostics: rangeDiagnostics,
            emptyThirdOctaveBands: emptyBands,
            highestEnergeticFrequencyHz: highestEnergeticFrequency
        )
    }
}
