import Foundation
import Accelerate
import os.signpost
import os.lock

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

    // Cached bandstop attenuation in dB. Recomputed only when the filter set or
    // bin count changes — replaces a per-bin `20*log10(...)` call on every frame.
    // The hot path becomes a single vDSP_vadd (transition zones), plus a small
    // O(blocked-bin) sweep that clamps fully-blocked bins to -120 dB.
    private var cachedBandstopFilterSnapshot: [BandstopFilter] = []
    private var cachedBandstopAttenuationDB: [Float] = []   // 0 for passthrough, <0 in transition zones
    private var cachedBandstopBlockedIndices: [Int] = []    // bins fully attenuated → set to -120 dB
    private var cachedBandstopFrequencyCount: Int = 0
    // Track the FFT bin layout so we invalidate the cache if sample-rate or
    // FFT size changes the actual Hz mapping (count alone isn't enough — same
    // count can map to different frequencies under a sample-rate switch).
    private var cachedBandstopFreqFirst: Float = .nan
    private var cachedBandstopFreqLast: Float = .nan

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
        let enabledFilters = bandstopFilterManager.snapshotEnabledFilters()
        guard !enabledFilters.isEmpty else {
            return magnitudes
        }

        ensureBandstopAttenuationCache(for: frequencies, enabledFilters: enabledFilters)

        // Common path: vector add of cached attenuation in dB (mostly zeros, negative
        // in narrow transition zones). Constant per-frame work, no log10 calls.
        let count = min(magnitudes.count, cachedBandstopAttenuationDB.count)
        var filtered = magnitudes
        cachedBandstopAttenuationDB.withUnsafeBufferPointer { attBuf in
            filtered.withUnsafeMutableBufferPointer { dst in
                vDSP_vadd(dst.baseAddress!, 1, attBuf.baseAddress!, 1,
                          dst.baseAddress!, 1, vDSP_Length(count))
            }
        }
        // Force fully-blocked bins to the floor. Index list is empty for the
        // common case where no filter has a passband (i.e. always non-empty here,
        // since enabledFilters != []), but kept short by the transition-zone math.
        for idx in cachedBandstopBlockedIndices where idx < count {
            filtered[idx] = -120.0
        }
        return filtered
    }

    /// Recomputes `cachedBandstopAttenuationDB` and `cachedBandstopBlockedIndices`
    /// only when the filter set or bin count changes. Stores attenuation in dB so
    /// the hot path does not call `log10`.
    private func ensureBandstopAttenuationCache(
        for frequencies: [Float],
        enabledFilters: [BandstopFilter]
    ) {
        let count = frequencies.count
        let first = count > 0 ? frequencies[0] : .nan
        let last  = count > 0 ? frequencies[count - 1] : .nan
        if count == cachedBandstopFrequencyCount,
           first == cachedBandstopFreqFirst,
           last  == cachedBandstopFreqLast,
           enabledFilters == cachedBandstopFilterSnapshot {
            return
        }

        var linearMap = [Float](repeating: 1.0, count: count)
        for filter in enabledFilters {
            let bandwidth = filter.highFrequency - filter.lowFrequency
            let transitionWidth = min(bandwidth * 0.1, 20.0)
            let minFreq = filter.lowFrequency - transitionWidth
            let maxFreq = filter.highFrequency + transitionWidth

            let startIndex = frequencies.partitionPoint { $0 < minFreq }
            let endIndex = frequencies.partitionPoint { $0 <= maxFreq }
            guard startIndex < endIndex else { continue }

            for i in startIndex..<endIndex {
                let freq = frequencies[i]
                let attenuation: Float
                if freq >= filter.lowFrequency && freq <= filter.highFrequency {
                    attenuation = 0.0
                } else if freq >= minFreq && freq < filter.lowFrequency {
                    let position = (freq - minFreq) / transitionWidth
                    attenuation = (1.0 + cos(position * .pi)) / 2.0
                } else if freq > filter.highFrequency && freq <= maxFreq {
                    let position = (freq - filter.highFrequency) / transitionWidth
                    attenuation = (1.0 - cos(position * .pi)) / 2.0
                } else {
                    attenuation = 1.0
                }
                linearMap[i] *= attenuation
            }
        }

        var attenDB = [Float](repeating: 0, count: count)
        var blocked: [Int] = []
        for i in 0..<count {
            let a = linearMap[i]
            if a < 0.01 {
                blocked.append(i)        // force to -120 in hot path
                // attenDB[i] stays 0 — vDSP_vadd would be a no-op; the index sweep
                // overwrites the bin anyway.
            } else if a < 1.0 {
                attenDB[i] = 20 * log10(a)
            }
            // else: a == 1.0, attenDB[i] = 0, vector add is a no-op
        }

        cachedBandstopAttenuationDB = attenDB
        cachedBandstopBlockedIndices = blocked
        cachedBandstopFrequencyCount = count
        cachedBandstopFreqFirst = first
        cachedBandstopFreqLast = last
        cachedBandstopFilterSnapshot = enabledFilters
    }
    
    private func calculateOctaveBands(frequencies: [Float], magnitudes: [Float], sampleRate: Double) -> [Float] {
        guard !magnitudes.isEmpty else {
            return [Float](repeating: -120.0, count: octaveCenterFrequencies.count)
        }

        ensureOctaveBandRanges(magnitudeCount: magnitudes.count, sampleRate: sampleRate)
        var bands = [Float](repeating: -120.0, count: octaveCenterFrequencies.count)

        let magCount = magnitudes.count
        magnitudes.withUnsafeBufferPointer { magBuf in
            for (i, range) in cachedOctaveRanges.enumerated() {
                guard range.start <= range.end, range.end < magCount else { continue }
                var bandMax: Float = -120.0
                vDSP_maxv(magBuf.baseAddress!.advanced(by: range.start), 1,
                          &bandMax, vDSP_Length(range.end - range.start + 1))
                bands[i] = bandMax
            }
        }
        return bands
    }
    
    private func aggregateByBinningFactor(frequencies: [Float], magnitudes: [Float]) -> ([Float], [Float]) {
        guard binningFactor > 1 else { return (frequencies, magnitudes) }

        let inputCount = frequencies.count
        let outputCount = (inputCount + binningFactor - 1) / binningFactor
        var bandFrequencies = [Float](repeating: 0, count: outputCount)
        var bandMagnitudes = [Float](repeating: 0, count: outputCount)

        // Index-based fill into pre-allocated arrays — avoids the per-bucket
        // `.append()` (which triggers CoW grow) on every FFT frame × 3 tracks.
        var out = 0
        var i = 0
        while i < inputCount {
            let endIndex = min(i + binningFactor, inputCount)
            let binCount = endIndex - i
            var frequencySum: Float = 0.0
            var magnitudeSum: Float = 0.0
            for idx in i..<endIndex {
                frequencySum += frequencies[idx]
                magnitudeSum += magnitudes[idx]
            }
            let inv = 1.0 / Float(binCount)
            bandFrequencies[out] = frequencySum * inv
            bandMagnitudes[out]  = magnitudeSum  * inv
            out += 1
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

        // One-third-octave band edges: center × 2^(±1/6). The diagnostic path
        // already uses these exact factors; the previous 0.89/1.12 constants
        // diverged by ~0.2% at the band edge and caused near-edge tones to be
        // attributed to different bands between the two code paths.
        let lowerFactor = pow(2.0 as Float, -1.0 / 6.0)
        let upperFactor = pow(2.0 as Float,  1.0 / 6.0)
        for center in octaveCenterFrequencies {
            let lower = center * lowerFactor
            let upper = center * upperFactor
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
    
    // IEC 61672 EMA time-weighting on FFT measurement values (dB).
    //
    // Pipeline position: runs on binned FFT dB magnitudes; output is stored in
    // SpectrogramProcessor.Result.bandMagnitudes. Consumers: third-octave bands,
    // acoustic metrics, recording, and the spectrogram visual fallback path.
    //
    // This does NOT feed the live spectrogram texture in normal operation.
    // HighEndSpectrogramAdapter prefers SpectrogramData.visualMagnitudes (DCT/Mel,
    // no EMA) over .magnitudes (EMA-smoothed FFT). The Metal shader's Gaussian
    // blur (HighEndSpectrogramShaders.metal) is a separate display-only pass on
    // the already-written texture columns — the two smoothing layers operate on
    // independent data paths and do NOT stack in normal live rendering (R10).
    //
    // temporalSmoothingIntensity (0=raw, 1=full IEC weighting) is the user knob
    // exposed in SpectrogramSettingsView.
    private func temporalSmoothing(currentMagnitudes: [Float], track: SmoothingTrack) -> [Float] {
        guard let previousBandMagnitudes = previousBandMagnitudesByTrack[track],
              previousBandMagnitudes.count == currentMagnitudes.count else {
            previousBandMagnitudesByTrack[track] = currentMagnitudes
            return currentMagnitudes
        }
        // IEC 61672: α = 1 − exp(−dt / τ), τ = 0.125 s (Fast) or 1.0 s (Slow)
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

struct MelSpectrogramProcessor {
    let filterBankCount: Int
    let fftBinCount: Int
    let sampleRate: Double
    let frequencyRange: ClosedRange<Float>
    private let filterBank: [Float]

    init(
        filterBankCount: Int = 40,
        fftBinCount: Int,
        sampleRate: Double,
        frequencyRange: ClosedRange<Float>? = nil
    ) {
        self.filterBankCount = max(1, filterBankCount)
        self.fftBinCount = max(1, fftBinCount)
        self.sampleRate = sampleRate

        let nyquist = Float(max(1.0, sampleRate / 2.0))
        let lower = max(0, frequencyRange?.lowerBound ?? 20)
        let upper = min(nyquist, max(lower + 1, frequencyRange?.upperBound ?? min(20_000, nyquist)))
        self.frequencyRange = lower...upper
        self.filterBank = Self.makeFilterBank(
            filterBankCount: self.filterBankCount,
            fftBinCount: self.fftBinCount,
            nyquist: nyquist,
            frequencyRange: self.frequencyRange
        )
    }

    func compute(linearMagnitudes: [Float]) -> [Float] {
        var output: [Float] = []
        compute(linearMagnitudes: linearMagnitudes, into: &output)
        return output
    }

    func compute(linearMagnitudes: [Float], into output: inout [Float]) {
        if output.count != filterBankCount {
            output = [Float](repeating: 0, count: filterBankCount)
        }
        guard linearMagnitudes.count >= fftBinCount else {
            vDSP_vclr(&output, 1, vDSP_Length(output.count))
            return
        }

        filterBank.withUnsafeBufferPointer { filterPtr in
            linearMagnitudes.withUnsafeBufferPointer { inputPtr in
                output.withUnsafeMutableBufferPointer { outputPtr in
                    vDSP_mmul(
                        filterPtr.baseAddress!,
                        1,
                        inputPtr.baseAddress!,
                        1,
                        outputPtr.baseAddress!,
                        1,
                        vDSP_Length(filterBankCount),
                        1,
                        vDSP_Length(fftBinCount)
                    )
                }
            }
        }
    }

    static func frequencyToMel(_ frequency: Float) -> Float {
        2595.0 * log10(1.0 + frequency / 700.0)
    }

    static func melToFrequency(_ mel: Float) -> Float {
        700.0 * (pow(10.0, mel / 2595.0) - 1.0)
    }

    private static func makeFilterBank(
        filterBankCount: Int,
        fftBinCount: Int,
        nyquist: Float,
        frequencyRange: ClosedRange<Float>
    ) -> [Float] {
        let pointCount = filterBankCount + 2
        let minMel = frequencyToMel(frequencyRange.lowerBound)
        let maxMel = frequencyToMel(frequencyRange.upperBound)
        let step = (maxMel - minMel) / Float(max(pointCount - 1, 1))

        var binPoints = (0..<pointCount).map { index -> Int in
            let mel = minMel + Float(index) * step
            let frequency = melToFrequency(mel)
            let normalized = frequency / max(nyquist, 1)
            return max(0, min(fftBinCount - 1, Int((normalized * Float(fftBinCount - 1)).rounded())))
        }

        for index in 1..<binPoints.count {
            if binPoints[index] <= binPoints[index - 1] {
                binPoints[index] = min(fftBinCount - 1, binPoints[index - 1] + 1)
            }
        }

        var bank = [Float](repeating: 0, count: filterBankCount * fftBinCount)
        bank.withUnsafeMutableBufferPointer { bankPtr in
            guard let base = bankPtr.baseAddress else { return }
            for filterIndex in 0..<filterBankCount {
                let left = binPoints[filterIndex]
                let center = binPoints[filterIndex + 1]
                let right = binPoints[filterIndex + 2]
                let row = base.advanced(by: filterIndex * fftBinCount)

                if center > left {
                    var start: Float = 0
                    var end: Float = 1
                    vDSP_vgen(&start, &end, row.advanced(by: left), 1, vDSP_Length(center - left + 1))
                }
                if right > center {
                    var start: Float = 1
                    var end: Float = 0
                    vDSP_vgen(&start, &end, row.advanced(by: center), 1, vDSP_Length(right - center + 1))
                }
            }
        }
        return bank
    }
}

/// Visualisierungspfad nach Apple "Visualizing Sound as an Audio Spectrogram":
/// gefenstertes Audio → DCT-II → |.| → 2/N Skalierung → Mel-Filterbank →
/// 20·log10 → +Kalibrierungsoffset. Wenn `melBandCount == 0` setzt der Prozessor
/// die Mel-Stufe aus und gibt die linearen DCT-Bins zurück (Legacy-Modus,
/// nützlich für Tests und Debug-Vergleiche).
final class VisualSpectrogramProcessor {
    private let lock = OSAllocatedUnfairLock()
    private var transformSize: Int
    private var sampleRate: Double
    private var windowFunction: WindowFunction
    private var melBandCount: Int
    private var frequencyRange: ClosedRange<Float>
    private var dct: vDSP.DCT?
    private var window: [Float]
    private var windowedSamples: [Float]
    private var coefficients: [Float]
    private var linearMagnitudes: [Float]
    private var melScratch: [Float]
    private var melProcessor: MelSpectrogramProcessor?
    private var frequencies: [Float]

    init(
        transformSize: Int,
        sampleRate: Double,
        windowFunction: WindowFunction = .hann,
        melBandCount: Int = 128,
        frequencyRange: ClosedRange<Float> = 20...20_000
    ) {
        let safeSize = max(16, transformSize)
        let safeMel = max(0, melBandCount)
        self.transformSize = safeSize
        self.sampleRate = sampleRate
        self.windowFunction = windowFunction
        self.melBandCount = safeMel
        self.frequencyRange = frequencyRange
        self.dct = vDSP.DCT(count: safeSize, transformType: .II)
        self.window = windowFunction.generate(size: safeSize)
        self.windowedSamples = [Float](repeating: 0, count: safeSize)
        self.coefficients = [Float](repeating: 0, count: safeSize)
        self.linearMagnitudes = [Float](repeating: 0, count: safeSize)

        if safeMel > 0 {
            let mel = MelSpectrogramProcessor(
                filterBankCount: safeMel,
                fftBinCount: safeSize,
                sampleRate: sampleRate,
                frequencyRange: frequencyRange
            )
            self.melProcessor = mel
            self.melScratch = [Float](repeating: 0, count: safeMel)
            self.frequencies = Self.makeMelFrequencies(
                filterBankCount: safeMel,
                frequencyRange: mel.frequencyRange
            )
        } else {
            self.melProcessor = nil
            self.melScratch = []
            self.frequencies = Self.makeLinearFrequencies(transformSize: safeSize, sampleRate: sampleRate)
        }
    }

    var outputBinCount: Int {
        lock.withLockUnchecked { melBandCount > 0 ? melBandCount : transformSize }
    }

    func currentFrequencies() -> [Float] {
        lock.withLockUnchecked { frequencies }
    }

    func reconfigure(
        transformSize newSize: Int,
        sampleRate newSampleRate: Double,
        windowFunction newWindow: WindowFunction,
        melBandCount newMelCount: Int? = nil,
        frequencyRange newRange: ClosedRange<Float>? = nil
    ) {
        lock.withLockUnchecked {
            let safeSize = max(16, newSize)
            let resolvedMel = max(0, newMelCount ?? melBandCount)
            let resolvedRange = newRange ?? frequencyRange

            let sizeChanged = safeSize != transformSize
            let sampleRateChanged = abs(newSampleRate - sampleRate) > 1.0
            let windowChanged = newWindow != windowFunction
            let melCountChanged = resolvedMel != melBandCount
            let rangeChanged = resolvedRange != frequencyRange

            guard sizeChanged || sampleRateChanged || windowChanged || melCountChanged || rangeChanged else {
                return
            }

            transformSize = safeSize
            sampleRate = newSampleRate
            windowFunction = newWindow
            melBandCount = resolvedMel
            frequencyRange = resolvedRange

            dct = vDSP.DCT(count: safeSize, transformType: .II)
            window = newWindow.generate(size: safeSize)
            windowedSamples = [Float](repeating: 0, count: safeSize)
            coefficients = [Float](repeating: 0, count: safeSize)
            linearMagnitudes = [Float](repeating: 0, count: safeSize)

            if resolvedMel > 0 {
                let mel = MelSpectrogramProcessor(
                    filterBankCount: resolvedMel,
                    fftBinCount: safeSize,
                    sampleRate: newSampleRate,
                    frequencyRange: resolvedRange
                )
                melProcessor = mel
                melScratch = [Float](repeating: 0, count: resolvedMel)
                frequencies = Self.makeMelFrequencies(
                    filterBankCount: resolvedMel,
                    frequencyRange: mel.frequencyRange
                )
            } else {
                melProcessor = nil
                melScratch = []
                frequencies = Self.makeLinearFrequencies(transformSize: safeSize, sampleRate: newSampleRate)
            }
        }
    }

    /// Berechnet die dB-Magnituden für den Visualpfad. Liefert die
    /// Frequenzbeschriftung der Ausgabe zurück (Mel-Zentren oder lineare
    /// DCT-Bins, je nach Konfiguration). `output` wird auf die korrekte Länge
    /// gebracht (Mel-Bandzahl oder Transformgröße).
    func computeDBMagnitudes(
        on samples: [Float],
        gainBoost: Float,
        calibrationOffset: Float,
        into output: inout [Float]
    ) -> [Float] {
        lock.withLockUnchecked {
            let bandCount = melBandCount > 0 ? melBandCount : transformSize
            if output.count != bandCount {
                output = [Float](repeating: -120, count: bandCount)
            }

            guard samples.count >= transformSize, let dct else {
                var floor: Float = -120
                vDSP_vfill(&floor, &output, 1, vDSP_Length(output.count))
                return frequencies
            }

            // 1) Hann-Fenster × Samples
            vDSP_vmul(samples, 1, window, 1, &windowedSamples, 1, vDSP_Length(transformSize))

            // 2) optionaler Gain (Mic-Pre-Boost) zieht in den DCT-Eingang
            if gainBoost != 1.0 {
                var gain = gainBoost
                vDSP_vsmul(windowedSamples, 1, &gain, &windowedSamples, 1, vDSP_Length(transformSize))
            }

            // 3) DCT-II → reelle Koeffizienten, |.| → lineare Magnituden
            dct.transform(windowedSamples, result: &coefficients)
            vDSP_vabs(coefficients, 1, &linearMagnitudes, 1, vDSP_Length(transformSize))

            // 4) 2/N Skalierung (vDSP DCT-II gibt unskalierte Koeffizienten zurück)
            var scale = 2.0 / Float(transformSize)
            vDSP_vsmul(linearMagnitudes, 1, &scale, &linearMagnitudes, 1, vDSP_Length(transformSize))

            // 5) Mel-Filterbank (oder Pass-through im Legacy-Modus)
            if let melProcessor {
                melProcessor.compute(linearMagnitudes: linearMagnitudes, into: &melScratch)
                var lo: Float = 1e-10
                var hi = Float.greatestFiniteMagnitude
                vDSP_vclip(melScratch, 1, &lo, &hi, &output, 1, vDSP_Length(bandCount))
            } else {
                var lo: Float = 1e-10
                var hi = Float.greatestFiniteMagnitude
                vDSP_vclip(linearMagnitudes, 1, &lo, &hi, &output, 1, vDSP_Length(bandCount))
            }

            // 6) 20·log10 → dB-Amplitude
            var count = Int32(bandCount)
            vvlog10f(&output, output, &count)

            var dbScale: Float = 20.0
            vDSP_vsmul(output, 1, &dbScale, &output, 1, vDSP_Length(bandCount))

            // 7) Kalibrierung in dB SPL
            var offset = calibrationOffset
            vDSP_vsadd(output, 1, &offset, &output, 1, vDSP_Length(bandCount))
            return frequencies
        }
    }

    private static func makeLinearFrequencies(transformSize: Int, sampleRate: Double) -> [Float] {
        let nyquist = Float(sampleRate / 2.0)
        return (0..<transformSize).map { Float($0) * nyquist / Float(max(transformSize - 1, 1)) }
    }

    /// Mel-Bandzentren in Hz, kompatibel mit
    /// `MelSpectrogramProcessor.makeFilterBank` (pointCount = bands + 2,
    /// gleichmäßig in Mel-Skala). Wird als `visualFrequencies` an Consumer
    /// (HighEndSpectrogramAdapter, WaterfallView, Export) weitergereicht.
    private static func makeMelFrequencies(
        filterBankCount: Int,
        frequencyRange: ClosedRange<Float>
    ) -> [Float] {
        let pointCount = filterBankCount + 2
        let minMel = MelSpectrogramProcessor.frequencyToMel(frequencyRange.lowerBound)
        let maxMel = MelSpectrogramProcessor.frequencyToMel(frequencyRange.upperBound)
        let step = (maxMel - minMel) / Float(max(pointCount - 1, 1))
        return (0..<filterBankCount).map { i in
            let mel = minMel + Float(i + 1) * step
            return MelSpectrogramProcessor.melToFrequency(mel)
        }
    }
}
