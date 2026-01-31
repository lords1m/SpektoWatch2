import Foundation

// MARK: - Watch Widget Types

public enum WatchWidgetType: String, Codable, CaseIterable, Identifiable {
    case spectrogram = "Spektrogramm"
    case levelMeter = "Pegel"
    case singleValue = "Wert"
    case loudness = "Lautheit"
    case empty = "Leer"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .spectrogram: return "waveform"
        case .levelMeter: return "gauge.with.needle"
        case .singleValue: return "textformat.123"
        case .loudness: return "speaker.wave.3"
        case .empty: return "square.dashed"
        }
    }
}

// MARK: - Watch Single Value Types

public enum WatchSingleValueType: String, Codable, CaseIterable {
    case laeq = "LAeq"
    case lceq = "LCeq"
    case lzeq = "LZeq"
    case lafMax = "LAF Max"
    case lafMin = "LAF Min"
    case lcfMax = "LCF Max"
    case lcfMin = "LCF Min"

    public var displayName: String { rawValue }
}

// MARK: - Watch Widget Configuration

public struct WatchWidgetConfig: Codable, Identifiable, Equatable {
    public let id: UUID
    public var type: WatchWidgetType
    public var position: Int // 0-15 for 4x4 grid
    public var singleValueType: WatchSingleValueType?

    public init(id: UUID = UUID(), type: WatchWidgetType, position: Int, singleValueType: WatchSingleValueType? = nil) {
        self.id = id
        self.type = type
        self.position = position
        self.singleValueType = singleValueType
    }

    public static func empty(at position: Int) -> WatchWidgetConfig {
        WatchWidgetConfig(type: .empty, position: position)
    }
}

// MARK: - Watch Dashboard Configuration

public struct WatchDashboardConfig: Codable, Equatable {
    public var widgets: [WatchWidgetConfig]
    public var version: Int

    public init(widgets: [WatchWidgetConfig] = WatchDashboardConfig.defaultWidgets, version: Int = 1) {
        self.widgets = widgets
        self.version = version
    }

    // Default layout: Spectrogram takes top 2x2, level meter and values below
    public static var defaultWidgets: [WatchWidgetConfig] {
        [
            // Top row (0-3): Spectrogram takes 4 cells
            WatchWidgetConfig(type: .spectrogram, position: 0),
            WatchWidgetConfig(type: .spectrogram, position: 1),
            WatchWidgetConfig(type: .spectrogram, position: 4),
            WatchWidgetConfig(type: .spectrogram, position: 5),

            // Middle right (2-3, 6-7): Level meter
            WatchWidgetConfig(type: .levelMeter, position: 2),
            WatchWidgetConfig(type: .levelMeter, position: 3),
            WatchWidgetConfig(type: .levelMeter, position: 6),
            WatchWidgetConfig(type: .levelMeter, position: 7),

            // Bottom row (8-11): Single values
            WatchWidgetConfig(type: .singleValue, position: 8, singleValueType: .laeq),
            WatchWidgetConfig(type: .singleValue, position: 9, singleValueType: .lafMax),
            WatchWidgetConfig(type: .singleValue, position: 10, singleValueType: .lceq),
            WatchWidgetConfig(type: .singleValue, position: 11, singleValueType: .lcfMax),

            // Bottom row (12-15): Empty
            WatchWidgetConfig(type: .empty, position: 12),
            WatchWidgetConfig(type: .empty, position: 13),
            WatchWidgetConfig(type: .empty, position: 14),
            WatchWidgetConfig(type: .empty, position: 15),
        ]
    }

    // Helper to get widget at grid position
    public func widget(at position: Int) -> WatchWidgetConfig? {
        widgets.first { $0.position == position }
    }

    // Helper to check if position is part of a multi-cell widget
    public func isPartOfMultiCell(at position: Int) -> Bool {
        // Check if this position is a secondary cell of a larger widget
        let spectrogramPositions = widgets.filter { $0.type == .spectrogram }.map { $0.position }
        let levelMeterPositions = widgets.filter { $0.type == .levelMeter }.map { $0.position }
        let loudnessPositions = widgets.filter { $0.type == .loudness }.map { $0.position }

        // Spectrogram and level meter span multiple cells
        if spectrogramPositions.count > 1 && spectrogramPositions.contains(position) {
            return position != spectrogramPositions.min()
        }
        if levelMeterPositions.count > 1 && levelMeterPositions.contains(position) {
            return position != levelMeterPositions.min()
        }
        if loudnessPositions.count > 1 && loudnessPositions.contains(position) {
            return position != loudnessPositions.min()
        }
        return false
    }

    // Encoding for WatchConnectivity
    public func encode() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public static func decode(from data: Data) -> WatchDashboardConfig? {
        try? JSONDecoder().decode(WatchDashboardConfig.self, from: data)
    }
}

// MARK: - UserDefaults Keys

public extension WatchDashboardConfig {
    static let userDefaultsKey = "watchDashboardConfig"

    static func load() -> WatchDashboardConfig {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = decode(from: data) else {
            return WatchDashboardConfig()
        }
        return config
    }

    func save() {
        if let data = encode() {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}
