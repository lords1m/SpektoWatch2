import Foundation
import os

// MARK: - MetricsResult

/// Value returned by `AcousticMetricsCalculator.updateMetrics`.
///
/// Bundling the broadband levels dict and the per-band Leq arrays in a single
/// struct avoids a second lock acquisition when the caller (AudioEngine) needs
/// both pieces of data after a single `updateMetrics` call.
struct MetricsResult {
    /// Broadband acoustic levels (LAF, LAS, LAeq, PHON, SONE, …).
    var levels: [String: Float]
    /// Per-band Leq (31 third-octave, Z-weighted): energy integrated over the
    /// measurement time from the unsmoothed bands (MC-4).
    /// Empty if no Z-band data was passed on this call.
    var bandLeqZ: [Float]
    /// Per-band Leq (31 third-octave, A-weighted). Empty when A-weighting is not active.
    var bandLeqA: [Float]
    /// Per-band Leq (31 third-octave, C-weighted). Empty when C-weighting is not active.
    var bandLeqC: [Float]
}

// MARK: -

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

/// Calculates acoustic metrics (LAF, LAS, LAeq, etc.) according to IEC 61672 standards.
///
/// ## Thread safety
///
/// - `updateMetrics(...)` is **real-time safe**: it may be called from the audio render
///   thread. It acquires the internal `OSAllocatedUnfairLock` via `withLockUnchecked`,
///   which avoids the ownership assertion overhead and priority-inversion detection that
///   are incompatible with real-time constraints.
/// - `reset()` may be called from **any thread** (typically main). The same lock
///   arbitrates against a concurrent `updateMetrics` call.
/// - `getStatistics()` is also thread-safe — it reads under the same lock.
///
/// The lock is `OSAllocatedUnfairLock` (not `NSLock`/`DispatchQueue`) to ensure
/// sub-microsecond uncontended acquisition and to avoid priority inversion on the
/// audio render thread.
class AcousticMetricsCalculator: @unchecked Sendable {

    // MARK: - Thread safety

    /// Guards all mutable accumulator state. Acquired with `withLockUnchecked` on the
    /// audio render thread; acquired with `withLock` / `withLockUnchecked` on other
    /// threads. No callouts are made while holding this lock.
    private let lock = OSAllocatedUnfairLock()

    // MARK: - Properties

    private let sampleRate: Double

    // Energy accumulators for exponential averaging
    private var lafEnergy: Float = 1e-12
    private var lasEnergy: Float = 1e-12
    private var lcfEnergy: Float = 1e-12
    private var lcsEnergy: Float = 1e-12
    private var lzfEnergy: Float = 1e-12
    private var lzsEnergy: Float = 1e-12

    // LAeq: time-integrated A-weighted energy (IEC Leq = 10·log10(∫E·dt / T)).
    private var laeqEnergyIntegral: Double = 0.0
    private var laeqTotalTime: Double = 0.0

    // Min/Max tracking
    private var lafMin: Float = 1000.0
    private var lafMax: Float = -1000.0
    private var lcPeakHold: Float = -120.0

    // Histogram for LAF percentile calculations (LAF5 / LAF95).
    // Covers −130 dB to +140 dB in 0.1 dB steps = 2701 bins.
    // The original ceiling was +10 dB, which silently saturated for
    // calibrated signals above that level — AE-6 fix extends to +140 dB.
    private static let histMinDB: Float = -130.0
    private static let histMaxDB: Float = 140.0
    private static let histBinCount: Int = Int((histMaxDB - histMinDB) * 10.0) + 1 // 2701
    private var lafHistogram = [Int](repeating: 0, count: histBinCount)
    private var lafTotalCounts: Int = 0
    // histMinDB kept as computed property for compatibility with existing callsite
    private var histMinDB: Float { Self.histMinDB }

    // Taktmaximal (5-second maximum)
    private var currentTaktMax: Float = -1000.0
    private var lastTaktTime: TimeInterval = 0
    private var taktValues: [Float] = []

    // MARK: - Per-band Leq (MC-4)

    /// Per-band energy integrals `Σ 10^(L/10)·dt` (linear power × seconds)
    /// and the integrated time per weighting. Leq = 10·log10(E/T) — a true
    /// equivalent level, independent of hop size or display smoothing
    /// (previously an EMA with a fixed 0.02 per-frame coefficient on
    /// display-smoothed bands). Protected by `lock`.
    private var bandEnergyZ: [Double] = []
    private var bandEnergyA: [Double] = []
    private var bandEnergyC: [Double] = []
    private var bandTimeZ: Double = 0
    private var bandTimeA: Double = 0
    private var bandTimeC: Double = 0

    /// RT-5: percentile scans over the 2701-bin histogram run every
    /// `percentileInterval` frames, not every frame.
    private let percentileInterval = 16
    private var framesSincePercentile = Int.max / 2
    private var cachedLAF5: Float = -120.0
    private var cachedLAF95: Float = -120.0

    // MARK: - Initialization

    init(sampleRate: Double = 44100.0) {
        self.sampleRate = sampleRate
    }

    // MARK: - Public Methods

