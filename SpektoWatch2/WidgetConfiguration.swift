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
    case small   // 1x1
    case medium  // 2x1
    case large   // 2x2
    case wide    // 3x1
    case full    // Volle Breite
    
    var height: CGFloat {
        switch self {
        case .small: return 150
        case .medium: return 150
        case .large: return 300
        case .wide: return 150
        case .full: return 200
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
        case .spectrogram: return .large
        case .lafGraph: return .medium
        case .frequencyDisplay: return .medium
        case .levelMeter: return .small
        case .octaveBands: return .medium
        case .phaseMeter: return .small
        }
    }
}