import Foundation

/// M22 MC-3 / MC-5: IEC 61672-style broadband level meter in the **time
/// domain**, shared by iOS and watchOS so both platforms compute identically.
///
/// - A and C frequency weighting: analog IEC 61672-1 pole/zero layout
///   (f1 = 20.6 Hz ×2, f2 = 107.7 Hz, f3 = 737.9 Hz, f4 = 12 194 Hz ×2)
///   realised as cascaded first-order bilinear sections, normalised to 0 dB at
///   1 kHz.
/// - Fast/Slow exponential time weighting (125 ms / 1 s) applied **per
///   sample** to the squared weighted signal — no averaging over the FFT window
///   first (that smeared Fast and made LAFmax under-read).
/// - LAeq integrates the A-weighted squared samples over the elapsed time.
/// - LCpeak is the true peak of the C-weighted sample stream (it used to be
///   the largest C-weighted FFT bin, which could read below LCF).
///
/// Calibration convention: levels match the FFT path's established scale so
/// stored user/device calibration offsets stay valid. The FFT path's energy
/// for a Hann window is `2·(Σw²/N)·meanSquare = 0.75·meanSquare`; this meter
/// multiplies its mean-square energies (and peak²) by the same
/// `referenceEnergyFactor`.
///
/// Real-time safe after `init`: `process` allocates nothing and takes no lock.
/// Not thread-safe — call from one thread (the audio render thread), and
/// `reset` from that thread or while capture is stopped.
final class TimeDomainLevelMeter {
    /// See type documentation (Hann FFT reference scale).
    static let referenceEnergyFactor: Double = 0.75

    struct Snapshot: Equatable {
        /// Calibrated, time-weighted energies (linear power, dB SPL scale).
        var lafEnergy: Double
        var lasEnergy: Double
        var lcfEnergy: Double
        var lcsEnergy: Double
        var lzfEnergy: Double
        var lzsEnergy: Double
        /// Running maximum of the Fast A-weighted energy (sample resolution).
        var lafMaxEnergy: Double
        /// Calibrated LAeq energy (mean over all processed samples).
        var laeqEnergy: Double
        /// Calibrated peak power of the C-weighted signal (session hold).
        var lcPeakEnergy: Double
        /// Seconds of audio processed since the last reset.
        var elapsed: Double

        static func dB(_ energy: Double) -> Float {
            Float(10 * log10(max(energy, 1e-12)))
        }
    }

    /// One first-order IIR section `y = b0·x + b1·x1 − a1·y1`.
    private struct Section {
        var b0: Double, b1: Double, a1: Double
        var x1: Double = 0, y1: Double = 0

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + b1 * x1 - a1 * y1
            x1 = x
            y1 = y
            return y
        }

        mutating func clear() { x1 = 0; y1 = 0 }

