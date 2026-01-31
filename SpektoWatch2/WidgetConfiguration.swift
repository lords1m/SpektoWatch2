import Foundation
import CoreGraphics

enum AudioWidgetType: String, Codable, CaseIterable, Identifiable {
    // Interaktive Widgets
    case toneGenerator = "Tongenerator"
    case fftParameters = "FFT-Parameter"
    case windowFunction = "Fensterfunktion"
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
        case .toneGenerator: return WidgetSize(columns: 2, rows: 2.0)
        case .fftParameters: return WidgetSize(columns: 2, rows: 1.5)
        case .windowFunction: return WidgetSize(columns: 2, rows: 1.5)
        case .spectrumComparison: return WidgetSize(columns: 2, rows: 2.0)
        }
    }
}
