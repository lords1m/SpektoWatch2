import XCTest
@testable import SpektoWatch2

final class WidgetDisplayStyleMigrationTests: XCTestCase {

    func testLegacyWidgetJSONDecodesAsLiveWidget() throws {
        let legacyJSON = #"""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "type": "Pegel-Meter",
          "gridPosition": {"index": 0},
          "size": {"columns": 2, "rows": 1},
          "settings": {}
        }
        """#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WidgetConfiguration.self, from: legacyJSON)
        XCTAssertEqual(decoded.displayStyle, .liveWidget)
        XCTAssertNil(decoded.preferredLiveSize)
        XCTAssertEqual(decoded.size, WidgetSize(columns: 2, rows: 1))
    }

    func testIconStyleAlwaysNormalizesTo1x1() {
        let iconWidget = WidgetConfiguration(
            type: .spectrogram,
            size: WidgetSize(columns: 3, rows: 3),
            displayStyle: .icon
        )
        XCTAssertEqual(iconWidget.size, WidgetSize(columns: 1, rows: 1))
        XCTAssertEqual(iconWidget.displayStyle, .icon)
    }

    @MainActor
    func testDashboardManagerToggleStylePreservesPreferredLiveSize() {
        let manager = DashboardManager()
        manager.addWidget(type: .spectrogram, displayStyle: .liveWidget)
        guard let added = manager.widgets.last else {
            return XCTFail("Expected widget to be added")
        }
        let originalLiveSize = added.size
        XCTAssertEqual(added.displayStyle, .liveWidget)
        XCTAssertGreaterThan(originalLiveSize.columns, 1)

        // Switch to icon
        manager.setDisplayStyle(.icon, for: added.id)
        let asIcon = manager.widgets.first { $0.id == added.id }
        XCTAssertEqual(asIcon?.displayStyle, .icon)
        XCTAssertEqual(asIcon?.size, WidgetSize(columns: 1, rows: 1))
        XCTAssertEqual(asIcon?.preferredLiveSize, originalLiveSize)

        // Switch back to liveWidget -> restores preferredLiveSize
        manager.setDisplayStyle(.liveWidget, for: added.id)
        let restored = manager.widgets.first { $0.id == added.id }
        XCTAssertEqual(restored?.displayStyle, .liveWidget)
        XCTAssertEqual(restored?.size, originalLiveSize)
    }

    func testDefaultHomeCompositionContainsLiveWidgetsAndIcons() {
        let homeWidgets = PresetCompositions.widgets(forPresetID: "overview")
        XCTAssertTrue(homeWidgets.contains { $0.displayStyle == .liveWidget })
        XCTAssertTrue(homeWidgets.contains { $0.displayStyle == .icon })
        XCTAssertTrue(homeWidgets.contains { $0.type == .audioEditor && $0.displayStyle == .icon })
        XCTAssertTrue(homeWidgets.contains { $0.type == .recordings && $0.displayStyle == .icon })
        XCTAssertTrue(homeWidgets.contains { $0.type == .settings && $0.displayStyle == .icon })
    }
}
