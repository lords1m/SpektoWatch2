import Foundation

/// User-facing spectrogram quality preset (frequency detail + watch canvas density).
public enum SpectrogramResolution: String, CaseIterable, Identifiable, Sendable {
    case standard
    case balanced
    case high

    public var id: String { rawValue }

    public var germanTitle: String {
        switch self {
        case .standard: return "Niedrig"
        case .balanced: return "Mittel"
        case .high: return "Hoch"
        }
    }

    public var germanDetail: String {
        switch self {
        case .standard:
            return "Weniger Speicher, weichere Darstellung"
        case .balanced:
            return "Ausgewogen — weniger Speicher"
        case .high:
            return "Empfohlen — maximale Frequenzauflösung"
        }
    }

    /// Vertical Metal texture rows (iPhone live spectrogram).
    public var textureFrequencyBins: Int {
        switch self {
        case .standard: return 768
        case .balanced: return 1024
        case .high: return 1536
        }
    }

    /// Mel bands in the DCT visual pipeline (iPhone).
    public var melBandCount: Int {
        switch self {
        case .standard: return 96
        case .balanced: return 128
        case .high: return 192
        }
    }

    /// Watch mic downsample target and Canvas row count.
    public var watchDisplayBinCount: Int {
        switch self {
        case .standard: return 40
        case .balanced: return 64
        case .high: return 80
        }
    }

    /// Ring-buffer columns retained in the watch spectrogram view.
    public var watchHistoryFrameCount: Int {
        switch self {
        case .standard: return 60
        case .balanced: return 80
        case .high: return 100
        }
    }

    public static let defaultValue: SpectrogramResolution = .high

    public static var current: SpectrogramResolution {
        let raw = UserDefaults.standard.string(forKey: PersistenceKeys.spectrogramResolution)
        return SpectrogramResolution(rawValue: raw ?? "") ?? .defaultValue
    }

    public static func save(_ resolution: SpectrogramResolution) {
        guard resolution != current else { return }
        UserDefaults.standard.set(resolution.rawValue, forKey: PersistenceKeys.spectrogramResolution)
        NotificationCenter.default.post(
            name: .spectrogramResolutionChanged,
            object: resolution
        )
    }
}
