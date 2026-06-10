import XCTest
@testable import SpektoWatch2

final class WatchDashboardConfigTests: XCTestCase {
    func testNormalizeLegacyGridCollapsesDuplicateSpectrogramCells() {
        var config = WatchDashboardConfig(widgets: [
            WatchWidgetConfig(type: .spectrogram, position: 0),
            WatchWidgetConfig(type: .spectrogram, position: 1),
            WatchWidgetConfig(type: .spectrogram, position: 4),
            WatchWidgetConfig(type: .spectrogram, position: 5),
            WatchWidgetConfig(type: .levelMeter, position: 2),
            WatchWidgetConfig(type: .levelMeter, position: 3),
            WatchWidgetConfig(type: .singleValue, position: 8, singleValueType: .laeq),
            WatchWidgetConfig(type: .empty, position: 12),
        ], version: 1)

        config.normalizeLegacyGridIfNeeded()

        XCTAssertEqual(config.widgets.filter { $0.type == .spectrogram }.count, 1)
        XCTAssertEqual(config.widgets.filter { $0.type == .levelMeter }.count, 1)
        XCTAssertFalse(config.widgets.contains(where: { $0.type == .empty }))
        XCTAssertEqual(config.orderedDisplayWidgets.map(\.position), Array(0..<config.orderedDisplayWidgets.count))
    }

    func testOrderedDisplayWidgetsAllowsMultipleSingleValues() {
        let config = WatchDashboardConfig(widgets: [
            WatchWidgetConfig(type: .singleValue, position: 0, singleValueType: .laeq),
            WatchWidgetConfig(type: .singleValue, position: 1, singleValueType: .lafMax),
            WatchWidgetConfig(type: .levelMeter, position: 2),
        ], version: 1)

        XCTAssertEqual(config.orderedDisplayWidgets.count, 3)
    }

    func testDefaultWidgetCountMatchesSlotModel() {
        XCTAssertEqual(WatchDashboardConfig.defaultWidgets.count, 6)
        XCTAssertEqual(WatchDashboardConfig().orderedDisplayWidgets.count, 6)
    }

    func testLevelMeterOrientationRoundTrip() throws {
        var config = WatchDashboardConfig(widgets: [
            WatchWidgetConfig(
                type: .levelMeter,
                position: 0,
                levelMeterOrientation: .vertical
            ),
        ])
        let data = try XCTUnwrap(config.encode())
        let restored = try XCTUnwrap(WatchDashboardConfig.decode(from: data))
        XCTAssertEqual(
            restored.orderedDisplayWidgets.first?.resolvedLevelMeterOrientation(),
            .vertical
        )
    }
}