    /// Updates all acoustic metrics with new FFT energy data.
    ///
    /// **Thread**: may be called from the audio render thread. Acquires the internal
    /// lock for the duration of accumulator mutation only; no callouts are made under
    /// the lock.
    ///
    /// - Parameters:
    ///   - energyZ: Unweighted (Z) linear energy for this frame
    ///   - energyA: A-weighted linear energy for this frame
    ///   - energyC: C-weighted linear energy for this frame
    ///   - peakLevel: IEC 61672 LCpeak in dB SPL (C-weighted frequency-domain peak)
    ///   - dt: Time step since last update (seconds)
    ///   - recordingDuration: Total recording duration for Taktmaximal calculation
    ///   - frequencies: FFT bin centre frequencies (Hz) — used for PHON/SONE
    ///   - magnitudes: FFT bin magnitudes in dB — used for PHON/SONE
    ///   - bandsZ: 31 third-octave band levels (dB, Z-weighted) for per-band Leq EMA.
    ///             Pass empty to skip Z-band Leq update.
    ///   - bandsA: 31 third-octave band levels (dB, A-weighted). Pass empty when
    ///             A-weighting is not active this frame.
    ///   - bandsC: 31 third-octave band levels (dB, C-weighted). Pass empty when
    ///             C-weighting is not active this frame.
    ///   - loudnessReferenceKey: Broadband level key used for PHON/SONE (e.g. `"LAF"`,
    ///             `"LCF"`, `"LZF"`). Should match the active frequency weighting.
    /// - Returns: `MetricsResult` containing broadband levels and smoothed per-band Leq.
    func updateMetrics(
        energyZ: Float,
        energyA: Float,
        energyC: Float,
        peakLevel: Float,
        dt: Float,
        recordingDuration: TimeInterval,
        frequencies: [Float] = [],
        magnitudes: [Float] = [],
        bandsZ: [Float] = [],
        bandsA: [Float] = [],
        bandsC: [Float] = [],
        loudnessReferenceKey: String = "LZF",
        timeDomain: TimeDomainLevelMeter.Snapshot? = nil
    ) -> MetricsResult {

        var result = lock.withLockUnchecked { () -> MetricsResult in
            let frameDt = Double(max(dt, 0))
            if let td = timeDomain {
                // MC-3/MC-5: broadband levels come from the per-sample
                // time-domain meter; the FFT frame energies are ignored.
                lafEnergy = Float(td.lafEnergy); lasEnergy = Float(td.lasEnergy)
                lcfEnergy = Float(td.lcfEnergy); lcsEnergy = Float(td.lcsEnergy)
                lzfEnergy = Float(td.lzfEnergy); lzsEnergy = Float(td.lzsEnergy)
                laeqEnergyIntegral = td.laeqEnergy * td.elapsed
                laeqTotalTime = td.elapsed
                lafMax = TimeDomainLevelMeter.Snapshot.dB(td.lafMaxEnergy)
                lcPeakHold = TimeDomainLevelMeter.Snapshot.dB(td.lcPeakEnergy)
            } else {
                // Legacy frame-energy path (stored-data tooling / tests).
                let alphaFast = 1.0 - exp(-dt / TimeWeighting.fast.timeConstant)
                let alphaSlow = 1.0 - exp(-dt / TimeWeighting.slow.timeConstant)
                lafEnergy = (1.0 - alphaFast) * lafEnergy + alphaFast * energyA
                lasEnergy = (1.0 - alphaSlow) * lasEnergy + alphaSlow * energyA
                lcfEnergy = (1.0 - alphaFast) * lcfEnergy + alphaFast * energyC
                lcsEnergy = (1.0 - alphaSlow) * lcsEnergy + alphaSlow * energyC
                lzfEnergy = (1.0 - alphaFast) * lzfEnergy + alphaFast * energyZ
                lzsEnergy = (1.0 - alphaSlow) * lzsEnergy + alphaSlow * energyZ
                if frameDt > 0 {
                    laeqEnergyIntegral += Double(energyA) * frameDt
                    laeqTotalTime += frameDt
                }
                lcPeakHold = max(lcPeakHold, peakLevel)
            }

            // Calculate broadband level (LAF)
            let broadbandLevel = 10.0 * log10(lafEnergy + 1e-12)

            // Update min/max
            lafMin = min(lafMin, broadbandLevel)
            lafMax = max(lafMax, broadbandLevel)

            // Update histogram — clamp to valid range so no sample is silently lost.
            let histIndex = Int((broadbandLevel - histMinDB) * 10.0)
            let clampedIndex = max(0, min(Self.histBinCount - 1, histIndex))
            lafHistogram[clampedIndex] += 1
            lafTotalCounts += 1

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
                "LAeq": laeqTotalTime > 0
                    ? Float(10.0 * log10(laeqEnergyIntegral / laeqTotalTime + 1e-12))
                    : -120.0,
                "LAFmin": lafMin,
                "LAFmax": lafMax,
                "LCpeak": lcPeakHold,
                "LAFT5": currentTaktMax,
            ]

            // Percentiles: refreshed every `percentileInterval` frames.
            if lafTotalCounts > 0 {
                framesSincePercentile += 1
                if framesSincePercentile >= percentileInterval {
                    framesSincePercentile = 0
                    cachedLAF5 = calculatePercentile_locked(targetPercentage: 0.05)
                    cachedLAF95 = calculatePercentile_locked(targetPercentage: 0.95)
                }
                levels["LAF5"] = cachedLAF5
                levels["LAF95"] = cachedLAF95
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

            // Per-band Leq (MC-4): integrate unsmoothed band energy.
            func integrate(_ bands: [Float], into energy: inout [Double], time: inout Double) -> [Float] {
                guard !bands.isEmpty else { return [] }
                if energy.count != bands.count {
                    energy = [Double](repeating: 0, count: bands.count)
                    time = 0
                }
                let step = frameDt > 0 ? frameDt : 0
                if step > 0 {
                    for i in 0..<bands.count where bands[i].isFinite {
                        energy[i] += pow(10.0, Double(bands[i]) / 10.0) * step
                    }
                    time += step
                }
                guard time > 0 else { return bands }
                return energy.map { Float(10.0 * log10(max($0 / time, 1e-12))) }
            }
            let outLeqZ = integrate(bandsZ, into: &bandEnergyZ, time: &bandTimeZ)
            let outLeqA = integrate(bandsA, into: &bandEnergyA, time: &bandTimeA)
            let outLeqC = integrate(bandsC, into: &bandEnergyC, time: &bandTimeC)

            return MetricsResult(levels: levels,
                                 bandLeqZ: outLeqZ,
                                 bandLeqA: outLeqA,
                                 bandLeqC: outLeqC)
        } // end lock

        // Compute phon + sone outside the lock (pure math, no shared state).
        // Uses the static ISO 226 helpers on LoudnessCalculator so no instance
        // allocation occurs on the audio render thread.
        if !frequencies.isEmpty && !magnitudes.isEmpty {
            let freq = LoudnessCalculator.dominantFrequency(frequencies: frequencies, magnitudes: magnitudes)
            // MC-6: ISO 226 contours already model the ear's frequency
            // response — feed an unweighted (Z) level, not LAF (double
            // equal-loudness correction).
            let spl = Double(
                result.levels[loudnessReferenceKey]
                    ?? result.levels["LZF"]
                    ?? -120.0
            )
            let phonVal = LoudnessCalculator.phon(spl: spl, frequency: freq)
            result.levels["PHON"] = Float(phonVal)
            result.levels["SONE"] = Float(LoudnessCalculator.sone(phon: phonVal))
        }
        return result
    }

