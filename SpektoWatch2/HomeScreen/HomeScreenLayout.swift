import SwiftUI

// MARK: - Home-screen spans
//
// The in-app Home Screen follows the iOS Home Screen: a 4-column grid of
// square cells. Feature icons and single values take one cell; every other
// widget takes a free rectangle of cells (the spectrogram at least 2×2),
// set by dragging the widget's edges in jiggle mode.
//
// The span is stored next to the legacy 3-column `WidgetSize`. Widgets
// saved before spans existed have none and get one derived from their
// stored size, so old layouts need no migration.

/// Size of a Home Screen tile in grid cells (4 columns, square rows).
struct HomeSpan: Codable, Equatable, Hashable {
    var columns: Int
    var rows: Int

    init(columns: Int, rows: Int) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
    }

    static let single = HomeSpan(columns: 1, rows: 1)

    func clamped(min lo: HomeSpan, max hi: HomeSpan) -> HomeSpan {
        HomeSpan(columns: Swift.max(lo.columns, Swift.min(hi.columns, columns)),
                 rows: Swift.max(lo.rows, Swift.min(hi.rows, rows)))
    }

    /// "2×2", as shown in the size menu and the resize badge.
    var label: String { "\(columns)×\(rows)" }

    /// Name of the matching iOS widget family, if any.
    var familyName: String? {
        switch (columns, rows) {
        case (1, 1): return "Icon-Größe"
        case (2, 2): return "Klein"
        case (4, 2): return "Mittel"
        case (4, 4): return "Groß"
        case (4, HomeGridMetrics.maxRows): return "Ganze Seite"
        default: return nil
        }
    }

    /// Sizes offered in the context menu (drag-resize reaches all others).
    static let menuPresets: [HomeSpan] = [
        HomeSpan(columns: 1, rows: 1),
        HomeSpan(columns: 2, rows: 1),
        HomeSpan(columns: 2, rows: 2),
        HomeSpan(columns: 4, rows: 1),
        HomeSpan(columns: 4, rows: 2),
        HomeSpan(columns: 4, rows: 4),
        HomeSpan(columns: 4, rows: HomeGridMetrics.maxRows),
    ]
}

extension WidgetConfiguration {
    /// Smallest and largest span a widget type may take on the Home grid.
    /// Value widgets (number, meter) work in a single cell; anything with a
    /// header and a chart needs at least 2×2.
    static func homeSpanRange(for type: AudioWidgetType) -> (min: HomeSpan, max: HomeSpan) {
        let cols = HomeGridMetrics.columns
        let page = HomeGridMetrics.maxRows
        switch type {
        case .singleValue:
            return (.single, .single)
        case .levelMeter:
            return (HomeSpan(columns: 1, rows: 1), HomeSpan(columns: cols, rows: page))
        case .spectrogram, .waterfall, .toneGenerator, .spektralanalyseLab:
            return (HomeSpan(columns: 2, rows: 2), HomeSpan(columns: cols, rows: page))
        case .levelHistory, .frequencyDisplay, .octaveBands:
            return (HomeSpan(columns: 2, rows: 2), HomeSpan(columns: cols, rows: 6))
        case .phaseMeter, .masking, .audioEditor, .recordings, .settings:
            return (HomeSpan(columns: 2, rows: 2), HomeSpan(columns: cols, rows: 4))
        }
    }

    /// Clamps a span into the type's range; level meters additionally need
    /// two cells along their bar axis.
    static func normalizedHomeSpan(_ span: HomeSpan, for type: AudioWidgetType, settings: [String: String]) -> HomeSpan {
        let range = homeSpanRange(for: type)
        var result = span.clamped(min: range.min, max: range.max)
        if type == .levelMeter {
            switch WidgetSettings.levelMeterOrientation(settings) {
            case .horizontal: result.columns = max(result.columns, 2)
            case .vertical:   result.rows = max(result.rows, 2)
            }
        }
        return result.clamped(min: range.min, max: range.max)
    }

    /// Span for widgets saved before spans existed, from the 3-column size
    /// (the former small / medium / large / page families). A 1×1 size
    /// stays one cell, so single values land as 1×1 tiles.
    static func legacyHomeSpan(for size: WidgetSize) -> HomeSpan {
        let cols = HomeGridMetrics.columns
        if size.columns == 1 && size.rows == 1 { return .single }
        if size.columns < 3 {
            return size.rows <= 2 ? HomeSpan(columns: 2, rows: 2) : HomeSpan(columns: cols, rows: 4)
        }
        switch size.rows {
        case ...2: return HomeSpan(columns: cols, rows: 2)
        case 3:    return HomeSpan(columns: cols, rows: 4)
        default:   return HomeSpan(columns: cols, rows: HomeGridMetrics.maxRows)
        }
    }

    /// Nearest 3-column size for a span, so code that still reads `size`
    /// (dashboard card heights, icon ↔ widget switching) stays consistent.
    static func legacySize(for span: HomeSpan) -> WidgetSize {
        let columns: Int
        switch span.columns {
        case 1:  columns = 1
        case 2, 3: columns = 2
        default: columns = 3
        }
        let rows: Int
        switch span.rows {
        case 1:    rows = 1
        case 2:    rows = 2
        case 3, 4: rows = 3
        default:   rows = 4
        }
        return WidgetSize(columns: columns, rows: rows)
    }

    /// Whether the tile is drawn as an app icon (one cell, launches the feature).
    var isHomeIcon: Bool { displayStyle == .icon }

