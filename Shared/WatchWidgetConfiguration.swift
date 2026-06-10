import Foundation
import Combine

// MARK: - Single-value display refresh rate

/// UI update cadence for numeric single-value tiles (watch + iPhone).
public enum SingleValueRefreshRate: String, Codable, CaseIterable, Identifiable, Equatable {
    /// Follow the live metrics stream (no extra throttling).
    case max = "max"
    case hz10 = "10"
    case hz5 = "5"
    case hz2 = "2"
    case hz1 = "1"

    public var id: String { rawValue }

    public static let `default`: Self = .hz5

    /// Minimum seconds between UI updates; `0` means unthrottled.
    public var minimumInterval: TimeInterval {
        switch self {
        case .max: return 0
        case .hz10: return 0.1
        case .hz5: return 0.2
        case .hz2: return 0.5
        case .hz1: return 1.0
        }
    }

    public var displayName: String {
        switch self {
        case .max: return "Maximal (Quelle)"
        case .hz10: return "10 Hz"
        case .hz5: return "5 Hz"
        case .hz2: return "2 Hz"
        case .hz1: return "1 Hz"
        }
    }

    public func resolvedRate(perWidget override: SingleValueRefreshRate?) -> SingleValueRefreshRate {
        override ?? self
    }
}

// MARK: - Level meter orientation

/// Bar fill direction for dashboard level-meter tiles (watch + iPhone).
public enum LevelMeterOrientation: String, Codable, CaseIterable, Identifiable, Equatable {
    case horizontal
    case vertical

    public var id: String { rawValue }

    public static let `default`: Self = .horizontal

    public var displayName: String {
        switch self {
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertikal"
        }
    }
}

extension Publisher {
    /// Throttles a live-metrics publisher for single-value UI updates.
    public func throttledForSingleValueDisplay(
        rate: SingleValueRefreshRate
    ) -> AnyPublisher<Output, Failure> {
        let interval = rate.minimumInterval
        guard interval > 0 else { return eraseToAnyPublisher() }
        return throttle(for: .seconds(interval), scheduler: RunLoop.main, latest: true)
            .eraseToAnyPublisher()
    }

    /// Throttles high-frequency Canvas / graph updates on watchOS (~5 Hz).
    public func throttledForWatchLiveDisplay(
        interval: TimeInterval = SingleValueRefreshRate.default.minimumInterval
    ) -> AnyPublisher<Output, Failure> {
        guard interval > 0 else { return eraseToAnyPublisher() }
        return throttle(for: .seconds(interval), scheduler: RunLoop.main, latest: true)
            .eraseToAnyPublisher()
    }
}

// MARK: - Watch Widget Types

public enum WatchWidgetType: String, Codable, CaseIterable, Identifiable {
    case spectrogram = "Spektrogramm"
    case levelMeter = "Pegel"
    case pegelmeter = "Pegelmesser"
    case singleValue = "Wert"
    case loudness = "Lautheit"
    case empty = "Leer"

    public var id: String { rawValue }

    /// Widget types allowed on the customizable meter face (not spectrogram/graph).
    public static let meterFaceTypes: [WatchWidgetType] = [.pegelmeter, .singleValue, .loudness]

    public var icon: String {
        switch self {
        case .spectrogram: return "waveform"
        case .levelMeter: return "gauge.with.needle"
        case .pegelmeter: return "gauge.with.needle.fill"
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
    /// Per-tile refresh override for `.singleValue` widgets; `nil` uses layout default.
    public var singleValueRefreshRate: SingleValueRefreshRate?
    /// Bar orientation for `.levelMeter` tiles; `nil` uses `.default`.
    public var levelMeterOrientation: LevelMeterOrientation?

    public init(
        id: UUID = UUID(),
        type: WatchWidgetType,
        position: Int,
        singleValueType: WatchSingleValueType? = nil,
        singleValueRefreshRate: SingleValueRefreshRate? = nil,
        levelMeterOrientation: LevelMeterOrientation? = nil
    ) {
        self.id = id
        self.type = type
        self.position = position
        self.singleValueType = singleValueType
        self.singleValueRefreshRate = singleValueRefreshRate
        self.levelMeterOrientation = levelMeterOrientation
    }

    public func resolvedLevelMeterOrientation() -> LevelMeterOrientation {
        levelMeterOrientation ?? .default
    }

    public static func empty(at position: Int) -> WatchWidgetConfig {
        WatchWidgetConfig(type: .empty, position: position)
    }
}

// MARK: - Watch Dashboard Configuration

public struct WatchDashboardConfig: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case widgets
        case version
        case defaultSingleValueRefreshRate
    }

    public var widgets: [WatchWidgetConfig]
    public var version: Int
    public var defaultSingleValueRefreshRate: SingleValueRefreshRate

    public init(
        widgets: [WatchWidgetConfig] = WatchDashboardConfig.defaultWidgets,
        version: Int = 1,
        defaultSingleValueRefreshRate: SingleValueRefreshRate = .default
    ) {
        self.widgets = widgets
        self.version = version
        self.defaultSingleValueRefreshRate = defaultSingleValueRefreshRate
    }

