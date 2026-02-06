import XCTest
@testable import SpektoWatch2

final class WatchValueMappingTests: XCTestCase {
    func testValueMappingFallsBackToBroadbandLevel() {
        let data = SpectrogramData(
            frequencies: [0],
            magnitudes: [0],
            broadbandLevel: 77.0,
            levels: [:],
            sampleRate: 44100
        )

        XCTAssertEqual(WatchValueMapping.value(for: .laeq, data: data), 77.0)
        XCTAssertEqual(WatchValueMapping.value(for: .lceq, data: data), 77.0)
        XCTAssertEqual(WatchValueMapping.value(for: .lzeq, data: data), 77.0)
        XCTAssertEqual(WatchValueMapping.value(for: .lafMax, data: data), 77.0)
        XCTAssertEqual(WatchValueMapping.value(for: .lafMin, data: data), 77.0)
        XCTAssertEqual(WatchValueMapping.value(for: .lcfMax, data: data), 77.0)
        XCTAssertEqual(WatchValueMapping.value(for: .lcfMin, data: data), 77.0)
    }

    func testValueMappingUsesExactLevelKeys() {
        let levels: [String: Float] = [
            "LAeq": 10,
            "LCeq": 11,
            "LZeq": 12,
            "LAFmax": 20,
            "LAFmin": 21,
            "LCFmax": 30,
            "LCFmin": 31,
            "LAF": 22,
            "LCF": 32
        ]
        let data = SpectrogramData(
            frequencies: [0],
            magnitudes: [0],
            broadbandLevel: 99.0,
            levels: levels,
            sampleRate: 44100
        )

        XCTAssertEqual(WatchValueMapping.value(for: .laeq, data: data), 10)
        XCTAssertEqual(WatchValueMapping.value(for: .lceq, data: data), 11)
        XCTAssertEqual(WatchValueMapping.value(for: .lzeq, data: data), 12)
        XCTAssertEqual(WatchValueMapping.value(for: .lafMax, data: data), 20)
        XCTAssertEqual(WatchValueMapping.value(for: .lafMin, data: data), 21)
        XCTAssertEqual(WatchValueMapping.value(for: .lcfMax, data: data), 30)
        XCTAssertEqual(WatchValueMapping.value(for: .lcfMin, data: data), 31)
    }

    func testValueMappingUsesSecondaryFallbacks() {
        let levels: [String: Float] = [
            "LAF": 22,
            "LCF": 32
        ]
        let data = SpectrogramData(
            frequencies: [0],
            magnitudes: [0],
            broadbandLevel: 99.0,
            levels: levels,
            sampleRate: 44100
        )

        XCTAssertEqual(WatchValueMapping.value(for: .lafMax, data: data), 22)
        XCTAssertEqual(WatchValueMapping.value(for: .lafMin, data: data), 22)
        XCTAssertEqual(WatchValueMapping.value(for: .lcfMax, data: data), 32)
        XCTAssertEqual(WatchValueMapping.value(for: .lcfMin, data: data), 32)
    }
}
