import XCTest
@testable import SpektoWatch2

/// Tests for the M8 widget-sizing migration: legacy `Double` rows (the
/// pre-M8 0.5-step model) and out-of-range sizes must decode without
/// crash and end up clamped against `WidgetConfiguration.sizeRange(for:)`.
///
/// These tests are pure decoder tests — no XCUI, no simulator state. They
/// cover M8 task-2 acceptance check #2 ("App launches cleanly with an
/// existing dashboard with legacy `Double`-row values") from a code-side
/// angle: if the decode path is correct, the per-widget runtime check is
/// purely visual.
final class WidgetSizingMigrationTests: XCTestCase {

    // MARK: - WidgetSize decoding

    /// Legacy persisted blob: `rows` is a `Double` with a 0.5 fraction.
    /// Decoder must round to `Int` and clamp to `WidgetSize.absoluteMinimum`.
    func testWidgetSizeDecodesLegacyHalfRow() throws {
        let json = #"{"columns":2,"rows":0.5}"#.data(using: .utf8)!
        let size = try JSONDecoder().decode(WidgetSize.self, from: json)
        XCTAssertEqual(size.columns, 2)
        XCTAssertEqual(size.rows, 1, "0.5 should round to 0, then clamp up to absoluteMinimum (1).")
    }

    /// Legacy `Double` with whole-number value should round through cleanly.
    func testWidgetSizeDecodesLegacyDoubleWhole() throws {
        let json = #"{"columns":3,"rows":2.0}"#.data(using: .utf8)!
        let size = try JSONDecoder().decode(WidgetSize.self, from: json)
        XCTAssertEqual(size.columns, 3)
        XCTAssertEqual(size.rows, 2)
    }

    /// New format: `rows` as an `Int`. No coercion path needed.
    func testWidgetSizeDecodesNewIntRows() throws {
        let json = #"{"columns":3,"rows":4}"#.data(using: .utf8)!
        let size = try JSONDecoder().decode(WidgetSize.self, from: json)
        XCTAssertEqual(size.columns, 3)
        XCTAssertEqual(size.rows, 4)
    }

    /// A `WidgetSize` on its own enforces only `absoluteMinimum`. Per-type
    /// clamping happens at the `WidgetConfiguration` layer (see below).
    func testWidgetSizeRespectsAbsoluteMinimum() throws {
        let json = #"{"columns":0,"rows":0}"#.data(using: .utf8)!
        let size = try JSONDecoder().decode(WidgetSize.self, from: json)
        XCTAssertGreaterThanOrEqual(size.columns, WidgetSize.absoluteMinimum)
        XCTAssertGreaterThanOrEqual(size.rows, WidgetSize.absoluteMinimum)
    }

    // MARK: - WidgetConfiguration per-type clamping

