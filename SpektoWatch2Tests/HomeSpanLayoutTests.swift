import XCTest
@testable import SpektoWatch2

final class HomeSpanLayoutTests: XCTestCase {

    // MARK: Per-type limits

    func testSingleValueAndIconsTakeOneCell() {
        let value = WidgetConfiguration(type: .singleValue, size: WidgetSize(columns: 4, rows: 4))
        XCTAssertEqual(value.resolvedHomeSpan, HomeSpan(columns: 1, rows: 1))
        XCTAssertEqual(
            WidgetConfiguration.normalizedHomeSpan(
                HomeSpan(columns: 4, rows: 4),
                for: .singleValue,
                settings: [:]
            ),
            .single
        )

        let icon = WidgetConfiguration(type: .spectrogram, size: WidgetSize(columns: 3, rows: 3), displayStyle: .icon)
        XCTAssertEqual(icon.resolvedHomeSpan, .single)
    }

    func testSpectrogramIsAtLeastTwoByTwo() {
        let span = WidgetConfiguration.normalizedHomeSpan(.single, for: .spectrogram, settings: [:])
        XCTAssertEqual(span, HomeSpan(columns: 2, rows: 2))
    }

    func testSpansClampToFourColumns() {
        let span = WidgetConfiguration.normalizedHomeSpan(HomeSpan(columns: 9, rows: 20), for: .spectrogram, settings: [:])
        XCTAssertEqual(span, HomeSpan(columns: HomeGridMetrics.columns, rows: HomeGridMetrics.maxRows))
    }

    func testLevelMeterNeedsTwoCellsAlongItsBar() {
        let horizontal = WidgetConfiguration.normalizedHomeSpan(.single, for: .levelMeter, settings: [:])
        XCTAssertEqual(horizontal, HomeSpan(columns: 2, rows: 1))

        let vertical = WidgetConfiguration.normalizedHomeSpan(
            .single,
            for: .levelMeter,
            settings: [WidgetSettings.levelMeterOrientationKey: LevelMeterOrientation.vertical.rawValue]
        )
        XCTAssertEqual(vertical, HomeSpan(columns: 1, rows: 2))
    }

    // MARK: Persistence

