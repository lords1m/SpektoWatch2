import XCTest
@testable import SpektoWatch2

final class WatchCalibrationProviderTests: XCTestCase {

    func testDefaultOffsetIsReferenceValue() {
        // 100.0 matches the hardcoded watchMicCalibrationOffset that
        // WatchAudioEngine used before M19. Must not drift silently.
        XCTAssertEqual(WatchCalibrationProvider.defaultOffset, 100.0)
    }

    func testUnknownDeviceFallsBackToDefault() {
        XCTAssertEqual(
            WatchCalibrationProvider.recommendedOffset(for: "Unknown-Watch"),
            WatchCalibrationProvider.defaultOffset
        )
        XCTAssertEqual(
            WatchCalibrationProvider.recommendedOffset(for: "x86_64"),
            WatchCalibrationProvider.defaultOffset
        )
    }

    func testKnownWatchModelReturnsTableValue() {
        // Apple Watch Series 4 (40 mm GPS) — earliest table entry.
        XCTAssertEqual(WatchCalibrationProvider.recommendedOffset(for: "Watch4,1"), 100.0)
        // Apple Watch Series 9 (41 mm GPS).
        XCTAssertEqual(WatchCalibrationProvider.recommendedOffset(for: "Watch7,1"), 100.0)
    }
}
