import XCTest
@testable import SpektoWatch2

/// Regression tests for DSP boundary clamping and edge-case hardening.
final class ReviewHardeningRegressionTests: XCTestCase {

    func testFrequencyWeightingProcessorClampsInvalidInitInputs() {
        let processor = FrequencyWeightingProcessor(fftSize: 0, sampleRate: 0)
        XCTAssertFalse(processor.aWeightingGainsSq.isEmpty)
        XCTAssertTrue(processor.aWeightingGainsSq.allSatisfy { $0.isFinite })
        XCTAssertTrue(processor.cWeightingGainsSq.allSatisfy { $0.isFinite })
    }

    func testFFTProcessorClampsInvalidInitInputs() {
        let processor = FFTProcessor(fftSize: 0, sampleRate: 0)
        XCTAssertGreaterThanOrEqual(processor.fftSize, 2)
        let bin = processor.binForFrequency(1000)
        XCTAssertGreaterThanOrEqual(bin, 0)
    }

    func testMelSpectrogramProcessorClampsZeroSampleRate() {
        let processor = MelSpectrogramProcessor(
            filterBankCount: 16,
            fftBinCount: 64,
            sampleRate: 0
        )
        XCTAssertLessThan(processor.frequencyRange.lowerBound, processor.frequencyRange.upperBound)
        let output = processor.compute(linearMagnitudes: [Float](repeating: 0.1, count: 64))
        XCTAssertEqual(output.count, 16)
        XCTAssertTrue(output.allSatisfy { $0.isFinite })
    }

    func testTriggerSpectrumAccumulatorClampsZeroCapacityAndGuardsShortBands() {
        let accumulator = TriggerSpectrumAccumulator(
            sampleRate: 48_000,
            hopSize: 1024,
            historySeconds: 0
        )
        // Must not trap on % windowCapacity or short band arrays.
        accumulator.feed(bands: [Float](repeating: -40, count: 5), rmsDB: -40)
        accumulator.beginMark()
        accumulator.feed(bands: [Float](repeating: -30, count: 5), rmsDB: -30)
        _ = accumulator.endMark()
        accumulator.calibrateAmbient()
        XCTAssertNil(accumulator.ambientBands, "Short band frames must be ignored safely")
    }
}
