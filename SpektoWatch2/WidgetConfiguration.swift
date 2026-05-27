import Foundation
import CoreGraphics

enum AudioWidgetType: String, Codable, CaseIterable, Identifiable {
    case spectrogram = "Spektrogramm"
    case waterfall = "Wasserfall"
    case levelHistory = "Pegelverlauf"
    case frequencyDisplay = "Frequenz-Spektrum"
    case levelMeter = "Pegel-Meter"
    case octaveBands = "1/3 Oktavbänder"
    case phaseMeter = "Phasen-Meter"
    case singleValue = "Einzelwert"
    case toneGenerator = "Tongenerator"
    case spektralanalyseLab = "Spektralanalyse-Labor"
    case masking = "Sound Masking"

    var id: String { rawValue }

    // Keep `octaveBands` and `phaseMeter` for backward-compatible
    // decoding, but hide them from picker options. phaseMeter is
    // deactivated as a product decision; existing instances are
    // filtered out by DashboardManager.normalizeWidgets on load.
    static var allCases: [AudioWidgetType] {
        [
            .spectrogram,
            .waterfall,
            .levelHistory,
            .frequencyDisplay,
            .levelMeter,
            .singleValue,
            .toneGenerator,
            .spektralanalyseLab,
            .masking
        ]
    }
}

/// Discrete grid cell occupancy for a widget. Always integer rows + columns —
/// half-rows are gone in M8 (see `agent/milestones/milestone-8-widget-sizing-refactor.md`).
///
/// Construction does **not** enforce per-type bounds: a bare `WidgetSize` is
/// the unit, and clamping against the widget type's range happens at the
/// container layer (`WidgetConfiguration.init(from:)`, `DashboardManager.resizeWidget`,
/// `WidgetCardView.handleResize`). Keeping the model dumb avoids
/// `WidgetSize` needing to know about `AudioWidgetType`.
///
/// The only invariant enforced here is the absolute floor: a widget cannot
/// have `< 1` columns or rows because that produces a zero-sized drawable and
/// crashes the Metal-backed widgets' draw loop (originally the M3
/// `minimumRows = 0.5` clamp; now hard `1`).
struct WidgetSize: Codable, Equatable {
    /// Hard floor enforced by the model. Per-type minimums are higher and
    /// applied at the container layer via `WidgetConfiguration.sizeRange(for:)`.
    static let absoluteMinimum: Int = 1

    var columns: Int

    private var _rows: Int

    var rows: Int {
        get { _rows }
        set { _rows = max(WidgetSize.absoluteMinimum, newValue) }
    }

    init(columns: Int, rows: Int) {
        self.columns = max(WidgetSize.absoluteMinimum, columns)
        self._rows = max(WidgetSize.absoluteMinimum, rows)
    }

    /// Base height per row (pt). The 200-pt baseline is a UX choice carried
    /// over from the pre-M8 implementation — kept stable to avoid shifting
    /// every dashboard's vertical footprint on the migration.
    var height: CGFloat {
        let baseHeight: CGFloat = 200
        let spacing: CGFloat = 12
        return CGFloat(rows) * baseHeight + CGFloat(max(0, rows - 1)) * spacing
    }

    // MARK: - Codable migration
    //
    // The JSON key is still `rows`, but the legacy value type was `Double`
    // (with 0.5-step support). The decoder accepts either — `Double` is
    // rounded to the nearest `Int`. Per-type clamping happens at the
    // `WidgetConfiguration` layer, not here.
    private enum CodingKeys: String, CodingKey {
        case columns
        case rows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let columns = try container.decode(Int.self, forKey: .columns)
        let rows: Int
        if let intRows = try? container.decode(Int.self, forKey: .rows) {
            rows = intRows
        } else {
            let doubleRows = try container.decode(Double.self, forKey: .rows)
            rows = Int(doubleRows.rounded())
        }
        self.columns = max(WidgetSize.absoluteMinimum, columns)
        self._rows = max(WidgetSize.absoluteMinimum, rows)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(columns, forKey: .columns)
        try container.encode(rows, forKey: .rows)
    }

