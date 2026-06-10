import XCTest
@testable import SpektoWatch_Watch_App

final class WatchMeterLayoutConfigTests: XCTestCase {
    func testDefaultLayoutIncludesPegelmesserAndSingleValues() {
        let config = WatchMeterLayoutConfig()
        let types = config.orderedMeterWidgets.map(\.type)
        XCTAssertTrue(types.contains(.pegelmeter))
        XCTAssertGreaterThanOrEqual(types.filter { $0 == .singleValue }.count, 2)
    }

    func testOrderedMeterWidgetsExcludesSpectrogram() {
        let config = WatchMeterLayoutConfig(widgets: [
            WatchWidgetConfig(type: .pegelmeter, position: 0),
            WatchWidgetConfig(type: .spectrogram, position: 1),
            WatchWidgetConfig(type: .singleValue, position: 2, singleValueType: .laeq),
        ])
        XCTAssertEqual(config.orderedMeterWidgets.count, 2)
        XCTAssertFalse(config.orderedMeterWidgets.contains(where: { $0.type == .spectrogram }))
    }

    func testMeterLayoutConfigEncodesDefaultAndPerTileRefreshRate() throws {
        var config = WatchMeterLayoutConfig(defaultSingleValueRefreshRate: .hz2)
        let widget = WatchWidgetConfig(
            type: .singleValue,
            position: 0,
            singleValueType: .laeq,
            singleValueRefreshRate: .hz10
        )
        config.replaceOrderedWidgets([widget])

        let data = try XCTUnwrap(config.encode())
        let restored = try XCTUnwrap(WatchMeterLayoutConfig.decode(from: data))

        XCTAssertEqual(restored.defaultSingleValueRefreshRate, .hz2)
        XCTAssertEqual(restored.refreshRate(for: restored.orderedMeterWidgets[0]), .hz10)
    }

    func testRefreshRateFallsBackToLayoutDefault() {
        let config = WatchMeterLayoutConfig(
            widgets: [
                WatchWidgetConfig(type: .singleValue, position: 0, singleValueType: .lafMax)
            ],
            defaultSingleValueRefreshRate: .hz1
        )
        let widget = config.orderedMeterWidgets[0]
        XCTAssertEqual(config.refreshRate(for: widget), .hz1)
    }
}