    public func refreshRate(for widget: WatchWidgetConfig) -> SingleValueRefreshRate {
        defaultSingleValueRefreshRate.resolvedRate(perWidget: widget.singleValueRefreshRate)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        widgets = try container.decode([WatchWidgetConfig].self, forKey: .widgets)
        version = try container.decode(Int.self, forKey: .version)
        defaultSingleValueRefreshRate = try container.decodeIfPresent(
            SingleValueRefreshRate.self,
            forKey: .defaultSingleValueRefreshRate
        ) ?? .default
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(widgets, forKey: .widgets)
        try container.encode(version, forKey: .version)
        try container.encode(defaultSingleValueRefreshRate, forKey: .defaultSingleValueRefreshRate)
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
                singleValueType: widget.singleValueType,
                singleValueRefreshRate: widget.singleValueRefreshRate,
                levelMeterOrientation: widget.levelMeterOrientation
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
                singleValueType: widget.singleValueType,
                singleValueRefreshRate: widget.singleValueRefreshRate,
                levelMeterOrientation: widget.levelMeterOrientation
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
        let snapshot = config.widgets
        config.normalizeLegacyGridIfNeeded()
        config.normalizeLevelMeterOrientationIfNeeded()
        if config.widgets != snapshot {
            config.save()
        }
        return config
    }

    /// Ensures level-meter tiles have an explicit orientation (backward compatible decode).
    mutating func normalizeLevelMeterOrientationIfNeeded() {
        var changed = false
        widgets = widgets.map { widget in
            guard widget.type == .levelMeter, widget.levelMeterOrientation == nil else { return widget }
            changed = true
            return WatchWidgetConfig(
                id: widget.id,
                type: widget.type,
                position: widget.position,
                singleValueType: widget.singleValueType,
                singleValueRefreshRate: widget.singleValueRefreshRate,
                levelMeterOrientation: .default
            )
        }
        if changed { version += 1 }
    }

    func save() {
        if let data = encode() {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}

// MARK: - Customizable meter face (Pegelmesser + single values)

public struct WatchMeterLayoutConfig: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case widgets
        case version
        case defaultSingleValueRefreshRate
    }

    public var widgets: [WatchWidgetConfig]
    public var version: Int
    public var defaultSingleValueRefreshRate: SingleValueRefreshRate

    public init(
        widgets: [WatchWidgetConfig] = WatchMeterLayoutConfig.defaultWidgets,
        version: Int = 1,
        defaultSingleValueRefreshRate: SingleValueRefreshRate = .default
    ) {
        self.widgets = widgets
        self.version = version
        self.defaultSingleValueRefreshRate = defaultSingleValueRefreshRate
    }

    public func refreshRate(for widget: WatchWidgetConfig) -> SingleValueRefreshRate {
        defaultSingleValueRefreshRate.resolvedRate(perWidget: widget.singleValueRefreshRate)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        widgets = try container.decode([WatchWidgetConfig].self, forKey: .widgets)
        version = try container.decode(Int.self, forKey: .version)
        defaultSingleValueRefreshRate = try container.decodeIfPresent(
            SingleValueRefreshRate.self,
            forKey: .defaultSingleValueRefreshRate
        ) ?? .default
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(widgets, forKey: .widgets)
        try container.encode(version, forKey: .version)
        try container.encode(defaultSingleValueRefreshRate, forKey: .defaultSingleValueRefreshRate)
    }

    public static let displayColumnCount = 3

    public static var defaultWidgets: [WatchWidgetConfig] {
        [
            WatchWidgetConfig(type: .pegelmeter, position: 0),
            WatchWidgetConfig(type: .singleValue, position: 1, singleValueType: .laeq),
            WatchWidgetConfig(type: .singleValue, position: 2, singleValueType: .lafMax),
            WatchWidgetConfig(type: .singleValue, position: 3, singleValueType: .lceq),
            WatchWidgetConfig(type: .singleValue, position: 4, singleValueType: .lcfMax),
        ]
    }

    public var orderedMeterWidgets: [WatchWidgetConfig] {
        var seenKeys = Set<String>()
        return widgets
            .sorted { $0.position < $1.position }
            .filter { widget in
                guard widget.type != .empty, Self.isMeterFaceType(widget.type) else { return false }
                let key = WatchDashboardConfig.displayKey(for: widget)
                return seenKeys.insert(key).inserted
            }
    }

    public static func isMeterFaceType(_ type: WatchWidgetType) -> Bool {
        WatchWidgetType.meterFaceTypes.contains(type)
    }

    public mutating func replaceOrderedWidgets(_ displayWidgets: [WatchWidgetConfig]) {
        widgets = displayWidgets.enumerated().map { index, widget in
            WatchWidgetConfig(
                id: widget.id,
                type: widget.type,
                position: index,
                singleValueType: widget.singleValueType,
                singleValueRefreshRate: widget.singleValueRefreshRate,
                levelMeterOrientation: widget.levelMeterOrientation
            )
        }
        version += 1
    }

    public func encode() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public static func decode(from data: Data) -> WatchMeterLayoutConfig? {
        try? JSONDecoder().decode(WatchMeterLayoutConfig.self, from: data)
    }
}

public extension WatchMeterLayoutConfig {
    static let maxWidgetCount = 8
    static let userDefaultsKey = PersistenceKeys.Watch.meterLayoutConfig

    static func load() -> WatchMeterLayoutConfig {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = decode(from: data) else {
            return WatchMeterLayoutConfig()
        }
        return config
    }

    func save() {
        if let data = encode() {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}
