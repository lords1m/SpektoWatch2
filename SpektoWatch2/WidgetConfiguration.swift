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

    // Keep `octaveBands` for backward-compatible decoding, but hide it from picker options.
    static var allCases: [AudioWidgetType] {
        [
            .spectrogram,
            .waterfall,
            .levelHistory,
            .frequencyDisplay,
            .levelMeter,
            .phaseMeter,
            .singleValue,
            .toneGenerator,
            .spektralanalyseLab,
            .masking
        ]
    }
}

struct WidgetSize: Codable, Equatable {
    /// Minimum permitted `rows`. A widget rendered with `rows == 0` produces
    /// `height == 0`, which makes the Metal-backed widgets ask MetalKit for a
    /// zero-sized drawable and crashes the draw loop. Clamping at the model
    /// layer means any corrupt/legacy persisted value still yields a usable
    /// widget instead of a broken UI.
    static let minimumRows: Double = 0.5

    var columns: Int

    /// Persisted backing for `rows`. Always read/written via `rows` so the
    /// minimum is enforced for every code path (mutation, decode, defaults).
    private var _rows: Double

    var rows: Double {
        get { _rows }
        set { _rows = max(WidgetSize.minimumRows, newValue) }
    }

    init(columns: Int, rows: Double) {
        self.columns = columns
        self._rows = max(WidgetSize.minimumRows, rows)
    }

    var height: CGFloat {
        let baseHeight: CGFloat = 200 // Basis-Höhe pro Zeile
        return CGFloat(rows) * baseHeight + CGFloat(max(0, rows - 1.0)) * 12 // + spacing
    }

    // MARK: - Codable migration
    //
    // Keep the JSON key as `rows` (matches legacy persisted dashboards). The
    // custom decoder coerces any value below `minimumRows` — including a
    // zero left by a buggy/older writer — to the minimum, preventing the
    // Metal zero-size crash on load.
    private enum CodingKeys: String, CodingKey {
        case columns
        case rows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let columns = try container.decode(Int.self, forKey: .columns)
        let rawRows = try container.decode(Double.self, forKey: .rows)
        self.columns = columns
        self._rows = max(WidgetSize.minimumRows, rawRows)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(columns, forKey: .columns)
        try container.encode(rows, forKey: .rows)
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
        self.size = size
        self.gridPosition = gridPosition
        self.settings = settings
    }

    static func defaultSize(for type: AudioWidgetType) -> WidgetSize {
        switch type {
        case .spectrogram: return WidgetSize(columns: 2, rows: 2.0)
        case .waterfall: return WidgetSize(columns: 2, rows: 2.0)
        case .levelHistory: return WidgetSize(columns: 2, rows: 1.0)
        case .frequencyDisplay: return WidgetSize(columns: 2, rows: 1.0)
        case .levelMeter: return WidgetSize(columns: 1, rows: 1.0)
        case .octaveBands: return WidgetSize(columns: 2, rows: 1.0)
        case .phaseMeter: return WidgetSize(columns: 1, rows: 1.0)
        case .singleValue: return WidgetSize(columns: 1, rows: 1.0)
        case .toneGenerator: return WidgetSize(columns: 2, rows: 2.0)
        case .spektralanalyseLab: return WidgetSize(columns: 2, rows: 2.0)
        case .masking: return WidgetSize(columns: 1, rows: 1.0)
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
    static let defaultWaterfallMinDB: Float = -110
    static let defaultWaterfallMaxDB: Float = 20
    static let defaultSingleValueMetric = "LAF"
    static let defaultLevelHistoryMetric = "AUTO"

    static func usesWidgetOverrides(_ settings: [String: String]) -> Bool {
        guard let rawValue = settings[useWidgetOverridesKey]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return rawValue == "1" || rawValue == "true" || rawValue == "yes" || rawValue == "on"
    }
}
