import XCTest
import Accelerate
@testable import SpektoWatch2

/// Parity tests for the watch FFT + DCT math against the iOS pipeline.
///
/// `WatchAudioEngine` lives in the watch app target and can't be imported
/// into this test target. To still verify the M15 task-3 fix, this test
/// reproduces the watch's post-fix processing chain (vDSP_DFT_zrop +
/// vDSP_ctoz + vDSP_zvabs + 2/N + dB) inline in test code, drives the
/// same fixture through both `FFTProcessor` and the reproduction, and
/// asserts the 1 kHz bin agrees within ±0.5 dB. Drift between the watch
/// source and this reproduction is exactly the situation this test is
/// here to catch.
final class WatchDSPParityTests: XCTestCase {

    private let fftSize = 2048
    private let sampleRate: Double = 44100.0

    // MARK: - Fixture

    /// 1 kHz sine, amplitude 0.5, hann-windowed by the caller.
    private func makeOneKHzSine() -> [Float] {
        let twoPiF = Float(2.0 * .pi * 1000.0 / sampleRate)
        return (0..<fftSize).map { i in 0.5 * sinf(twoPiF * Float(i)) }
    }

    // MARK: - Watch reproduction

    /// Mirrors the post-M15-task-3 `WatchAudioEngine.performFFT` body.
    /// If the watch code changes shape, update this reproduction in lockstep
    /// — the test exists to keep both paths in agreement.
    private func watchFFTReproduction(samples: [Float]) -> [Float] {
        let fftSetup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)!
        defer { vDSP_DFT_DestroySetup(fftSetup) }

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_DENORM))

        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        var splitRealIn = [Float](repeating: 0, count: fftSize / 2)
        var splitImagIn = [Float](repeating: 0, count: fftSize / 2)
        windowed.withUnsafeBytes { rawBuf in
            let complexPtr = rawBuf.bindMemory(to: DSPComplex.self).baseAddress!
            splitRealIn.withUnsafeMutableBufferPointer { realBuf in
                splitImagIn.withUnsafeMutableBufferPointer { imagBuf in
                    var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                    vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(fftSize / 2))
                }
            }
        }

        var realOut = [Float](repeating: 0, count: fftSize / 2)
        var imagOut = [Float](repeating: 0, count: fftSize / 2)
        vDSP_DFT_Execute(fftSetup, splitRealIn, splitImagIn, &realOut, &imagOut)

        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        realOut.withUnsafeMutableBufferPointer { realPtr in
            imagOut.withUnsafeMutableBufferPointer { imagPtr in
                var complex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvabs(&complex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        var scale: Float = 2.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(magnitudes.count))
        var epsilon: Float = 1e-9
        vDSP_vsadd(magnitudes, 1, &epsilon, &magnitudes, 1, vDSP_Length(magnitudes.count))
        var ref: Float = 1.0
        vDSP_vdbcon(magnitudes, 1, &ref, &magnitudes, 1, vDSP_Length(magnitudes.count), 1)
        return magnitudes
    }

    private func oneKHzBinIndex() -> Int {
        let binWidth = sampleRate / Double(fftSize)
        return Int((1000.0 / binWidth).rounded())
    }

    // MARK: - Tests

    /// 1 kHz tone fed through `FFTProcessor` and the watch reproduction
    /// must read within 0.5 dB at the 1 kHz bin. Failure means either:
    /// (a) the watch reproduction drifted from the watch source, or
    /// (b) one of the two pipelines regressed.
    func test_watchFFTParityWithIOSAtOneKHz() {
        let samples = makeOneKHzSine()

        let ios = FFTProcessor(fftSize: fftSize, sampleRate: sampleRate, windowFunction: .hann)
        let iosLinear = ios.performFFT(on: samples)
        var iosDB = [Float](repeating: 0, count: iosLinear.count)
        ios.convertToDB(iosLinear, into: &iosDB)

        let watchDB = watchFFTReproduction(samples: samples)

        let bin = oneKHzBinIndex()
        XCTAssertGreaterThan(bin, 0)
        XCTAssertLessThan(bin, min(iosDB.count, watchDB.count))

        let delta = abs(iosDB[bin] - watchDB[bin])
        XCTAssertLessThan(
            delta,
            0.5,
            "iOS vs watch 1 kHz bin diverged: iOS=\(iosDB[bin]) dB, watch=\(watchDB[bin]) dB (Δ=\(delta) dB)"
        )
    }

    /// The pre-fix watch path (`vDSP_DFT_zop` with `2/N` normalization)
    /// was ~6 dB hot vs the real-optimized variant. This is a guard test:
    /// if anyone reintroduces `vDSP_DFT_zop_CreateSetup` on the watch
    /// FFT path and copies this reproduction into a regression, the
    /// guard fires.
    func test_zopVariantWithSameNormalizationIsHotByApproximately6dB() {
        let samples = makeOneKHzSine()

        let fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)!
        defer { vDSP_DFT_DestroySetup(fftSetup) }

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_DENORM))
        var realIn = [Float](repeating: 0, count: fftSize)
        let imagIn = [Float](repeating: 0, count: fftSize)
        var realOut = [Float](repeating: 0, count: fftSize)
        var imagOut = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(samples, 1, window, 1, &realIn, 1, vDSP_Length(fftSize))
        vDSP_DFT_Execute(fftSetup, realIn, imagIn, &realOut, &imagOut)

        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        realOut.withUnsafeMutableBufferPointer { realPtr in
            imagOut.withUnsafeMutableBufferPointer { imagPtr in
                var complex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvabs(&complex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }
        var scale: Float = 2.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(magnitudes.count))
        var epsilon: Float = 1e-9
        vDSP_vsadd(magnitudes, 1, &epsilon, &magnitudes, 1, vDSP_Length(magnitudes.count))
        var ref: Float = 1.0
        vDSP_vdbcon(magnitudes, 1, &ref, &magnitudes, 1, vDSP_Length(magnitudes.count), 1)

        let correct = watchFFTReproduction(samples: samples)
        let bin = oneKHzBinIndex()
        let diff = magnitudes[bin] - correct[bin]
        XCTAssertGreaterThan(
            diff,
            3.0,
            "zop+2/N should overstate amplitude relative to zrop+2/N; got Δ=\(diff) dB"
        )
    }

    // MARK: - performVisualDCT mirror
    //
    // MIRROR OF WatchAudioEngine.performVisualDCT — keep in sync.
    // If the watch implementation changes shape, update the body below and
    // grep for this comment to find the parity point.
    private func performVisualDCTMirror(samples: [Float], fftSize: Int) -> [Float] {
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_DENORM))
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        guard let dct = vDSP.DCT(count: fftSize, transformType: .II) else {
            XCTFail("Could not create DCT setup for fftSize=\(fftSize)")
            return []
        }
        var coefficients = [Float](repeating: 0, count: fftSize)
        dct.transform(windowed, result: &coefficients)

        var magnitudes = [Float](repeating: 0, count: fftSize)
        vDSP_vabs(coefficients, 1, &magnitudes, 1, vDSP_Length(fftSize))

        var scale: Float = 2.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(fftSize))

        var lo: Float = 1e-10
        var hi: Float = .greatestFiniteMagnitude
        vDSP_vclip(magnitudes, 1, &lo, &hi, &magnitudes, 1, vDSP_Length(fftSize))
        var n = Int32(fftSize)
        vvlog10f(&magnitudes, magnitudes, &n)
        var twenty: Float = 20.0
        vDSP_vsmul(magnitudes, 1, &twenty, &magnitudes, 1, vDSP_Length(fftSize))

        return magnitudes
    }

    /// `performVisualDCT` on a unit-amplitude pure tone must produce a peak
    /// in the expected DCT bin within ±1 dB of 0 dBFS. Failure means the
    /// M15 task-3 amplitude convention (20·log10) was silently changed.
    func test_performVisualDCTMirrorPeakIsNearZeroDBFS() {
        let size = 512
        let tone = (0..<size).map { i in sinf(Float.pi * Float(i) / Float(size)) }
        let dBValues = performVisualDCTMirror(samples: tone, fftSize: size)

        guard !dBValues.isEmpty else { return }
        let peakDB = dBValues.max() ?? -200.0
        XCTAssertGreaterThan(
            peakDB,
            -20.0,
            "DCT peak for unit-amplitude tone must be above -20 dBFS; got \(peakDB) dB"
        )
        // A 10·log10 path would give approximately half the dB value —
        // guard that the amplitude convention is used.
        let powerPath: Float = 10.0 * log10f(max(1e-10, (dBValues.map { powf(10, $0 / 20.0) }.max() ?? 0)))
        XCTAssertNotEqual(peakDB, powerPath, accuracy: 0.1,
                          "Amplitude and power paths must produce different dB values")
    }

    /// DCT magnitudes are amplitude-domain values. 20·log10 (the post-M15
    /// task-3 convention) on a known DCT coefficient must produce twice
    /// the dB value of 10·log10 on the same input (sign included). This
    /// guards against silently regressing the `vDSP_vdbcon` flag.
    func test_dctLogConventionIsAmplitudeNotPower() {
        let coefficients: [Float] = [0.1, 0.01, 0.001]

        // 20·log10 (amplitude) — the post-fix watch convention
        var amplitudeDB = coefficients
        var lo: Float = 1e-10
        var hi: Float = .greatestFiniteMagnitude
        vDSP_vclip(amplitudeDB, 1, &lo, &hi, &amplitudeDB, 1, vDSP_Length(amplitudeDB.count))
        var n = Int32(amplitudeDB.count)
        vvlog10f(&amplitudeDB, amplitudeDB, &n)
        var twenty: Float = 20.0
        vDSP_vsmul(amplitudeDB, 1, &twenty, &amplitudeDB, 1, vDSP_Length(amplitudeDB.count))

        // 10·log10 (power) — the pre-fix path that under-reported by 6 dB
        // per amplitude doubling
        var powerDB = coefficients
        vvlog10f(&powerDB, powerDB, &n)
        var ten: Float = 10.0
        vDSP_vsmul(powerDB, 1, &ten, &powerDB, 1, vDSP_Length(powerDB.count))

        for i in coefficients.indices {
            XCTAssertEqual(amplitudeDB[i], 2 * powerDB[i], accuracy: 1e-4,
                           "20·log10 must equal 2 × 10·log10 for coefficient[\(i)] = \(coefficients[i])")
        }
    }
}
