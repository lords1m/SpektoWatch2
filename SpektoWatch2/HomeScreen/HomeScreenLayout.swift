import SwiftUI

// MARK: - Home-screen families
//
// The in-app Home Screen follows the iOS Home Screen: a 4-column grid of
// square cells. Feature icons take one cell; live widgets take one of the
// iOS widget families. The persisted `WidgetSize` (3-column dashboard
// model) is kept unchanged and mapped onto these families, so stored
// layouts need no migration.

enum HomeTileFamily: CaseIterable, Equatable {
    /// App icon with label, 1×1 cell.
    case icon
    /// Small widget, 2×2 cells.
    case small
    /// Medium widget, 4×2 cells.
    case medium
    /// Large widget, 4×4 cells.
    case large
    /// Full-page widget for single-feature pages (Tongenerator, Labor …), 4×7 cells.
    case page

    var cells: (columns: Int, rows: Int) {
        switch self {
        case .icon:   return (1, 1)
        case .small:  return (2, 2)
        case .medium: return (4, 2)
        case .large:  return (4, 4)
        case .page:   return (4, 7)
        }
    }

    var label: String {
        switch self {
        case .icon:   return "Icon"
        case .small:  return "Klein"
        case .medium: return "Mittel"
        case .large:  return "Groß"
        case .page:   return "Ganze Seite"
        }
    }

    var symbol: String {
        switch self {
        case .icon:   return "app"
        case .small:  return "square"
        case .medium: return "rectangle"
        case .large:  return "square.fill"
        case .page:   return "rectangle.portrait"
        }
    }

    /// The 3-column dashboard size that represents this family.
    fileprivate var modelSize: WidgetSize {
        switch self {
        case .icon:   return WidgetSize(columns: 1, rows: 1)
        case .small:  return WidgetSize(columns: 2, rows: 2)
        case .medium: return WidgetSize(columns: 3, rows: 2)
        case .large:  return WidgetSize(columns: 3, rows: 3)
        case .page:   return WidgetSize(columns: 3, rows: 4)
        }
    }

    /// Maps a stored dashboard size onto a family.
    static func family(for size: WidgetSize, displayStyle: WidgetDisplayStyle) -> HomeTileFamily {
        if displayStyle == .icon { return .icon }
        if size.columns < 3 { return size.rows <= 2 ? .small : .large }
        switch size.rows {
        case ...2: return .medium
        case 3:    return .large
        default:   return .page
        }
    }
}

extension WidgetConfiguration {
    var homeFamily: HomeTileFamily {
        HomeTileFamily.family(for: size, displayStyle: displayStyle)
    }

    /// Widget families this widget type can take on the Home Screen, each
    /// with the stored size that produces it (after per-type clamping).
    var availableHomeFamilies: [(family: HomeTileFamily, size: WidgetSize)] {
        guard displayStyle == .liveWidget else { return [] }
        let range = WidgetConfiguration.sizeRange(for: type, displayStyle: .liveWidget)
        var result: [(HomeTileFamily, WidgetSize)] = []
        for family in HomeTileFamily.allCases where family != .icon {
            let size = WidgetConfiguration.normalizedSize(
                for: type,
                size: family.modelSize.clamped(min: range.min, max: range.max),
                settings: settings
            )
            if HomeTileFamily.family(for: size, displayStyle: .liveWidget) == family {
                result.append((family, size))
            }
        }
        return result
    }
}

// MARK: - Grid metrics

/// iOS-style geometry: four equal column pitches across the page, square
/// rows of the same pitch. Widgets align to the outer edges of the icons
/// they replace, so a small widget is exactly as wide as two icons plus
/// the gap between them.
struct HomeGridMetrics: Equatable {
    static let columns = 4

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

    /// Frame for a tile placed at `column`/`row` with `family`, in page coordinates.
    func frame(column: Int, row: Int, family: HomeTileFamily) -> CGRect {
        let cells = family.cells
        if family == .icon {
            // Whole cell: icon on top, label underneath.
            return CGRect(x: margin + CGFloat(column) * pitch,
                          y: CGFloat(row) * pitch,
                          width: pitch,
                          height: pitch)
        }
        return CGRect(x: margin + CGFloat(column) * pitch + gutter / 2,
                      y: CGFloat(row) * pitch,
                      width: CGFloat(cells.columns - 1) * pitch + iconSize,
                      height: CGFloat(cells.rows - 1) * pitch + iconSize)
    }

    func height(rows: Int) -> CGFloat { CGFloat(rows) * pitch }
}

// MARK: - Packing

/// Places tiles the way iOS does: in order, each at the first free slot
/// scanning rows top to bottom. Small widgets snap to column 0 or 2, wide
/// widgets to column 0, icons fill any free cell — so icons flow around
/// small widgets exactly like on the iOS Home Screen.
enum HomeGridPacker {
    struct Placement: Equatable {
        let column: Int
        let row: Int
        let family: HomeTileFamily
    }

    static func pack(_ items: [(id: UUID, family: HomeTileFamily)]) -> (placements: [UUID: Placement], rows: Int) {
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
            let (w, h) = item.family.cells
            let allowedColumns: [Int]
            switch w {
            case 1: allowedColumns = Array(0..<columns)
            case 2: allowedColumns = [0, 2]
            default: allowedColumns = [0]
            }
            var row = 0
            var placed = false
            while !placed {
                for column in allowedColumns where isFree(column: column, row: row, width: w, height: h) {
                    while occupied.count < row + h {
                        occupied.append(Array(repeating: false, count: columns))
                    }
                    for r in row..<(row + h) {
                        for c in column..<(column + w) { occupied[r][c] = true }
                    }
                    placements[item.id] = Placement(column: column, row: row, family: item.family)
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