    func testLegacyJSONWithoutSpanDerivesFromSize() throws {
        let json = #"""
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "type": "Spektrogramm",
          "gridPosition": {"index": 0},
          "size": {"columns": 3, "rows": 2},
          "settings": {}
        }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WidgetConfiguration.self, from: json)
        XCTAssertNil(decoded.homeSpan)
        XCTAssertEqual(decoded.resolvedHomeSpan, HomeSpan(columns: 4, rows: 2))
    }

    func testSpanRoundTrips() throws {
        var widget = WidgetConfiguration(type: .spectrogram, size: WidgetSize(columns: 3, rows: 2))
        widget.homeSpan = HomeSpan(columns: 3, rows: 5)
        let data = try JSONEncoder().encode(widget)
        let decoded = try JSONDecoder().decode(WidgetConfiguration.self, from: data)
        XCTAssertEqual(decoded.homeSpan, HomeSpan(columns: 3, rows: 5))
        XCTAssertEqual(decoded.resolvedHomeSpan, HomeSpan(columns: 3, rows: 5))
    }

    @MainActor
    func testResizeHomeWidgetClampsSpanAndSynchronizesLegacySize() throws {
        let manager = DashboardManager()
        let widget = WidgetConfiguration(
            type: .spectrogram,
            size: WidgetSize(columns: 2, rows: 2)
        )
        manager.widgets = [widget]

        manager.resizeHomeWidget(id: widget.id, to: HomeSpan(columns: 9, rows: 20))

        XCTAssertEqual(manager.widgets[0].homeSpan, HomeSpan(columns: 4, rows: 7))
        XCTAssertEqual(manager.widgets[0].size, WidgetSize(columns: 3, rows: 4))

        let data = try JSONEncoder().encode(manager.widgets[0])
        let decoded = try JSONDecoder().decode(WidgetConfiguration.self, from: data)
        XCTAssertEqual(decoded.homeSpan, HomeSpan(columns: 4, rows: 7))
        XCTAssertEqual(decoded.size, WidgetSize(columns: 3, rows: 4))
    }

    @MainActor
    func testResizeHomeWidgetIgnoresIconsAndUnknownIDs() {
        let manager = DashboardManager()
        let icon = WidgetConfiguration(
            type: .spectrogram,
            size: WidgetSize(columns: 1, rows: 1),
            displayStyle: .icon
        )
        manager.widgets = [icon]

        manager.resizeHomeWidget(id: icon.id, to: HomeSpan(columns: 4, rows: 4))
        manager.resizeHomeWidget(id: UUID(), to: HomeSpan(columns: 4, rows: 4))

        XCTAssertEqual(manager.widgets, [icon])
    }

    // MARK: Packing

    func testIconsFlowAroundAWidget() {
        let widget = UUID()
        let icons = (0..<6).map { _ in UUID() }
        let items = [(id: widget, span: HomeSpan(columns: 2, rows: 2))] + icons.map { (id: $0, span: HomeSpan.single) }
        let packed = HomeGridPacker.pack(items)

        XCTAssertEqual(packed.placements[widget]?.column, 0)
        XCTAssertEqual(packed.placements[widget]?.row, 0)
        // First four icons fill the two free cells beside the widget on rows 0 and 1.
        XCTAssertEqual(packed.placements[icons[0]].map { [$0.column, $0.row] }, [2, 0])
        XCTAssertEqual(packed.placements[icons[1]].map { [$0.column, $0.row] }, [3, 0])
        XCTAssertEqual(packed.placements[icons[2]].map { [$0.column, $0.row] }, [2, 1])
        XCTAssertEqual(packed.placements[icons[3]].map { [$0.column, $0.row] }, [3, 1])
        XCTAssertEqual(packed.placements[icons[4]].map { [$0.column, $0.row] }, [0, 2])
        XCTAssertEqual(packed.rows, 3)
    }

    func testThreeWideWidgetLeavesOneColumnForIcons() {
        let widget = UUID()
        let icon = UUID()
        let packed = HomeGridPacker.pack([
            (id: widget, span: HomeSpan(columns: 3, rows: 2)),
            (id: icon, span: .single),
        ])
        XCTAssertEqual(packed.placements[icon].map { [$0.column, $0.row] }, [3, 0])
        XCTAssertEqual(packed.rows, 2)
    }

    func testOversizedSpanIsClampedToGridWidth() {
        let id = UUID()
        let packed = HomeGridPacker.pack([(id: id, span: HomeSpan(columns: 6, rows: 1))])
        XCTAssertEqual(packed.placements[id]?.span.columns, HomeGridMetrics.columns)
    }

    func testCompactHeightGridUsesAdditionalColumnsWithoutChangingWidgetSpans() {
        let widget = UUID()
        let icons = (0..<3).map { _ in UUID() }
        let packed = HomeGridPacker.pack(
            [(id: widget, span: HomeSpan(columns: 4, rows: 1))]
                + icons.map { (id: $0, span: HomeSpan.single) },
            columns: HomeGridMetrics.landscapeColumns
        )

        XCTAssertEqual(packed.placements[widget]?.span.columns, 4)
        XCTAssertEqual(packed.placements[icons[0]].map { [$0.column, $0.row] }, [4, 0])
        XCTAssertEqual(packed.placements[icons[1]].map { [$0.column, $0.row] }, [5, 0])
        XCTAssertEqual(packed.placements[icons[2]].map { [$0.column, $0.row] }, [0, 1])
    }

    func testLandscapeMetricsReduceCellPitchWhilePortraitKeepsFourColumns() {
        let portrait = HomeGridMetrics(width: 390)
        let landscape = HomeGridMetrics(width: 844, columns: HomeGridMetrics.landscapeColumns)

        XCTAssertEqual(portrait.gridColumns, HomeGridMetrics.columns)
        XCTAssertEqual(landscape.gridColumns, HomeGridMetrics.landscapeColumns)
        XCTAssertEqual(landscape.pitch, 134, accuracy: 1)
        XCTAssertLessThan(landscape.pitch, portrait.pitch * 2)
    }
}
