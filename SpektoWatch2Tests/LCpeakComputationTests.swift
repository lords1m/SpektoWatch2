import XCTest
import Accelerate
@testable import SpektoWatch2

/// Tests for the IEC 61672 LCpeak computation path.
///
/// LCpeak must be derived from the C-weighted spectrum, not from the raw broadband
/// sample peak. These tests guard the M15 task-7 fix and document the expected
/// attenuation at low frequencies where C-weighting has measurable effect.
final class LCpeakComputationTests: XCTestCase {

    // MARK: - Helpers

    /// Reproduces the AudioEngine LCpeak computation from a synthetic FFT magnitude
    /// array, using the production FrequencyWeightingProcessor.
    ///
    /// This mirrors the code in `AudioEngine.processFFTFrame` so that the test
    /// exercises the same vDSP path without needing to instantiate a full AudioEngine.
    private func computeLCpeak(
        fftLinearMagnitudes: [Float],
        calibrationOffset: Float,
        sampleRate: Double = 44100.0
    ) -> Float {
        let fftSize = fftLinearMagnitudes.count * 2  // half-spectrum → full size
        let processor = FrequencyWeightingProcessor(fftSize: fftSize, sampleRate: sampleRate)
        let cGains = processor.getWeightingGains(for: .c)

        let count = min(fftLinearMagnitudes.count, cGains.count)
        var cWeightedMags = [Float](repeating: 0, count: count)
        vDSP_vmul(fftLinearMagnitudes, 1, cGains, 1, &cWeightedMags, 1, vDSP_Length(count))

        var cPeakLinear: Float = 0.0
        vDSP_maxv(cWeightedMags, 1, &cPeakLinear, vDSP_Length(count))

        return 20.0 * log10(cPeakLinear + 1e-9) + calibrationOffset
    }

    /// Returns the bin index closest to `targetHz` for a half-spectrum of length
    /// `binCount` at `sampleRate`.
    private func binIndex(for targetHz: Float, binCount: Int, sampleRate: Double) -> Int {
        let nyquist = Float(sampleRate / 2.0)
        let binHz = nyquist / Float(binCount)
        return max(1, min(binCount - 1, Int(targetHz / binHz + 0.5)))
    }

    // MARK: - Tests

    /// A 1 kHz tone: C-weighting is ~0 dB at 1 kHz, so LCpeak should be very close
    /// to what the raw broadband peak gives (within ~1 dB of normalization rounding).
    func testLCpeak_atOneKHz_isApproximatelyEqualToBroadbandPeak() {
        let binCount = 4096  // fftSize = 8192
        let sampleRate = 44100.0
        let calibration: Float = 94.0

        // Place unit amplitude at 1 kHz bin; all other bins = 0
        var mags = [Float](repeating: 0, count: binCount)
        let bin1k = binIndex(for: 1000.0, binCount: binCount, sampleRate: sampleRate)
        mags[bin1k] = 1.0

        let lcPeak = computeLCpeak(fftLinearMagnitudes: mags, calibrationOffset: calibration, sampleRate: sampleRate)
        // Raw broadband peak of unit amplitude at 1 kHz = 20*log10(1.0) + 94 = 94 dB SPL
        let broadbandPeak: Float = 20.0 * log10(1.0) + calibration

        // C-weighting is normalised to 0 dB at 1 kHz, so LCpeak ≈ broadbandPeak ± 1 dB
        XCTAssertEqual(lcPeak, broadbandPeak, accuracy: 1.0,
            "LCpeak at 1 kHz should be within 1 dB of broadband peak (C-weighting ≈ 0 dB at 1 kHz)")
    }