    /// A spectrogram persisted at 1×0.5 (impossible under M8) must clamp up
    /// to the spectrogram's min size 2×2 on decode.
    func testSpectrogramLegacySizeClampsUpToMin() throws {
        let json = #"""
        {
          "id":"00000000-0000-0000-0000-000000000001",
          "type":"Spektrogramm",
          "gridPosition":{"index":0},
          "size":{"columns":1,"rows":0.5},
          "settings":{}
        }
        """#.data(using: .utf8)!
        let config = try JSONDecoder().decode(WidgetConfiguration.self, from: json)
        XCTAssertEqual(config.type, .spectrogram)
        let min = WidgetConfiguration.sizeRange(for: .spectrogram).min
        XCTAssertGreaterThanOrEqual(config.size.columns, min.columns)
        XCTAssertGreaterThanOrEqual(config.size.rows, min.rows)
        XCTAssertEqual(config.size.columns, 2)
        XCTAssertEqual(config.size.rows, 2)
    }

    /// A singleValue persisted at 4×6 (impossible under M8) must clamp
    /// down to the singleValue's max size 2×2 on decode.
    func testSingleValueLegacySizeClampsDownToMax() throws {
        let json = #"""
        {
          "id":"00000000-0000-0000-0000-000000000002",
          "type":"Einzelwert",
          "gridPosition":{"index":0},
          "size":{"columns":4,"rows":6},
          "settings":{}
        }
        """#.data(using: .utf8)!
        let config = try JSONDecoder().decode(WidgetConfiguration.self, from: json)
        XCTAssertEqual(config.type, .singleValue)
        let max = WidgetConfiguration.sizeRange(for: .singleValue).max
        XCTAssertLessThanOrEqual(config.size.columns, max.columns)
        XCTAssertLessThanOrEqual(config.size.rows, max.rows)
        XCTAssertEqual(config.size.columns, 2)
        XCTAssertEqual(config.size.rows, 2)
    }

    /// A legacy `octaveBands` widget should still decode (kept for
    /// backward compat; downstream `DashboardManager.normalizeWidgets`
    /// rewrites it to `frequencyDisplay`). M8 just needs the decode to
    /// succeed and the size to land inside the octaveBands range.
    func testLegacyOctaveBandsDecodes() throws {
        let json = #"""
        {
          "id":"00000000-0000-0000-0000-000000000003",
          "type":"1/3 Oktavbänder",
          "gridPosition":{"index":0},
          "size":{"columns":2,"rows":1.5},
          "settings":{}
        }
        """#.data(using: .utf8)!
        let config = try JSONDecoder().decode(WidgetConfiguration.self, from: json)
        XCTAssertEqual(config.type, .octaveBands)
        let range = WidgetConfiguration.sizeRange(for: .octaveBands)
        XCTAssertGreaterThanOrEqual(config.size.columns, range.min.columns)
        XCTAssertGreaterThanOrEqual(config.size.rows, range.min.rows)
        XCTAssertLessThanOrEqual(config.size.columns, range.max.columns)
        XCTAssertLessThanOrEqual(config.size.rows, range.max.rows)
    }

    // MARK: - sizeRange invariants

    /// Sanity: every widget type's `min` is element-wise ≤ `max`, and
    /// every widget's `defaultSize(for:)` lies inside its range.
    func testSizeRangesAreWellFormedAndDefaultsAreInRange() {
        for type in AudioWidgetType.allCases + [.octaveBands] {
            let range = WidgetConfiguration.sizeRange(for: type)
            XCTAssertLessThanOrEqual(range.min.columns, range.max.columns, "\(type) min.columns > max.columns")
            XCTAssertLessThanOrEqual(range.min.rows, range.max.rows, "\(type) min.rows > max.rows")

            let def = WidgetConfiguration.defaultSize(for: type)
            XCTAssertGreaterThanOrEqual(def.columns, range.min.columns, "\(type) default.columns below min")
            XCTAssertLessThanOrEqual(def.columns, range.max.columns, "\(type) default.columns above max")
            XCTAssertGreaterThanOrEqual(def.rows, range.min.rows, "\(type) default.rows below min")
            XCTAssertLessThanOrEqual(def.rows, range.max.rows, "\(type) default.rows above max")
        }
    }

    /// Round-trip: encode → decode → equal. Confirms the new
    /// integer-rows model survives serialization.
    func testWidgetConfigurationRoundTripsThroughJSON() throws {
        let original = WidgetConfiguration(
            type: .levelMeter,
            size: WidgetSize(columns: 1, rows: 2),
            gridPosition: GridPosition(index: 3),
            settings: ["timeWeighting": "Fast"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetConfiguration.self, from: data)
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.size.columns, original.size.columns)
        XCTAssertEqual(decoded.size.rows, original.size.rows)
        XCTAssertEqual(decoded.gridPosition.index, original.gridPosition.index)
        XCTAssertEqual(decoded.settings, original.settings)
    }

    @MainActor
    func testWidgetSizeScreenshotPresetCreatesOneLayoutPerVisibleType() {
        let manager = DashboardManager()
        manager.installWidgetSizeScreenshotPreset()

        XCTAssertEqual(manager.layouts.count, AudioWidgetType.allCases.count)
        XCTAssertEqual(manager.activeLayoutIndex, 0)

        for (index, type) in AudioWidgetType.allCases.enumerated() {
            XCTAssertEqual(manager.layouts[index].name, "Preset: \(type.rawValue)")
            XCTAssertTrue(manager.layouts[index].widgets.allSatisfy { $0.type == type })
        }

        manager.resetToDefault()
    }

    @MainActor
    func testWidgetSizeScreenshotPresetIncludesEveryAllowedSize() throws {
        let manager = DashboardManager()
        manager.installWidgetSizeScreenshotPreset()

        for type in AudioWidgetType.allCases {
            let layout = try XCTUnwrap(manager.layouts.first { $0.name == "Preset: \(type.rawValue)" })
            let range = WidgetConfiguration.sizeRange(for: type)
            let expectedSizes = Set(
                (range.min.rows...range.max.rows).flatMap { rows in
                    (range.min.columns...range.max.columns).map { columns in
                        "\(columns)x\(rows)"
                    }
                }
            )
            let actualSizes = Set(layout.widgets.map { "\($0.size.columns)x\($0.size.rows)" })

            XCTAssertEqual(actualSizes, expectedSizes, "\(type.rawValue) preset page does not contain every allowed size")
            XCTAssertEqual(layout.widgets.map(\.gridPosition.index), Array(0..<layout.widgets.count))
        }

        manager.resetToDefault()
    }
}
