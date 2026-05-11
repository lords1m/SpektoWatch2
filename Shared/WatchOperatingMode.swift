import Foundation

/// The role the watch is currently playing.
///
/// SpektoWatch can act as one of three things, and the rest of the watch UI
/// should branch on this single value rather than on `audioEngine.isRecording`
/// + `connectivityManager.spectrogramData != nil` heuristics.
///
/// Defined in `Shared/` so both phone and watch agree on the vocabulary.
public enum WatchOperatingMode: String, Codable, Sendable, Equatable {
    /// Phone is recording. The watch is a remote display: it shows whatever the
    /// phone pushes via `WatchConnectivityManager.spectrogramData`. The watch
    /// mic is idle.
    case companion

    /// Watch is recording with its own mic. It computes a local FFT for
    /// immediate display, *and* (Phase 4+) streams processed metrics to the
    /// phone where they are merged as a secondary track.
    case wearableMic

    /// Watch is recording with its own mic, storing locally to a `.swr` file.
    /// Phone connectivity is optional; recordings sync on the next reachability.
    /// (Implemented in Phase 4 — Phase 1 keeps this for protocol compatibility.)
    case standalone

    /// User-facing short label, e.g. for a status pill.
    public var displayName: String {
        switch self {
        case .companion:    return "Companion"
        case .wearableMic:  return "Wearable Mic"
        case .standalone:   return "Standalone"
        }
    }

    /// Whether the watch's local microphone is the source of truth in this mode.
    public var watchMicIsActive: Bool {
        switch self {
        case .companion:                         return false
        case .wearableMic, .standalone:          return true
        }
    }
}
