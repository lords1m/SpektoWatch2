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
    // Spektralanalyse-Labor Widgets
    case fftParameters = "FFT-Parameter"
    case windowFunction = "Fensterfunktion"
    case heisenbergResolution = "Zeit-Frequenz"
    case spectrumComparison = "Spektrum-Vergleich"

    var id: String { rawValue }
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
        // Spektralanalyse-Labor Widgets
        case .fftParameters: return WidgetSize(columns: 2, rows: 1.5)
        case .windowFunction: return WidgetSize(columns: 2, rows: 1.5)
        case .heisenbergResolution: return WidgetSize(columns: 2, rows: 1.5)
        case .spectrumComparison: return WidgetSize(columns: 2, rows: 2.0)
        }
    }
}