    /// Returns a new size clamped element-wise into the inclusive range
    /// `[min, max]`. Used by `WidgetConfiguration.init(from:)` and the
    /// resize handlers.
    func clamped(min minSize: WidgetSize, max maxSize: WidgetSize) -> WidgetSize {
        let cols = Swift.max(minSize.columns, Swift.min(maxSize.columns, columns))
        let rs   = Swift.max(minSize.rows,    Swift.min(maxSize.rows,    rows))
        return WidgetSize(columns: cols, rows: rs)
    }
}

struct GridPosition: Codable, Equatable {
    var index: Int
}

struct WidgetConfiguration: Identifiable, Codable {
    let id: UUID
    var type: AudioWidgetType
    var gridPosition: GridPosition
    var size: WidgetSize
    var settings: [String: String]

    init(type: AudioWidgetType, size: WidgetSize, gridPosition: GridPosition = GridPosition(index: 0), settings: [String: String] = [:]) {
        self.id = UUID()
        self.type = type
        self.size = size.clamped(
            min: WidgetConfiguration.sizeRange(for: type).min,
            max: WidgetConfiguration.sizeRange(for: type).max
        )
        self.gridPosition = gridPosition
        self.settings = settings
    }

    // MARK: - Codable migration
    //
    // `type` must be decoded before `size` so that a legacy `WidgetSize`
    // with a half-row value (or a value outside the new per-type range)
    // gets clamped against the right range. The default synthesized
    // initializer would not guarantee ordering, hence the explicit form.

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case gridPosition
        case size
        case settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.type = try container.decode(AudioWidgetType.self, forKey: .type)
        self.gridPosition = try container.decode(GridPosition.self, forKey: .gridPosition)
        self.settings = try container.decode([String: String].self, forKey: .settings)
        let rawSize = try container.decode(WidgetSize.self, forKey: .size)
        let range = WidgetConfiguration.sizeRange(for: self.type)
        self.size = rawSize.clamped(min: range.min, max: range.max)
    }

    // MARK: - Per-type sizing rules
    //
    // Single source of truth for what each widget type is allowed to occupy
    // in the 3-column dashboard grid. Read by:
    //   - `defaultSize(for:)` below (initial placement),
    //   - `init(from:)` above (legacy clamp on decode),
    //   - `DashboardManager.resizeWidget(...)` (programmatic resize),
    //   - `WidgetCardView.handleResize(...)` (drag resize).
    //
    // If you adjust the matrix here, no other call site needs updating.
    static func sizeRange(for type: AudioWidgetType) -> (min: WidgetSize, max: WidgetSize) {
        switch type {
        case .spectrogram, .waterfall, .toneGenerator, .spektralanalyseLab:
            return (min: WidgetSize(columns: 2, rows: 2), max: WidgetSize(columns: 3, rows: 4))
        case .levelHistory, .frequencyDisplay, .octaveBands:
            return (min: WidgetSize(columns: 2, rows: 1), max: WidgetSize(columns: 3, rows: 3))
        case .levelMeter:
            return (min: WidgetSize(columns: 1, rows: 1), max: WidgetSize(columns: 2, rows: 3))
        case .phaseMeter:
            return (min: WidgetSize(columns: 1, rows: 1), max: WidgetSize(columns: 2, rows: 2))
        case .singleValue:
            return (min: WidgetSize(columns: 1, rows: 1), max: WidgetSize(columns: 2, rows: 2))
        case .masking:
            return (min: WidgetSize(columns: 1, rows: 1), max: WidgetSize(columns: 3, rows: 3))
        }
    }

    /// Base height (pt) for a single row of this widget type. Most widgets
    /// keep the historical 200pt baseline so chart/spectrogram layouts stay
    /// untouched; compact value-readout widgets get a shorter baseline so
    /// `1×1` cells don't waste vertical space around a single number.
    static func baseRowHeight(for type: AudioWidgetType) -> CGFloat {
        switch type {
        case .singleValue, .levelMeter, .phaseMeter:
            return 110
        default:
            return 200
        }
    }

    /// Total height for this widget's frame, derived from its type's base
    /// row height + spacing between rows. Replaces direct reads of
    /// `widget.size.height` so per-type row heights take effect.
    var frameHeight: CGFloat {
        let baseHeight = WidgetConfiguration.baseRowHeight(for: type)
        let spacing: CGFloat = 12
        return CGFloat(size.rows) * baseHeight + CGFloat(max(0, size.rows - 1)) * spacing
    }

    static func defaultSize(for type: AudioWidgetType) -> WidgetSize {
        switch type {
        case .spectrogram, .waterfall, .toneGenerator, .spektralanalyseLab:
            return WidgetSize(columns: 3, rows: 3)
        case .levelHistory, .frequencyDisplay, .octaveBands:
            return WidgetSize(columns: 3, rows: 2)
        case .levelMeter, .phaseMeter:
            return WidgetSize(columns: 1, rows: 2)
        case .singleValue:
            return WidgetSize(columns: 1, rows: 1)
        case .masking:
            return WidgetSize(columns: 2, rows: 2)
        }
    }
}

