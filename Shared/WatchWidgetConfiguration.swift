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

    /// Column count on the watch dashboard (`WatchDashboardView`).
    public static let watchDisplayColumnCount = 3

    /// Legacy phone editor used a 4×4 grid with duplicate cells per widget type.
    public static let legacyEditorGridColumns = 4

    /// Default layout: one entry per visible widget, `position` = display order (0…n).
    public static var defaultWidgets: [WatchWidgetConfig] {
        [
            WatchWidgetConfig(type: .spectrogram, position: 0),
            WatchWidgetConfig(type: .levelMeter, position: 1),
            WatchWidgetConfig(type: .singleValue, position: 2, singleValueType: .laeq),
            WatchWidgetConfig(type: .singleValue, position: 3, singleValueType: .lafMax),
            WatchWidgetConfig(type: .singleValue, position: 4, singleValueType: .lceq),
            WatchWidgetConfig(type: .singleValue, position: 5, singleValueType: .lcfMax),
        ]
    }

    /// Widgets rendered on the watch: sorted by `position`, one row per type (multiple single-value metrics allowed).
    public var orderedDisplayWidgets: [WatchWidgetConfig] {
        var seenKeys = Set<String>()
        return widgets
            .sorted { $0.position < $1.position }
            .filter { widget in
                guard widget.type != .empty else { return false }
                let key = Self.displayKey(for: widget)
                return seenKeys.insert(key).inserted
            }
    }

    /// Stable dedupe key matching `WatchDashboardView` rendering.
    public static func displayKey(for widget: WatchWidgetConfig) -> String {
        if widget.type == .singleValue {
            return "singleValue-\(widget.singleValueType?.rawValue ?? "")"
        }
        return widget.type.rawValue
    }

    /// Collapses legacy 4×4 multi-cell entries to one slot per visible widget and reindexes `position`.
    public mutating func normalizeLegacyGridIfNeeded() {
        let normalized = Self.collapseLegacyGrid(widgets).enumerated().map { index, widget in
            WatchWidgetConfig(
                id: widget.id,
                type: widget.type,
                position: index,
                singleValueType: widget.singleValueType
            )
        }
        guard widgets != normalized else { return }
        widgets = normalized
        version += 1
    }

    private static func collapseLegacyGrid(_ widgets: [WatchWidgetConfig]) -> [WatchWidgetConfig] {
        var result: [WatchWidgetConfig] = []
        var seenKeys = Set<String>()

        for widget in widgets.sorted(by: { $0.position < $1.position }) {
            guard widget.type != .empty else { continue }
            let key = displayKey(for: widget)
            guard seenKeys.insert(key).inserted else { continue }
            result.append(widget)
        }
        return result
    }

    public mutating func replaceOrderedDisplayWidgets(_ displayWidgets: [WatchWidgetConfig]) {
        widgets = displayWidgets.enumerated().map { index, widget in
            WatchWidgetConfig(
                id: widget.id,
                type: widget.type,
                position: index,
                singleValueType: widget.singleValueType
            )
        }
        version += 1
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
    static let userDefaultsKey = PersistenceKeys.watchDashboardConfig

    static func load() -> WatchDashboardConfig {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              var config = decode(from: data) else {
            return WatchDashboardConfig()
        }
        let before = config.widgets
        config.normalizeLegacyGridIfNeeded()
        if config.widgets != before {
            config.save()
        }
        return config
    }

    func save() {
        if let data = encode() {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}
