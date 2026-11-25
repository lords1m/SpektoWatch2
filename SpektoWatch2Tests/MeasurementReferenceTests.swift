import XCTest
import Accelerate
@testable import SpektoWatch2

/// M22 task-6 reference harness: synthetic signals through the measurement
/// maths. Targets follow IEC 61672-1 (tolerances noted per test). The
/// absolute scale is the app's established Hann-FFT calibration reference
/// (`TimeDomainLevelMeter.referenceEnergyFactor`), so existing calibration
/// offsets stay valid.
final class MeasurementReferenceTests: XCTestCase {

    private let fs = 48_000.0

    private func sine(freq: Double, amplitude: Float, seconds: Double, fs: Double) -> [Float] {
        let n = Int(seconds * fs)
        return (0..<n).map { amplitude * Float(sin(2 * .pi * freq * Double($0) / fs)) }
    }

    private func dB(_ e: Double) -> Double { 10 * log10(max(e, 1e-12)) }

    // MARK: - MC-2 window normalisation

    private func fftEnergy(_ samples: [Float], window: WindowFunction, size: Int = 4096) -> Double {
        let fft = FFTProcessor(fftSize: size, sampleRate: fs, windowFunction: window)
        let mags = fft.performFFT(on: Array(samples.prefix(size)))
        var e: Float = 0
        vDSP_svesq(mags, 1, &e, vDSP_Length(mags.count))
        return Double(e)
    }

    func testSineEnergyIsWindowIndependent() {
        let x = sine(freq: 1_000.3, amplitude: 0.5, seconds: 0.2, fs: fs)
        let hann = dB(fftEnergy(x, window: .hann))
        for window in WindowFunction.allCases {
            XCTAssertEqual(dB(fftEnergy(x, window: window)), hann, accuracy: 0.3, "\(window)")
        }
    }

    func testNoiseEnergyIsWindowIndependent() {
        var generator = SystemRandomNumberGenerator()
        let x = (0..<8192).map { _ in Float.random(in: -0.3...0.3, using: &generator) }
        let hann = dB(fftEnergy(x, window: .hann))
        for window in [WindowFunction.rectangular, .flatTop, .blackmanHarris] {
            XCTAssertEqual(dB(fftEnergy(x, window: window)), hann, accuracy: 0.5, "\(window)")
        }
    }

    func testHannReferenceUnchanged() {
        XCTAssertEqual(FFTProcessor.powerNormalization(for: WindowFunction.hann.generate(size: 4096)), 1, accuracy: 0.01)
    }

    // MARK: - MC-3 / MC-5 time-domain meter

    func testMeterMatchesFFTCalibrationReferenceForSine() {
        let x = sine(freq: 1_000, amplitude: 0.5, seconds: 2, fs: fs)
        let meter = TimeDomainLevelMeter(sampleRate: fs)
        let snap = meter.process(x, calibrationOffset: 0)
        // A-weighting is 0 dB at 1 kHz; FFT Hann energy is the reference scale.
        XCTAssertEqual(dB(snap.lafEnergy), dB(fftEnergy(x, window: .hann)), accuracy: 0.2)
        XCTAssertEqual(dB(snap.laeqEnergy), dB(snap.lafEnergy), accuracy: 0.2)
    }

    func testLevelIndependentOfBlockSize() {
        let x = sine(freq: 1_000, amplitude: 0.2, seconds: 2, fs: fs)
        func level(block: Int) -> Double {
            let meter = TimeDomainLevelMeter(sampleRate: fs)
            var snap = meter.snapshot(calibrationOffset: 94)
            var i = 0
            while i < x.count {
                snap = meter.process(x[i..<min(i + block, x.count)], calibrationOffset: 94)
                i += block
            }
            return dB(snap.lafEnergy)
        }
        XCTAssertEqual(level(block: 256), level(block: 4096), accuracy: 0.05)
    }

    func testToneBurstLAFmaxMatchesIECTable() {
        // IEC 61672-1 Table 4: 4 kHz, 10 ms burst, Fast → −11.0 dB (±1.0).
        let steady = sine(freq: 4_000, amplitude: 0.3, seconds: 2, fs: fs)
        let steadyMeter = TimeDomainLevelMeter(sampleRate: fs)
        let steadyLevel = dB(steadyMeter.process(steady, calibrationOffset: 0).lafEnergy)

        var burst = [Float](repeating: 0, count: Int(fs))
        let burstSamples = Int(0.010 * fs)
        for i in 0..<burstSamples {
            burst[1000 + i] = 0.3 * Float(sin(2 * .pi * 4_000 * Double(i) / fs))
        }
        let burstMeter = TimeDomainLevelMeter(sampleRate: fs)
        let lafMax = dB(burstMeter.process(burst, calibrationOffset: 0).lafMaxEnergy)
        XCTAssertEqual(lafMax - steadyLevel, -11.0, accuracy: 0.5)
    }

    func testLCpeakNotBelowLCF() {
        let x = sine(freq: 1_000, amplitude: 0.4, seconds: 1, fs: fs)
        let meter = TimeDomainLevelMeter(sampleRate: fs)
        let snap = meter.process(x, calibrationOffset: 94)
        XCTAssertEqual(dB(snap.lcPeakEnergy) - dB(snap.lcfEnergy), 3.01, accuracy: 0.3, "Sine crest factor")

        var impulse = [Float](repeating: 0, count: Int(fs / 2))
        impulse[100] = 0.8
        let impulseMeter = TimeDomainLevelMeter(sampleRate: fs)
        let isnap = impulseMeter.process(impulse, calibrationOffset: 94)
        XCTAssertGreaterThanOrEqual(dB(isnap.lcPeakEnergy), dB(isnap.lcfEnergy))
    }