enum WidgetSettings {
    static let useWidgetOverridesKey = "useWidgetOverrides"
    static let defaultSpectrogramColormap = 0
    static let defaultTimeSpanSeconds = 5
    static let defaultSpectrogramSensitivity: Float = 90.0
    static let defaultSpectrumBandMode = "terz"
    static let defaultWaterfallSliceCount = 96
    // Magnitudes from AudioEngine are already calibrated dB SPL
    // (dBFS + calibrationOffset, see AudioEngine.swift line ~1303),
    // so the waterfall range lives in positive SPL space, not dBFS.
    static let defaultWaterfallMinDB: Float = 30
    static let defaultWaterfallMaxDB: Float = 110
    static let defaultSingleValueMetric = "LAF"
    static let defaultLevelHistoryMetric = "AUTO"
    // Shared Y-axis range defaults (dB SPL). Used by chart widgets
    // (LevelHistory, FrequencySpectrum) when no per-widget override
    // is configured. Waterfall uses its own range keys (waterfallMinDB
    // / waterfallMaxDB) — kept separate to preserve legacy decoding.
    static let defaultChartYMinDB: Float = 20
    static let defaultChartYMaxDB: Float = 110
    /// Per-widget noise floor in dB SPL. −120 means off (no suppression).
    /// Spectrogram: soft-knee gate below the floor. SingleValue: display guard.
    /// Waterfall: floor is minDB; soft-knee is always on (fixed 6 dB, no key needed).
    /// Chart widgets: floor is chartYMinDB; no separate key.
    static let defaultNoiseFloor: Float = -120.0

    static func noiseFloorDB(_ settings: [String: String]) -> Float {
        guard usesWidgetOverrides(settings),
              let raw = settings["noiseFloor"],
              let v = Float(raw) else { return defaultNoiseFloor }
        return v
    }

    static func chartYMinDB(_ settings: [String: String]) -> Float {
        guard usesWidgetOverrides(settings),
              let raw = settings["chartYMinDB"],
              let v = Float(raw) else { return defaultChartYMinDB }
        return v
    }

    static func chartYMaxDB(_ settings: [String: String]) -> Float {
        guard usesWidgetOverrides(settings),
              let raw = settings["chartYMaxDB"],
              let v = Float(raw) else { return defaultChartYMaxDB }
        return v
    }

    static func usesWidgetOverrides(_ settings: [String: String]) -> Bool {
        guard let rawValue = settings[useWidgetOverridesKey]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return rawValue == "1" || rawValue == "true" || rawValue == "yes" || rawValue == "on"
    }
}
