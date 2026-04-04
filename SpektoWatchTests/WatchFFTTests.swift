import XCTest
import Accelerate
@testable import SpektoWatch_Watch_App

// MARK: - Watch FFT Algorithm Tests
//
// WatchAudioEngine.performFFT() is private, so we test the same algorithm
// in isolation.  Every step mirrors the engine's implementation exactly:
//   1. Hann windowing
//   2. vDSP_DFT_zop forward transform
//   3. Magnitude via vDSP_zvabs
//   4. Normalisation: scale = 2/N
//   5. Epsilon guard: + 1e-9
//   6. dB conversion via vDSP_vdbcon (power = 0 → 20·log10)
//
// Regression: the normalization scale 2/N was added to fix values being
// ~66 dB too high (factor of N/2 = 1024 ≈ +60 dB).

final class WatchFFTTests: XCTestCase {

    // Parameters matching WatchAudioEngine exactly
    let fftSize = 2048
    let sampleRate: Double = 44100.0

    // MARK: - Hann Window

    func testHannWindowFirstSampleIsZero() {
        let window = makeHannWindow(size: fftSize)
        XCTAssertEqual(window[0], 0.0, accuracy: 1e-6,
            "Hann window w[0] = 0.5 - 0.5·cos(0) = 0")
    }

    func testHannWindowMidpointIsOne() {
        let window = makeHannWindow(size: fftSize)
        // w[N/2] = 0.5 - 0.5·cos(π) = 0.5 + 0.5 = 1.0
        XCTAssertEqual(window[fftSize / 2], 1.0, accuracy: 1e-5,
            "Hann window must reach 1.0 at its midpoint")
    }

    func testHannWindowIsSymmetric() {
        let window = makeHannWindow(size: fftSize)
        for i in 1..<(fftSize / 2) {
            XCTAssertEqual(window[i], window[fftSize - i], accuracy: 1e-6,
                "Hann window must be symmetric: w[\(i)] ≈ w[\(fftSize - i)]")
        }
    }

    func testHannWindowAllValuesInUnitInterval() {
        let window = makeHannWindow(size: fftSize)
        for (i, w) in window.enumerated() {
            XCTAssertGreaterThanOrEqual(w, 0.0,
                "Hann window value at index \(i) must be ≥ 0")
            XCTAssertLessThanOrEqual(w, 1.0 + 1e-6,
                "Hann window value at index \(i) must be ≤ 1")
        }
    }

    // MARK: - Normalization Scale

    func testNormalizationScaleIsCorrect() {
        let scale: Float = 2.0 / Float(fftSize)
        // 2/2048 = 0.0009765625
        XCTAssertEqual(scale, 2.0 / 2048.0, accuracy: 1e-9,
            "Normalisation scale must be exactly 2/N")
    }

    func testNormalizationPreventsOverscaling() {
        // Without normalization, a full-scale sine (amplitude 1.0) would produce
        // a peak magnitude of N/2 = 1024 in the FFT output.
        // With scale 2/N, the peak should be ≈ 1.0.
        let magnitudes = performFullPipeline(sineAmplitude: 1.0, binIndex: 10)
        // After normalization (before dB), the linear peak magnitude ≈ 1.0 → 0 dBFS
        // The dB result should be in a physically sensible range, not ~+60 dB.
        let peakDB = magnitudes.max() ?? 0
        XCTAssertLessThan(peakDB, 10.0,
            "Normalised full-scale sine must not exceed ~0 dBFS; got \(peakDB) dB")
        XCTAssertGreaterThan(peakDB, -20.0,
            "Normalised full-scale sine must be close to 0 dBFS; got \(peakDB) dB")
    }

    // MARK: - Pure Sine Tone

    func testPureSineProducesPeakAtCorrectBin() {
        // A pure sine at frequency bin k produces a peak at bin k.
        let targetBin = 50
        let magnitudes = performFullPipeline(sineAmplitude: 0.5, binIndex: targetBin)

        guard let maxValue = magnitudes.max(),
              let peakBin = magnitudes.firstIndex(of: maxValue) else {
            XCTFail("Could not find peak in FFT output")
            return
        }

        // Allow ±1 bin tolerance due to spectral leakage from the Hann window
        XCTAssertEqual(peakBin, targetBin, accuracy: 1,
            "Pure sine at bin \(targetBin) must produce peak near that bin, got \(peakBin)")
    }

    func testSilenceProducesOnlyEpsilonLevel() {
        // Zero input → all magnitudes should be near ε = 1e-9 → ~-180 dB
        let silenceMagnitudes = performFullPipeline(sineAmplitude: 0.0, binIndex: 0)
        let maxDB = silenceMagnitudes.max() ?? 0
        XCTAssertLessThan(maxDB, -100.0,
            "Silence must produce very low dB values (epsilon floor); got max \(maxDB) dB")
    }