    /// Resets all metrics to initial state.
    ///
    /// **Thread**: may be called from any thread (typically main). The internal lock
    /// arbitrates against a concurrent `updateMetrics` call on the audio thread.
    func reset() {
        lock.withLockUnchecked {
            lafEnergy = 1e-12
            lasEnergy = 1e-12
            lcfEnergy = 1e-12
            lcsEnergy = 1e-12
            lzfEnergy = 1e-12
            lzsEnergy = 1e-12

            laeqEnergyIntegral = 0.0
            laeqTotalTime = 0.0

            lafMin = 1000.0
            lafMax = -1000.0
            lcPeakHold = -120.0

            lafHistogram = [Int](repeating: 0, count: Self.histBinCount)
            lafTotalCounts = 0

            currentTaktMax = -1000.0
            lastTaktTime = 0
            taktValues = []

            bandEnergyZ = []
            bandEnergyA = []
            bandEnergyC = []
            bandTimeZ = 0
            bandTimeA = 0
            bandTimeC = 0
            framesSincePercentile = Int.max / 2
            cachedLAF5 = -120.0
            cachedLAF95 = -120.0
        }
    }

    /// Returns current statistics summary.
    ///
    /// **Thread**: may be called from any thread. Acquires the lock for a brief read.
    func getStatistics() -> (laeqFast: Float, peak: Float, min: Float) {
        return lock.withLockUnchecked {
            (
                laeqFast: 10.0 * log10(lafEnergy + 1e-12),
                peak: lafMax,
                min: lafMin
            )
        }
    }
    
    // MARK: - Private Methods

    /// Calculates percentile from the histogram.
    ///
    /// **Must be called while holding `lock`** (i.e., from inside a
    /// `lock.withLockUnchecked` closure).
    ///
    /// - Parameter targetPercentage: Percentile to calculate (0.0 to 1.0)
    /// - Returns: Level in dB at the specified percentile
    private func calculatePercentile_locked(targetPercentage: Double) -> Float {
        let targetCount = Int(Double(lafTotalCounts) * targetPercentage)
        guard targetCount > 0 else { return histMinDB }
        var currentCount = 0

        // Iterate from high to low — returns the level exceeded by `targetPercentage`
        // of all frames (e.g. LAF5 = level exceeded 5% of the time, LAF95 = 95%).
        for i in stride(from: lafHistogram.count - 1, through: 0, by: -1) {
            currentCount += lafHistogram[i]
            if currentCount >= targetCount {
                return histMinDB + Float(i) / 10.0
            }
        }

        return histMinDB
    }
}
