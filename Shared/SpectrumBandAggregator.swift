import Foundation

/// Centralized 1/3-octave, octave, and Bark band aggregation for
/// display widgets.
///
/// Shared between iOS and watch targets. Extracted from
/// `SpectrumBandChartView` as part of M13 task-6 (DSP out of view
/// bodies). The math was previously duplicated between the engine
/// pre-compute path and the widget fallback — that drift caused the
/// M12 "negative offset" bug.
///
/// Conventions
/// -----------
/// All input/output magnitudes are in **dB SPL** (calibrated by the
/// AudioEngine pipeline before they reach view code). Band aggregation
/// is power-summation: each band's level is
/// `10 · log10(Σ 10^(bin_dB / 10))` over the bins falling inside the
/// band's edge frequencies — the conventional 1/3-octave SPL.
enum SpectrumBandAggregator {

    // MARK: - Canonical center frequencies (ISO-based)

    /// 31 third-octave centers from 20 Hz to 20 kHz.
    static let thirdOctaveCenters: [Float] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400,
        500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000,
        6300, 8000, 10000, 12500, 16000, 20000
    ]

    /// Display labels matching `thirdOctaveCenters` (1:1).
    static let thirdOctaveLabels: [String] = [
        "20", "25", "31.5", "40", "50", "63", "80", "100", "125", "160",
        "200", "250", "315", "400", "500", "630", "800", "1k", "1.25k", "1.6k",
        "2k", "2.5k", "3.15k", "4k", "5k", "6.3k", "8k", "10k", "12.5k", "16k", "20k"
    ]

    /// 10 octave centers from 31.5 Hz to 16 kHz, expressed as triplets of
    /// third-octave indices (into `thirdOctaveCenters`). Sums of three
    /// adjacent thirds in linear power give the octave SPL.
    static let octaveLabels: [String] = [
        "31.5", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"
    ]

    private static let octaveAsThirdIndices: [[Int]] = [
        [1, 2, 3],  [4, 5, 6],   [7, 8, 9],    [10, 11, 12], [13, 14, 15],
        [16, 17, 18], [19, 20, 21], [22, 23, 24], [25, 26, 27], [28, 29, 30]
    ]

    /// 24 Bark band edges (Hz) — standard psychoacoustic critical bands.
    static let barkEdges: [Float] = [
        20, 100, 200, 300, 400, 510, 630, 770, 920, 1080, 1270, 1480, 1720,
        2000, 2320, 2700, 3150, 3700, 4400, 5300, 6400, 7700, 9500, 12000, 15500
    ]

    // MARK: - Aggregation

    /// Aggregate a per-bin dB-SPL spectrum into 31 third-octave SPL
    /// values. This is the single canonical implementation — the
    /// engine's pre-compute path and the widget fallback both route
    /// here.
    ///
    /// - Parameters:
    ///   - frequencies: FFT bin centers (Hz). Must align 1:1 with
    ///     `spectrum`.
    ///   - spectrum: Per-bin dB-SPL magnitudes.
    /// - Returns: 31-element array of band SPL values in dB. Bands
    ///   that have no bins in range and lie above 250 Hz fall back to
    ///   −120 dB (silence floor). Bands ≤ 250 Hz use linear
    ///   interpolation between neighbours when the FFT resolution is
    ///   coarse.
    static func thirdOctaveBands(frequencies: [Float], spectrum: [Float]) -> [Float] {
        return aggregateBands(
            centerFrequencies: thirdOctaveCenters,
            frequencies: frequencies,
            spectrum: spectrum
        )
    }

    /// Aggregate a per-bin dB-SPL spectrum into 10 octave SPL values.
    /// If the caller already has third-octave bands from
    /// `thirdOctaveBands(...)`, pass them in `fromThirds:` to avoid
    /// recomputing — power-sums three adjacent thirds per octave.
    static func octaveBands(
        frequencies: [Float],
        spectrum: [Float],
        fromThirds precomputedThirds: [Float]? = nil
    ) -> [Float] {
        let thirds: [Float]
        if let pre = precomputedThirds, pre.count == thirdOctaveCenters.count {
            thirds = pre
        } else {
            thirds = thirdOctaveBands(frequencies: frequencies, spectrum: spectrum)
        }
        var result = [Float](repeating: -120.0, count: octaveAsThirdIndices.count)
        for (octaveIdx, indices) in octaveAsThirdIndices.enumerated() {
            var sumLinear: Float = 0
            for idx in indices where idx < thirds.count {
                sumLinear += pow(10, thirds[idx] / 10.0)
            }
            result[octaveIdx] = 10 * log10(max(sumLinear, 1e-10))
        }
        return result
    }

    private static let thirdOctaveLowerFactor: Float = pow(2.0 as Float, -1.0 / 6.0)
    private static let thirdOctaveUpperFactor: Float = pow(2.0 as Float, 1.0 / 6.0)

    /// Aggregate a per-bin dB-SPL spectrum into 24 Bark-band SPL values.
    /// Uses a single O(N + 24) two-pointer sweep since `barkEdges` is strictly
    /// increasing and contiguous.
    static func barkBands(frequencies: [Float], spectrum: [Float]) -> [Float] {
        let bandCount = barkEdges.count - 1
        var result = [Float](repeating: -120.0, count: bandCount)
        let limit = min(frequencies.count, spectrum.count)
        guard limit > 0 else { return result }

        var cursor = lowerBound(in: frequencies, range: 0..<limit, target: barkEdges[0])
        for i in 0..<bandCount {
            let lower = barkEdges[i]
            let upper = barkEdges[i + 1]
            while cursor < limit && frequencies[cursor] < lower {
                cursor += 1
            }
            var sumLinear: Float = 0
            var hasBin = false
            while cursor < limit && frequencies[cursor] < upper {
                sumLinear += pow(10, spectrum[cursor] / 10.0)
                hasBin = true
                cursor += 1
            }
            if hasBin {
                result[i] = 10 * log10(max(sumLinear, 1e-10))
            }
        }
        return result
    }

    // MARK: - Implementation

    /// Power-sum aggregation across band edges defined by
    /// 1/6-octave widths around each center frequency.
    private static func aggregateBands(
        centerFrequencies: [Float],
        frequencies: [Float],
        spectrum: [Float]
    ) -> [Float] {
        var bands = [Float](repeating: -120.0, count: centerFrequencies.count)
        let limit = min(frequencies.count, spectrum.count)
        guard limit > 0 else { return bands }

        let usableStart = lowerBound(in: frequencies, range: 0..<limit, target: 0.0)
        let usableEnd = upperBound(in: frequencies, range: usableStart..<limit, target: 20000.0)
        guard usableStart < usableEnd else { return bands }
        let usableRange = usableStart..<usableEnd

        let lowerFactor = thirdOctaveLowerFactor
        let upperFactor = thirdOctaveUpperFactor

        for (i, center) in centerFrequencies.enumerated() {
            let lower = center * lowerFactor
            let upper = center * upperFactor
            let startIdx = lowerBound(in: frequencies, range: usableRange, target: lower)
            var bandLinearSum: Float = 0.0
            var bandBinCount = 0

            var idx = startIdx
            while idx < usableEnd && frequencies[idx] < upper {
                bandLinearSum += pow(10.0, spectrum[idx] / 10.0)
                bandBinCount += 1
                idx += 1
            }

            if bandBinCount > 0 {
                // Band SPL = sum of linear bin powers, then back to dB
                // (conventional 1/3-octave SPL). Previously this site
                // and AudioEngine.computeDisplayThirdOctaveBands both
                // used mean-of-power, under-reporting by
                // 10·log10(bins-per-band). Fix landed in M12.
                bands[i] = 10.0 * log10(max(bandLinearSum, 1e-12))
                continue
            }

            // Coarse FFT grids miss narrow low-frequency 1/3-octave
            // bands. Fall back to linear interpolation between
            // neighbouring bins for centers ≤ 250 Hz; leave higher
            // centers at the silence floor (no artificial fill).
            if center <= 250.0 {
                bands[i] = interpolatedMagnitude(
                    targetFrequency: center,
                    frequencies: frequencies,
                    spectrum: spectrum,
                    usableRange: usableRange
                )
            } else {
                bands[i] = -120.0
            }
        }
        return bands
    }

    private static func interpolatedMagnitude(
        targetFrequency: Float,
        frequencies: [Float],
        spectrum: [Float],
        usableRange: Range<Int>
    ) -> Float {
        guard !usableRange.isEmpty else { return -120.0 }
        let first = usableRange.lowerBound
        let last = usableRange.upperBound - 1
        if targetFrequency <= frequencies[first] { return spectrum[first] }
        if targetFrequency >= frequencies[last] { return spectrum[last] }

        let upperIdx = lowerBound(in: frequencies, range: usableRange, target: targetFrequency)
        guard upperIdx > first, upperIdx <= last else {
            return spectrum[min(upperIdx, last)]
        }

        let lowerIdx = upperIdx - 1
        let f0 = frequencies[lowerIdx]
        let f1 = frequencies[upperIdx]
        if abs(f1 - f0) < 0.001 {
            return max(spectrum[lowerIdx], spectrum[upperIdx])
        }

        let t = (targetFrequency - f0) / (f1 - f0)
        return spectrum[lowerIdx] * (1.0 - t) + spectrum[upperIdx] * t
    }

    /// First index in `range` where `values[index] >= target`.
    private static func lowerBound(in values: [Float], range: Range<Int>, target: Float) -> Int {
        var lo = range.lowerBound
        var hi = range.upperBound
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if values[mid] < target {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    /// First index in `range` where `values[index] > target`.
    private static func upperBound(in values: [Float], range: Range<Int>, target: Float) -> Int {
        var lo = range.lowerBound
        var hi = range.upperBound
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if values[mid] <= target {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }
}
