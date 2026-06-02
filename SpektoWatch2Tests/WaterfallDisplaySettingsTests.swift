import XCTest
@testable import SpektoWatch2

final class WaterfallDisplaySettingsTests: XCTestCase {

    func testClampedDBRangeEnforcesMinimumSpan() {
        var settings = WaterfallDisplaySettings.liveDefault
        settings.minDB = 80
        settings.maxDB = 82
        let range = settings.clampedDBRange()
        XCTAssertEqual(range.minDB, 77)
        XCTAssertEqual(range.maxDB, 85)
    }

    func testWidgetSettingsMigrationRejectsLegacyNegativeMinDB() {
        let settings = WaterfallDisplaySettings.fromWidgetSettings(
            ["useWidgetOverrides": "true", "waterfallMinDB": "-110"],
            engineWeighting: "Z"
        )
        XCTAssertEqual(settings.minDB, WidgetSettings.defaultWaterfallMinDB)
    }

    func testDefaultSpectrumModeIsContinuous() {
        XCTAssertEqual(WaterfallDisplaySettings.liveDefault.spectrumMode, .continuous)
        XCTAssertEqual(WaterfallDisplaySettings.playbackDefault.spectrumMode, .continuous)
    }
}
