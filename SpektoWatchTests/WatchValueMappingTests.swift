import XCTest
@testable import SpektoWatch_Watch_App

// MARK: - WatchValueMapping Tests (Watch target)
//
// These tests are intentionally analogous to those in the iOS SpektoWatch2Tests
// target, but they import from the Watch App module instead of the iOS module.
// This catches any divergence between the two copies of WatchValueMapping.

final class WatchValueMappingTests: XCTestCase {

    // MARK: - Fallback to broadbandLevel

    func testAllTypesReturnBroadbandLevelWhenNoLevelsDict() {
        let data = SpectrogramData(
            frequencies: [100, 200],
            magnitudes: [50, 55],
            broadbandLevel: 77.0,
            levels: [:],
            sampleRate: 44100
        )

        for type in WatchSingleValueType.allCases {
            XCTAssertEqual(
                WatchValueMapping.value(for: type, data: data),
                77.0,
                "When levels dict is empty, \(type) must fall back to broadbandLevel"
            )
        }
    }

    func testBroadbandLevelFallbackWithExactKeys() {
        // Only unexpected keys → still falls back
        let data = SpectrogramData(
            frequencies: [0],
            magnitudes: [0],
            broadbandLevel: 55.0,
            levels: ["unknown": 99.0],
            sampleRate: 44100
        )

        XCTAssertEqual(WatchValueMapping.value(for: .laeq, data: data), 55.0)
    }

    // MARK: - Primary level keys

    func testLaeqReadsLAeqKey() {
        let data = makeData(levels: ["LAeq": 42.0])
        XCTAssertEqual(WatchValueMapping.value(for: .laeq, data: data), 42.0)
    }

    func testLceqReadsLCeqKey() {
        let data = makeData(levels: ["LCeq": 43.0])
        XCTAssertEqual(WatchValueMapping.value(for: .lceq, data: data), 43.0)
    }

    func testLzeqReadsLZeqKey() {
        let data = makeData(levels: ["LZeq": 44.0])
        XCTAssertEqual(WatchValueMapping.value(for: .lzeq, data: data), 44.0)
    }

    func testLafMaxReadsLAFmaxKey() {
        let data = makeData(levels: ["LAFmax": 80.0])
        XCTAssertEqual(WatchValueMapping.value(for: .lafMax, data: data), 80.0)
    }

    func testLafMinReadsLAFminKey() {
        let data = makeData(levels: ["LAFmin": 30.0])
        XCTAssertEqual(WatchValueMapping.value(for: .lafMin, data: data), 30.0)
    }

    func testLcfMaxReadsLCFmaxKey() {
        let data = makeData(levels: ["LCFmax": 82.0])
        XCTAssertEqual(WatchValueMapping.value(for: .lcfMax, data: data), 82.0)
    }

    func testLcfMinReadsLCFminKey() {
        let data = makeData(levels: ["LCFmin": 31.0])
        XCTAssertEqual(WatchValueMapping.value(for: .lcfMin, data: data), 31.0)
    }

    // MARK: - Secondary fallbacks (LAF / LCF as instantaneous proxies)

    func testLafMaxFallsBackToLAFWhenLAFmaxMissing() {
        let data = makeData(levels: ["LAF": 65.0])
        XCTAssertEqual(WatchValueMapping.value(for: .lafMax, data: data), 65.0)
    }

    func testLafMinFallsBackToLAFWhenLAFminMissing() {
        let data = makeData(levels: ["LAF": 65.0])
        XCTAssertEqual(WatchValueMapping.value(for: .lafMin, data: data), 65.0)
    }

    func testLcfMaxFallsBackToLCFWhenLCFmaxMissing() {
        let data = makeData(levels: ["LCF": 66.0])
        XCTAssertEqual(WatchValueMapping.value(for: .lcfMax, data: data), 66.0)
    }

    func testLcfMinFallsBackToLCFWhenLCFminMissing() {
        let data = makeData(levels: ["LCF": 66.0])
        XCTAssertEqual(WatchValueMapping.value(for: .lcfMin, data: data), 66.0)
    }

    // MARK: - Primary key takes precedence over secondary

    func testPrimaryKeyPreferredOverLAFFallback() {
        let data = makeData(levels: ["LAFmax": 80.0, "LAF": 65.0])
        XCTAssertEqual(WatchValueMapping.value(for: .lafMax, data: data), 80.0,
            "LAFmax must be preferred over LAF fallback")
    }

    func testPrimaryKeyPreferredOverBroadbandFallback() {
        let data = makeData(levels: ["LAeq": 50.0], broadband: 99.0)
        XCTAssertEqual(WatchValueMapping.value(for: .laeq, data: data), 50.0,
            "LAeq must be preferred over broadbandLevel")
    }

    // MARK: - Full levels dict round-trip

    func testAllKeysSetSimultaneously() {
        let levels: [String: Float] = [
            "LAeq": 10, "LCeq": 11, "LZeq": 12,
            "LAFmax": 20, "LAFmin": 21,
            "LCFmax": 30, "LCFmin": 31,
            "LAF": 22, "LCF": 32
        ]
        let data = makeData(levels: levels, broadband: 99.0)

        XCTAssertEqual(WatchValueMapping.value(for: .laeq,   data: data), 10)
        XCTAssertEqual(WatchValueMapping.value(for: .lceq,   data: data), 11)
        XCTAssertEqual(WatchValueMapping.value(for: .lzeq,   data: data), 12)
        XCTAssertEqual(WatchValueMapping.value(for: .lafMax,  data: data), 20)
        XCTAssertEqual(WatchValueMapping.value(for: .lafMin,  data: data), 21)
        XCTAssertEqual(WatchValueMapping.value(for: .lcfMax,  data: data), 30)
        XCTAssertEqual(WatchValueMapping.value(for: .lcfMin,  data: data), 31)
    }

    // MARK: - Edge values

    func testZeroLevelValue() {
        let data = makeData(levels: ["LAeq": 0.0])
        XCTAssertEqual(WatchValueMapping.value(for: .laeq, data: data), 0.0)
    }

    func testNegativeLevelValue() {
        let data = makeData(levels: ["LAeq": -10.0])
        XCTAssertEqual(WatchValueMapping.value(for: .laeq, data: data), -10.0)
    }

    func testVeryHighLevelValue() {
        let data = makeData(levels: ["LAeq": 140.0])
        XCTAssertEqual(WatchValueMapping.value(for: .laeq, data: data), 140.0)
    }

    // MARK: - Helpers

    private func makeData(
        levels: [String: Float],
        broadband: Float = 0.0
    ) -> SpectrogramData {
        SpectrogramData(
            frequencies: [0],
            magnitudes: [0],
            broadbandLevel: broadband,
            levels: levels,
            sampleRate: 44100
        )
    }
}