        func response(at omega: Double) -> (re: Double, im: Double) {
            // H(e^{jω}) = (b0 + b1 e^{-jω}) / (1 + a1 e^{-jω})
            let c = cos(omega), s = sin(omega)
            let nr = b0 + b1 * c, ni = -b1 * s
            let dr = 1 + a1 * c, di = -a1 * s
            let den = dr * dr + di * di
            return ((nr * dr + ni * di) / den, (ni * dr - nr * di) / den)
        }
    }

    let sampleRate: Double
    private var cSections: [Section]
    private var aExtraSections: [Section]
    private let cGain: Double
    private let aGain: Double
    private let alphaFast: Double
    private let alphaSlow: Double

    private var lafE = 1e-12, lasE = 1e-12
    private var lcfE = 1e-12, lcsE = 1e-12
    private var lzfE = 1e-12, lzsE = 1e-12
    private var lafMaxE = 1e-12
    private var aEnergySum = 0.0
    private var sampleCount = 0
    private var cPeakSquared = 0.0

    init(sampleRate: Double) {
        let fs = max(1_000, sampleRate)
        self.sampleRate = fs
        let k = 2 * fs
        func w(_ f: Double) -> Double { 2 * .pi * f }
        func highpass(_ f: Double) -> Section {
            let om = w(f)
            return Section(b0: k / (k + om), b1: -k / (k + om), a1: (om - k) / (k + om))
        }
        // The 12.2 kHz double pole sits close to Nyquist: a plain bilinear
        // section warps it (−8 dB at 16 kHz). One matched-pole section (no
        // forced zero at Nyquist, errs high) plus one pre-warped bilinear
        // section (errs low) keep A and C within ±1.0 dB of the IEC 61672
        // table up to 16 kHz at 44.1/48 kHz.
        func lowpassMatched(_ f: Double) -> Section {
            let p = exp(-w(f) / fs)
            return Section(b0: 1 - p, b1: 0, a1: -p)
        }
        func lowpassPrewarped(_ f: Double) -> Section {
            let wd = 2 * fs * tan(.pi * min(f, fs * 0.49) / fs)
            return Section(b0: wd / (k + wd), b1: wd / (k + wd), a1: (wd - k) / (k + wd))
        }
        let f1 = 20.598997, f2 = 107.65265, f3 = 737.86223, f4 = 12_194.217
        let c = [highpass(f1), highpass(f1), lowpassMatched(f4), lowpassPrewarped(f4)]
        let aExtra = [highpass(f2), highpass(f3)]
        cSections = c
        aExtraSections = aExtra

        // Normalise to 0 dB at 1 kHz.
        let omega1k = 2 * .pi * 1_000 / fs
        func magnitude(_ sections: [Section]) -> Double {
            var re = 1.0, im = 0.0
            for section in sections {
                let r = section.response(at: omega1k)
                (re, im) = (re * r.re - im * r.im, re * r.im + im * r.re)
            }
            return sqrt(re * re + im * im)
        }
        cGain = 1 / magnitude(c)
        aGain = 1 / magnitude(c + aExtra)

        alphaFast = 1 - exp(-1 / (Double(TimeWeighting.fast.timeConstant) * fs))
        alphaSlow = 1 - exp(-1 / (Double(TimeWeighting.slow.timeConstant) * fs))
    }

    func reset() {
        for i in cSections.indices { cSections[i].clear() }
        for i in aExtraSections.indices { aExtraSections[i].clear() }
        lafE = 1e-12; lasE = 1e-12
        lcfE = 1e-12; lcsE = 1e-12
        lzfE = 1e-12; lzsE = 1e-12
        lafMaxE = 1e-12
        aEnergySum = 0
        sampleCount = 0
        cPeakSquared = 0
    }

    /// Processes one block of (gain-applied, uncalibrated) samples and returns
    /// calibrated levels. `calibrationOffset` is in dB (dB SPL = dBFS + offset).
    @discardableResult
    func process<C: Collection>(_ samples: C, gain: Float = 1, calibrationOffset: Float) -> Snapshot where C.Element == Float {
        let g = Double(gain)
        let aF = alphaFast, aS = alphaSlow
        for raw in samples {
            let x = Double(raw) * g
            var c = x
            for i in cSections.indices { c = cSections[i].process(c) }
            var a = c
            for i in aExtraSections.indices { a = aExtraSections[i].process(a) }
            c *= cGain
            a *= aGain

            let z2 = x * x, c2 = c * c, a2 = a * a
            lafE += aF * (a2 - lafE); lasE += aS * (a2 - lasE)
            lcfE += aF * (c2 - lcfE); lcsE += aS * (c2 - lcsE)
            lzfE += aF * (z2 - lzfE); lzsE += aS * (z2 - lzsE)
            if lafE > lafMaxE { lafMaxE = lafE }
            if c2 > cPeakSquared { cPeakSquared = c2 }
            aEnergySum += a2
        }
        sampleCount += samples.count
        return snapshot(calibrationOffset: calibrationOffset)
    }

    func snapshot(calibrationOffset: Float) -> Snapshot {
        let scale = Self.referenceEnergyFactor * pow(10, Double(calibrationOffset) / 10)
        return Snapshot(
            lafEnergy: lafE * scale,
            lasEnergy: lasE * scale,
            lcfEnergy: lcfE * scale,
            lcsEnergy: lcsE * scale,
            lzfEnergy: lzfE * scale,
            lzsEnergy: lzsE * scale,
            lafMaxEnergy: lafMaxE * scale,
            laeqEnergy: sampleCount > 0 ? aEnergySum / Double(sampleCount) * scale : 1e-12,
            lcPeakEnergy: cPeakSquared * scale,
            elapsed: Double(sampleCount) / sampleRate
        )
    }

    /// Magnitude of the A (`weighting == .a`) or C weighting at `frequency` in
    /// dB (for tests against the IEC 61672 table).
    func weightingResponseDB(_ weighting: FrequencyWeighting, at frequency: Double) -> Double {
        let omega = 2 * .pi * frequency / sampleRate
        let sections = weighting == .a ? cSections + aExtraSections : cSections
        var re = 1.0, im = 0.0
        for section in sections {
            let r = section.response(at: omega)
            (re, im) = (re * r.re - im * r.im, re * r.im + im * r.re)
        }
        let gain = weighting == .a ? aGain : cGain
        return 20 * log10(sqrt(re * re + im * im) * gain)
    }
}
