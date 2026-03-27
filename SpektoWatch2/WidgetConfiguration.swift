import Foundation
import CoreGraphics

enum AudioWidgetType: String, Codable, CaseIterable, Identifiable {
    case spectrogram = "Spektrogramm"
    case levelHistory = "Pegelverlauf"
    case frequencyDisplay = "Frequenz-Spektrum"
    case levelMeter = "Pegel-Meter"
    case octaveBands = "1/3 Oktavbänder"
    case phaseMeter = "Phasen-Meter"
    case singleValue = "Einzelwert"
    case toneGenerator = "Tongenerator"
    case spektralanalyseLab = "Spektralanalyse-Labor"

    var id: String { rawValue }

    // Keep `octaveBands` for backward-compatible decoding, but hide it from picker options.
    static var allCases: [AudioWidgetType] {
        [
            .spectrogram,
            .levelHistory,
            .frequencyDisplay,
            .levelMeter,
            .phaseMeter,
            .singleValue,
            .toneGenerator,
            .spektralanalyseLab
        ]
    }
}

struct WidgetSize: Codable, Equatable {
    var columns: Int
    var rows: Double

    var height: CGFloat {
        let baseHeight: CGFloat = 200 // Basis-Höhe pro Zeile
        return CGFloat(rows) * baseHeight + CGFloat(max(0, rows - 1.0)) * 12 // + spacing
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
        case .levelHistory: return WidgetSize(columns: 2, rows: 1.0)
        case .frequencyDisplay: return WidgetSize(columns: 2, rows: 1.0)
        case .levelMeter: return WidgetSize(columns: 1, rows: 1.0)
        case .octaveBands: return WidgetSize(columns: 2, rows: 1.0)
        case .phaseMeter: return WidgetSize(columns: 1, rows: 1.0)
        case .singleValue: return WidgetSize(columns: 1, rows: 1.0)
        case .toneGenerator: return WidgetSize(columns: 2, rows: 2.0)
        case .spektralanalyseLab: return WidgetSize(columns: 2, rows: 2.0)
        }
    }
}

enum WidgetSettings {
    static let useWidgetOverridesKey = "useWidgetOverrides"
    static let defaultSpectrogramColormap = 0
    static let defaultTimeSpanSeconds = 5
    static let defaultSpectrogramSensitivity: Float = 90.0
    static let defaultSpectrumBandMode = "terz"
    static let defaultSingleValueMetric = "LAF"
    static let defaultLevelHistoryMetric = "AUTO"

    static func usesWidgetOverrides(_ settings: [String: String]) -> Bool {
        guard let rawValue = settings[useWidgetOverridesKey]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return rawValue == "1" || rawValue == "true" || rawValue == "yes" || rawValue == "on"
    }
}
