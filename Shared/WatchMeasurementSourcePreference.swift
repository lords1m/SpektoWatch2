import Foundation

/// User-chosen policy for which device supplies live levels on the watch UI.
public enum WatchMeasurementSourcePreference: String, Codable, CaseIterable, Sendable {
    /// Prefer the iPhone while it is measuring and reachable; otherwise the watch mic.
    case auto
    /// Always mirror live metrics from the paired iPhone (companion mode).
    case iPhone
    /// Always use the Apple Watch microphone (standalone / watch-first).
    case appleWatch

    public var displayName: String {
        switch self {
        case .auto: return "Automatisch"
        case .iPhone: return "iPhone"
        case .appleWatch: return "Apple Watch"
        }
    }

    public var systemImageName: String {
        switch self {
        case .auto: return "arrow.triangle.2.circlepath"
        case .iPhone: return "iphone"
        case .appleWatch: return "applewatch"
        }
    }
}

/// Resolved live source shown in the watch UI indicator.
public enum WatchActiveMeasurementSource: String, Sendable, Equatable {
    case iPhoneMirror
    case watchMic
    case idle

    public var displayName: String {
        switch self {
        case .iPhoneMirror: return "iPhone"
        case .watchMic: return "Watch"
        case .idle: return "—"
        }
    }

    public var systemImageName: String {
        switch self {
        case .iPhoneMirror: return "iphone"
        case .watchMic: return "applewatch"
        case .idle: return "mic.slash"
        }
    }
}
