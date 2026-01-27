import Foundation
import CoreGraphics

enum AudioWidgetType: String, Codable, CaseIterable, Identifiable {
    case spectrogram = "Spektrogramm"
    case lafGraph = "LAF Verlauf"
    case frequencyDisplay = "Frequenz-Spektrum"
    case levelMeter = "Pegel-Meter"
    case octaveBands = "1/3 Oktavbänder"
    case phaseMeter = "Phasen-Meter"
    
    var id: String { rawValue }
}

enum WidgetSize: String, Codable, CaseIterable {
    case small = "Klein"        // 1 Spalte
    case medium = "Mittel"      // 1 Spalte
    case large = "Groß"        // 2 Spalten
    case wide = "Breit"         // 2 Spalten
    case full = "Vollbild"      // 2 Spalten
    
    var height: CGFloat {
        switch self {
        case .small: return 180
        case .medium: return 250
        case .large: return 350
        case .wide: return 200
        case .full: return 400
        }
    }
    
    /// Anzahl der Spalten die das Widget im Grid einnimmt (bei 2-Spalten-Layout)
    var gridColumns: Int {
        switch self {
        case .small: return 1
        case .medium: return 1
        case .large: return 2   // Volle Breite
        case .wide: return 2    // Volle Breite
        case .full: return 2    // Volle Breite
        }
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
        case .spectrogram: return .full      // Groß und breit
        case .lafGraph: return .large        // Groß und breit
        case .frequencyDisplay: return .large // Groß und breit
        case .levelMeter: return .medium     // Mittel
        case .octaveBands: return .large     // Groß und breit
        case .phaseMeter: return .medium     // Mittel
        }
    }
}