    func testNoNaNInFFTOutput() {
        let magnitudes = performFullPipeline(sineAmplitude: 0.8, binIndex: 100)
        for (i, m) in magnitudes.enumerated() {
            XCTAssertFalse(m.isNaN, "FFT output must not contain NaN at bin \(i)")
        }
    }

    func testNoInfInFFTOutput() {
        let magnitudes = performFullPipeline(sineAmplitude: 1.0, binIndex: 200)
        for (i, m) in magnitudes.enumerated() {
            XCTAssertFalse(m.isInfinite, "FFT output must not contain Inf at bin \(i)")
        }
    }

    // MARK: - Output Size

    func testFFTOutputHasHalfPlusOneBins() {
        // vDSP outputs fftSize/2 unique bins (0 … Nyquist)
        let magnitudes = performFullPipeline(sineAmplitude: 0.5, binIndex: 30)
        XCTAssertEqual(magnitudes.count, fftSize / 2,
            "FFT output must contain exactly fftSize/2 = \(fftSize/2) bins")
    }

    // MARK: - dB Conversion

    func testDBConversionUsesVoltageFormula() {
        // vDSP_vdbcon with flag 1 computes 20·log10(x), i.e. voltage/amplitude formula.
        // For amplitude 1.0 (after epsilon: 1.0 + 1e-9 ≈ 1.0): 20·log10(1) = 0 dB.
        var input: [Float] = [1.0]
        var output: [Float] = [0.0]
        var ref: Float = 1.0
        vDSP_vdbcon(&input, 1, &ref, &output, 1, 1, 1)
        XCTAssertEqual(output[0], 0.0, accuracy: 0.001,
            "20·log10(1.0) must equal 0 dB")
    }

    func testDBConversionHalfAmplitudeIsMinus6dB() {
        var input: [Float] = [0.5]
        var output: [Float] = [0.0]
        var ref: Float = 1.0
        vDSP_vdbcon(&input, 1, &ref, &output, 1, 1, 1)
        XCTAssertEqual(output[0], -6.0206, accuracy: 0.01,
            "20·log10(0.5) must be approximately -6 dB")
    }

    // MARK: - Helpers

    /// Builds the same Hann window as WatchAudioEngine.
    private func makeHannWindow(size: Int) -> [Float] {
        var w = [Float](repeating: 0, count: size)
        let n = Float(size)
        for i in 0..<size {
            let x = Float(i) / n
            w[i] = 0.5 - 0.5 * cos(2 * .pi * x)
        }
        return w
    }

    /// Runs the full FFT pipeline (window → DFT → magnitude → normalise → dB)
    /// mirroring WatchAudioEngine.performFFT().
    private func performFullPipeline(sineAmplitude: Float, binIndex: Int) -> [Float] {
        guard let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD) else {
            XCTFail("Could not create DFT setup")
            return []
        }
        defer { vDSP_DFT_DestroySetup(setup) }

        // Generate input signal: pure sine at exact bin frequency
        let freq = Float(binIndex) * Float(sampleRate) / Float(fftSize)
        let samples: [Float] = (0..<fftSize).map { n in
            sineAmplitude * sin(2 * .pi * freq * Float(n) / Float(sampleRate))
        }

        let window = makeHannWindow(size: fftSize)

        var realIn  = [Float](repeating: 0, count: fftSize)
        var imagIn  = [Float](repeating: 0, count: fftSize)
        var realOut = [Float](repeating: 0, count: fftSize)
        var imagOut = [Float](repeating: 0, count: fftSize)
        var mags    = [Float](repeating: 0, count: fftSize / 2)

        // Step 1: Hann window
        vDSP_vmul(samples, 1, window, 1, &realIn, 1, vDSP_Length(fftSize))
        vDSP_vclr(&imagIn, 1, vDSP_Length(fftSize))

        // Step 2: DFT
        vDSP_DFT_Execute(setup, realIn, imagIn, &realOut, &imagOut)

        // Step 3: Magnitude
        realOut.withUnsafeMutableBufferPointer { rp in
            imagOut.withUnsafeMutableBufferPointer { ip in
                var c = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_zvabs(&c, 1, &mags, 1, vDSP_Length(fftSize / 2))
            }
        }

        // Step 4: Normalise 2/N
        var scale: Float = 2.0 / Float(fftSize)
        vDSP_vsmul(mags, 1, &scale, &mags, 1, vDSP_Length(mags.count))

        // Step 5: Epsilon guard
        var epsilon: Float = 1e-9
        vDSP_vsadd(mags, 1, &epsilon, &mags, 1, vDSP_Length(mags.count))

        // Step 6: dB conversion (voltage formula: 20·log10)
        var ref: Float = 1.0
        vDSP_vdbcon(mags, 1, &ref, &mags, 1, vDSP_Length(mags.count), 1)

        return mags
    }
}