    func testWeightingTableWithinTolerance() {
        // IEC 61672-1 nominal values; class-1 tolerances are wider above 4 kHz.
        let aTable: [(Double, Double)] = [(31.5, -39.4), (63, -26.2), (125, -16.1), (250, -8.6),
                                          (500, -3.2), (1_000, 0), (2_000, 1.2), (4_000, 1.0),
                                          (8_000, -1.1), (12_500, -4.3), (16_000, -6.6)]
        let cTable: [(Double, Double)] = [(31.5, -3.0), (63, -0.8), (1_000, 0), (4_000, -0.8), (8_000, -3.0), (16_000, -8.5)]
        for rate in [44_100.0, 48_000.0] {
            let meter = TimeDomainLevelMeter(sampleRate: rate)
            for (f, expected) in aTable {
                XCTAssertEqual(meter.weightingResponseDB(.a, at: f), expected, accuracy: 1.1, "A \(f) Hz @ \(rate)")
            }
            for (f, expected) in cTable {
                XCTAssertEqual(meter.weightingResponseDB(.c, at: f), expected, accuracy: 1.1, "C \(f) Hz @ \(rate)")
            }
        }
    }

    // MARK: - MC-1 hop larger than the FFT window

    func testFramesAreExactlyOneHopApartWhenHopExceedsFrame() {
        let ring = SampleRingBuffer()
        let frameSize = 1024, hop = 4096
        var starts: [Float] = []
        var next: Float = 0
        for _ in 0..<40 {
            let block = (0..<512).map { _ -> Float in defer { next += 1 }; return next }
            ring.append(block)
            while let frame = ring.nextFrame(frameSize: frameSize, hop: hop) {
                starts.append(frame[0])
            }
        }
        XCTAssertGreaterThan(starts.count, 2)
        for i in 1..<starts.count {
            XCTAssertEqual(starts[i] - starts[i - 1], Float(hop), "frame \(i)")
        }
    }

    // MARK: - MC-6 loudness extrapolation

    func testPhonAbove90IsContinuousAndMonotonic() {
        let p90 = LoudnessCalculator.phon(spl: 90, frequency: 1_000)
        let p100 = LoudnessCalculator.phon(spl: 100, frequency: 1_000)
        let p110 = LoudnessCalculator.phon(spl: 110, frequency: 1_000)
        XCTAssertEqual(p90, 90, accuracy: 1.5)
        XCTAssertEqual(p100, 100, accuracy: 2.5, "At 1 kHz phon ≈ dB SPL")
        XCTAssertGreaterThan(p110, p100)
        XCTAssertEqual(p110 - p100, p100 - p90, accuracy: 1.0, "Linear continuation of the contour slope")
    }

    // MARK: - MC-9 / MC-10 masking helpers

    func testSuggestedVolumeUsesDBFS() {
        XCTAssertEqual(MaskerSuggestionEngine.suggestedVolumeDBFS(triggerSPL: 60, calibrationOffset: 100), -40, accuracy: 0.01)
        XCTAssertEqual(MaskerSuggestionEngine.suggestedVolumeDBFS(triggerSPL: 99, calibrationOffset: 100), -10, accuracy: 0.01)
        XCTAssertEqual(MaskerSuggestionEngine.suggestedVolumeDBFS(triggerSPL: 10, calibrationOffset: 100), -60, accuracy: 0.01)
    }

    func testQToOctaveBandwidth() {
        // Q = √2 ↔ 1 octave
        XCTAssertEqual(MaskingPreviewPlayer.octaveBandwidth(forQ: 1.4142), 1.0, accuracy: 0.01)
        XCTAssertEqual(MaskingPreviewPlayer.octaveBandwidth(forQ: 4.318), 1.0 / 3.0, accuracy: 0.01)
    }

    // MARK: - MC-8 time-based trigger capture

    func testTriggerCaptureUsesTimestampsAndWaitsForPostWindow() {
        let acc = TriggerSpectrumAccumulator(preMarkSeconds: 0.5, postMarkSeconds: 0.5)
        var finalized: Bool?
        acc.onCaptureFinalized = { finalized = $0 }
        let quiet = [Float](repeating: 30, count: TriggerSpectrum.bandCount)
        let loud = [Float](repeating: 70, count: TriggerSpectrum.bandCount)
        var t = 0.0
        // 10 Hz feed (Watch cadence)
        for _ in 0..<20 { acc.feed(bands: quiet, rmsDB: 30, at: t); t += 0.1 }
        acc.beginMark(at: t)
        for _ in 0..<10 { acc.feed(bands: loud, rmsDB: 70, at: t); t += 0.1 }
        XCTAssertTrue(acc.endMark(at: t))
        XCTAssertTrue(acc.isCapturePending, "Must not read future (unwritten) frames")
        XCTAssertNil(finalized)
        for _ in 0..<6 { acc.feed(bands: loud, rmsDB: 70, at: t); t += 0.1 }
        XCTAssertEqual(finalized, true)
        XCTAssertEqual(acc.captureCount, 1)
    }
}