    /// The span this widget occupies on the Home grid.
    var resolvedHomeSpan: HomeSpan {
        if isHomeIcon { return .single }
        return Self.normalizedHomeSpan(homeSpan ?? Self.legacyHomeSpan(for: size), for: type, settings: settings)
    }

    /// Spans from `HomeSpan.menuPresets` this widget can take, de-duplicated
    /// after per-type normalisation.
    var availableHomeSpans: [HomeSpan] {
        guard !isHomeIcon else { return [] }
        var seen = Set<HomeSpan>()
        return HomeSpan.menuPresets.compactMap { preset in
            let span = Self.normalizedHomeSpan(preset, for: type, settings: settings)
            return seen.insert(span).inserted ? span : nil
        }
    }
}

// MARK: - Grid metrics

/// iOS-style geometry: four equal column pitches across the page, square
/// rows of the same pitch. Widgets align to the outer edges of the icons
/// they replace, so a small widget is exactly as wide as two icons plus
/// the gap between them.
struct HomeGridMetrics: Equatable {
    static let columns = 4
    /// Tallest span: a widget filling a whole page.
    static let maxRows = 7

    let width: CGFloat
    let margin: CGFloat
    let pitch: CGFloat
    let iconSize: CGFloat

    init(width: CGFloat) {
        self.width = width
        margin = width >= 400 ? 20 : 16
        pitch = (width - 2 * margin) / CGFloat(Self.columns)
        iconSize = min(64, (pitch * 0.68).rounded())
    }

    /// Gap between neighbouring icons / widgets.
    var gutter: CGFloat { pitch - iconSize }

    /// Frame for a tile placed at `column`/`row` spanning `span`, in page coordinates.
    func frame(column: Int, row: Int, span: HomeSpan, isIcon: Bool) -> CGRect {
        if isIcon {
            // Whole cell: icon on top, label underneath.
            return CGRect(x: margin + CGFloat(column) * pitch,
                          y: CGFloat(row) * pitch,
                          width: pitch,
                          height: pitch)
        }
        return CGRect(x: margin + CGFloat(column) * pitch + gutter / 2,
                      y: CGFloat(row) * pitch,
                      width: CGFloat(span.columns - 1) * pitch + iconSize,
                      height: CGFloat(span.rows - 1) * pitch + iconSize)
    }

    func height(rows: Int) -> CGFloat { CGFloat(rows) * pitch }
}

// MARK: - Packing

/// Places tiles the way iOS does: in order, each at the first free slot
/// scanning rows top to bottom, left to right. Smaller tiles flow into the
/// gaps next to larger ones, exactly like icons around a small widget on
/// the iOS Home Screen.
enum HomeGridPacker {
    struct Placement: Equatable {
        let column: Int
        let row: Int
        let span: HomeSpan
    }

    static func pack(_ items: [(id: UUID, span: HomeSpan)]) -> (placements: [UUID: Placement], rows: Int) {
        let columns = HomeGridMetrics.columns
        var occupied: [[Bool]] = []
        var placements: [UUID: Placement] = [:]

        func isFree(column: Int, row: Int, width: Int, height: Int) -> Bool {
            for r in row..<(row + height) {
                guard r < occupied.count else { continue }
                for c in column..<(column + width) where occupied[r][c] { return false }
            }
            return true
        }

        for item in items {
            let w = min(columns, max(1, item.span.columns))
            let h = max(1, item.span.rows)
            var row = 0
            var placed = false
            while !placed {
                for column in 0...(columns - w) where isFree(column: column, row: row, width: w, height: h) {
                    while occupied.count < row + h {
                        occupied.append(Array(repeating: false, count: columns))
                    }
                    for r in row..<(row + h) {
                        for c in column..<(column + w) { occupied[r][c] = true }
                    }
                    placements[item.id] = Placement(column: column, row: row,
                                                    span: HomeSpan(columns: w, rows: h))
                    placed = true
                    break
                }
                row += 1
            }
        }
        return (placements, occupied.count)
    }
}

// MARK: - Icon identity

extension AudioWidgetType {
    /// Short label under a Home Screen icon (iOS truncates long app names;
    /// these keep every label on one line).
    var homeShortName: String {
        switch self {
        case .spectrogram:        return "Spektrogramm"
        case .waterfall:          return "Wasserfall"
        case .levelHistory:       return "Pegelverlauf"
        case .frequencyDisplay:   return "Spektrum"
        case .levelMeter:         return "Pegel"
        case .octaveBands:        return "Terzen"
        case .phaseMeter:         return "Phase"
        case .singleValue:        return "Einzelwert"
        case .toneGenerator:      return "Tongenerator"
        case .spektralanalyseLab: return "Labor"
        case .audioEditor:        return "Editor"
        case .recordings:         return "Aufnahmen"
        case .settings:           return "Einstellungen"
        case .masking:            return "Masking"
        }
    }

    /// Line colour used as the accent bar on this feature's icon, like the
    /// colour of a U-Bahn line on a station sign. `nil` = plain ink.
    var homeIconLine: FerriteLine? {
        switch self {
        case .recordings:         return .u2
        case .toneGenerator:      return .u7
        case .audioEditor:        return .u6
        case .spektralanalyseLab: return .u5
        case .frequencyDisplay, .octaveBands: return .u4
        case .spectrogram, .waterfall: return .u8
        case .levelHistory, .levelMeter, .singleValue: return .u1
        case .phaseMeter, .masking: return .u3
        case .settings:           return nil
        }
    }
}
