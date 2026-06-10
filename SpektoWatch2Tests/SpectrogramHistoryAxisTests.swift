import XCTest
@testable import SpektoWatch2

final class SpectrogramHistoryAxisTests: XCTestCase {
    func testInferThirdOctaveFromBandCount() {
        let kind = SpectrogramHistoryAxis.infer(
            binCount: MeasurementDataFormat.thirdOctaveBandCount,
            hasFullFFT: false,
            fftBinCount: 0
        )
        XCTAssertEqual(kind, .thirdOctave)
    }

    func testThirdOctaveBinIndexUsesCenterFrequencies() {
        let binCount = MeasurementDataFormat.thirdOctaveBandCount
        let index = SpectrogramHistoryAxis.binIndex(
            forFrequency: 1000,
            kind: .thirdOctave,
            binCount: binCount,
            sampleRate: 48_000
        )
        XCTAssertEqual(SpectrogramHistoryAxis.thirdOctaveCenterFrequencies[index], 1000)
    }

    func testLogSpacedBinCountScalesWithFFTSize() {
        XCTAssertEqual(
            SpectrogramHistoryAxis.logBinCount(forFFTSize: 4096, resolution: .standard),
            1024
        )
        XCTAssertEqual(
            SpectrogramHistoryAxis.logBinCount(forFFTSize: 4096, resolution: .balanced),
            1365
        )
        XCTAssertEqual(SpectrogramHistoryAxis.hopSize(forFFTSize: 4096), 512)
    }
}
