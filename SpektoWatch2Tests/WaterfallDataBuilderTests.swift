import XCTest
@testable import SpektoWatch2

final class WaterfallDataBuilderTests: XCTestCase {

    func testEmptyHistoryProducesEmptyDataSet() {
        let result = WaterfallDataBuilder.build(history: [], sourceFrequencies: [], duration: 0)
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(result.slices.isEmpty)
    }

    func testSliceCountDoesNotExceedTarget() {
        let frames = (0..<200).map { _ in Array(repeating: Float(-60), count: 31) }
        let result = WaterfallDataBuilder.build(
            history: frames,
            sourceFrequencies: WaterfallDataBuilder.thirdOctaveCenters,
            duration: 10,
            targetSliceCount: 48
        )
        XCTAssertLessThanOrEqual(result.slices.count, 48)
    }

    func testFrequencyCountDoesNotExceedTarget() {
        let frames = (0..<10).map { _ in Array(repeating: Float(-60), count: 64) }
        let freqs = (0..<64).map { Float($0) * 344 }
        let result = WaterfallDataBuilder.build(
            history: frames,
            sourceFrequencies: freqs,
            duration: 5,
            targetSliceCount: 96,
            targetFrequencyCount: 32
        )
        XCTAssertLessThanOrEqual(result.frequencies.count, 32)
    }

    func testSingleFrameProducesOneSlice() {
        let frame = Array(repeating: Float(-70), count: 31)
        let result = WaterfallDataBuilder.build(
            history: [frame],
            sourceFrequencies: WaterfallDataBuilder.thirdOctaveCenters,
            duration: 1,
            targetSliceCount: 96
        )
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.slices.count, 1)
    }

    func testMinMaxDBPreserved() {
        let frame = Array(repeating: Float(-60), count: 8)
        let freqs = (0..<8).map { Float($0) * 1000 }
        let result = WaterfallDataBuilder.build(
            history: [frame],
            sourceFrequencies: freqs,
            duration: 1,
            minDB: -90,
            maxDB: 10
        )
        XCTAssertEqual(result.minDB, -90)
        XCTAssertEqual(result.maxDB, 10)
    }

    func testSourceFrequenciesThirdOctave() {
        let freqs = WaterfallDataBuilder.sourceFrequencies(
            binCount: WaterfallDataBuilder.thirdOctaveCenters.count,
            sampleRate: 44100,
            storedProviderHasFullFFT: false
        )
        XCTAssertEqual(freqs.count, WaterfallDataBuilder.thirdOctaveCenters.count)
        for (a, b) in zip(freqs, WaterfallDataBuilder.thirdOctaveCenters) {
            XCTAssertEqual(a, b, accuracy: 0.001)
        }
    }

    func testSourceFrequenciesFullFFT() {
        let binCount = 512
        let sampleRate: Double = 44100
        let freqs = WaterfallDataBuilder.sourceFrequencies(
            binCount: binCount,
            sampleRate: sampleRate,
            storedProviderHasFullFFT: true
        )
        XCTAssertEqual(freqs.count, binCount)
        XCTAssertEqual(freqs.first ?? -1, 0, accuracy: 0.1)
        let nyquist = Float(sampleRate / 2)
        XCTAssertEqual(freqs.last ?? -1, nyquist, accuracy: 1.0)
        // Linear spacing: successive differences should be equal
        let diffs = zip(freqs.dropFirst(), freqs).map { $0 - $1 }
        let firstDiff = diffs[0]
        for d in diffs {
            XCTAssertEqual(d, firstDiff, accuracy: 0.01)
        }
    }
}
