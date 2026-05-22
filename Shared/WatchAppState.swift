import Foundation

/// Cross-target envelope for non-audio app state shared from the iOS
/// app to the paired watch.
///
/// Added in M13 task-7 to unblock watch faces 4a/4b/4c from
/// hardcoding the phosphor accent: today they ship a baked-in
/// `Color(red: 0.45, green: 0.93, blue: 0.55)` because there is no
/// way to propagate the iOS `AccentChoice` across WatchConnectivity.
/// This envelope is the carrier for accent + theme + active preset +
/// recording state + (eventually) tone-generator state.
///
/// Wire format: `Codable` JSON inside a `WatchConnectivity` message
/// keyed by `WatchConnectivityProtocol.MessageType.appStateUpdate`.
/// JSON is preferred over the binary path because the payload is
/// small and infrequent (≥ 0.2 s coalescing), and the readability
/// helps when debugging on hardware.
public struct WatchAppState: Codable, Equatable {

    /// Active dashboard preset id (matches `DashboardPreset.id` from
    /// `PresetCatalogue`). Nil if no preset is selected.
    public let activePresetID: String?

    /// True when an iOS-side recording session is in progress.
    public let isRecording: Bool

    /// Active accent choice (matches `AccentChoice.rawValue`).
    /// e.g. "phosphor", "amber", "cyan", "magenta", "paper".
    public let designAccent: String

    /// Active theme mode (matches `ThemeMode.rawValue`).
    /// e.g. "dark", "light".
    public let theme: String

    /// Optional tone-generator state. Nil when the tone generator is
    /// not active. Reserved for future use — the iOS tone widget
    /// owns local state today and isn't wired to the envelope yet.
    public let toneGenerator: ToneState?

    /// Schema version. Increment on any field-shape change so the
    /// receiver can reject mismatched envelopes cleanly.
    public let schemaVersion: UInt8

    public static let currentSchemaVersion: UInt8 = 0x01

    public init(
        activePresetID: String?,
        isRecording: Bool,
        designAccent: String,
        theme: String,
        toneGenerator: ToneState? = nil,
        schemaVersion: UInt8 = WatchAppState.currentSchemaVersion
    ) {
        self.activePresetID = activePresetID
        self.isRecording = isRecording
        self.designAccent = designAccent
        self.theme = theme
        self.toneGenerator = toneGenerator
        self.schemaVersion = schemaVersion
    }

    public struct ToneState: Codable, Equatable {
        public let frequencyHz: Double
        public let amplitude: Float
        public let waveform: String   // matches a future Waveform enum rawValue
        public let isPlaying: Bool

        public init(frequencyHz: Double, amplitude: Float, waveform: String, isPlaying: Bool) {
            self.frequencyHz = frequencyHz
            self.amplitude = amplitude
            self.waveform = waveform
            self.isPlaying = isPlaying
        }
    }
}

// MARK: - JSON envelope helpers

extension WatchAppState {
    /// Encode for transport over WatchConnectivity. JSON is small
    /// here (≤ 200 bytes typical) and keeps the wire format
    /// inspectable.
    public func encode() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Decode an envelope received over WatchConnectivity. Returns
    /// nil for an unknown schema version (receiver should log and
    /// keep running with its previous state).
    public static func decode(_ data: Data) -> WatchAppState? {
        guard let envelope = try? JSONDecoder().decode(WatchAppState.self, from: data) else {
            return nil
        }
        guard envelope.schemaVersion == currentSchemaVersion else {
            return nil
        }
        return envelope
    }
}