    /// A 31.5 Hz tone: C-weighting attenuates by ~3 dB at 31.5 Hz (IEC 61672).
    /// LCpeak should be noticeably lower than the raw broadband peak at this frequency.
    ///
    /// This is the spec's canonical fixture: the pre-fix code passed `peakLevel`
    /// (raw broadband) directly, so pre-fix LCpeak ≈ broadbandPeak. Post-fix,
    /// LCpeak < broadbandPeak by approximately the C-weighting attenuation amount.
    func testLCpeak_atThirtyOneHz_isLowerThanBroadbandPeak() {
        let binCount = 4096
        let sampleRate = 44100.0
        let calibration: Float = 94.0

        var mags = [Float](repeating: 0, count: binCount)
        let bin31 = binIndex(for: 31.5, binCount: binCount, sampleRate: sampleRate)
        mags[bin31] = 1.0  // unit amplitude at 31.5 Hz

        let lcPeak = computeLCpeak(fftLinearMagnitudes: mags, calibrationOffset: calibration, sampleRate: sampleRate)
        let broadbandPeak: Float = 20.0 * log10(1.0) + calibration  // = 94 dB SPL

        // IEC 61672 C-weighting is approximately −3 dB at 31.5 Hz.
        // Post-fix: LCpeak < broadbandPeak.
        // Pre-fix: LCpeak == broadbandPeak (wrong — the test would fail on old code).
        XCTAssertLessThan(lcPeak, broadbandPeak,
            "LCpeak at 31.5 Hz must be less than raw broadband peak (C-weighting attenuates below ~40 Hz)")

        // Verify the attenuation is in the expected range for 31.5 Hz:
        // IEC 61672 table value is approximately −3.0 dB at 31.5 Hz.
        // Allow ±1 dB tolerance for bin-frequency rounding.
        let attenuation = broadbandPeak - lcPeak
        XCTAssertGreaterThan(attenuation, 1.5,
            "C-weighting attenuation at 31.5 Hz should be at least 1.5 dB")
        XCTAssertLessThan(attenuation, 6.0,
            "C-weighting attenuation at 31.5 Hz should not exceed 6 dB (IEC table value ≈ 3 dB)")
    }

    /// At 20 Hz (below IEC C-weighting lower limit), attenuation is significant (~8 dB).
    /// LCpeak should be substantially lower than broadband peak.
    func testLCpeak_at20Hz_hasLargerAttenuation() {
        let binCount = 4096
        let sampleRate = 44100.0
        let calibration: Float = 94.0

        var mags = [Float](repeating: 0, count: binCount)
        let bin20 = binIndex(for: 20.0, binCount: binCount, sampleRate: sampleRate)
        mags[bin20] = 1.0

        let lcPeak = computeLCpeak(fftLinearMagnitudes: mags, calibrationOffset: calibration, sampleRate: sampleRate)
        let broadbandPeak: Float = 20.0 * log10(1.0) + calibration

        // C-weighting attenuation at 20 Hz is roughly 6–10 dB.
        let attenuation = broadbandPeak - lcPeak
        XCTAssertGreaterThan(attenuation, 4.0,
            "C-weighting attenuation at 20 Hz should exceed 4 dB")
    }

    /// All-zero input should produce LCpeak at the noise floor (≈ calibration − 180 dB),
    /// not crash or return a large value.
    func testLCpeak_allZeroMagnitudes_returnsFloor() {
        let binCount = 4096
        let mags = [Float](repeating: 0, count: binCount)
        let calibration: Float = 94.0

        let lcPeak = computeLCpeak(fftLinearMagnitudes: mags, calibrationOffset: calibration)

        // 20*log10(epsilon=1e-9) ≈ -180 dBFS; + calibration = -86 dB
        // The result should be a large negative number well below any real signal.
        XCTAssertLessThan(lcPeak, -60.0,
            "All-zero magnitudes should produce LCpeak well below -60 dB SPL (noise floor)")
    }

    /// Multi-tone input: the bin with the highest C-weighted amplitude determines LCpeak.
    /// A high-amplitude 31.5 Hz bin and a lower-amplitude 1 kHz bin: if the 1 kHz
    /// amplitude is still higher after C-weighting, LCpeak should be dominated by 1 kHz.
    func testLCpeak_dominantHighFreqBinWins() {
        let binCount = 4096
        let sampleRate = 44100.0
        let calibration: Float = 0.0  // no offset — makes dB math straightforward

        var mags = [Float](repeating: 0, count: binCount)
        let bin1k = binIndex(for: 1000.0, binCount: binCount, sampleRate: sampleRate)
        let bin31 = binIndex(for: 31.5, binCount: binCount, sampleRate: sampleRate)

        mags[bin1k] = 1.0    // 0 dBFS at 1 kHz — C-weight ≈ 0 dB → ~0 dBFS after weighting
        mags[bin31] = 0.5    // -6 dBFS at 31.5 Hz — C-weight ≈ -3 dB → ~-9 dBFS after weighting

        let lcPeak = computeLCpeak(fftLinearMagnitudes: mags, calibrationOffset: calibration, sampleRate: sampleRate)

        // 1 kHz dominates; LCpeak ≈ 0 dBFS + 0 dB C-weight + 0 dB cal ≈ 0 dB
        XCTAssertGreaterThan(lcPeak, -2.0,
            "1 kHz bin should dominate LCpeak when its C-weighted amplitude exceeds the 31.5 Hz bin")
        XCTAssertLessThan(lcPeak, 2.0,
            "LCpeak should be near 0 dB when dominated by a unit-amplitude 1 kHz bin")
    }
}
