#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity attributes for an active measurement session.
///
/// Static `attributes` (set once at `Activity.request`): the session title and
/// the start date. The start date drives the Lock Screen / Dynamic Island
/// elapsed-time label via `Text(timerInterval:)`, so elapsed time animates
/// without spending ActivityKit update budget.
///
/// Dynamic `ContentState` (pushed via `Activity.update`, throttled to ~1 Hz):
/// the live broadband level, peak, weighting label, and paused flag.
///
/// The same type is shared by the main app (which drives the lifecycle) and
/// the Live Activity widget extension (which renders the UI).
struct MeasurementActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Broadband level in calibrated dB SPL (LAF-style fast level).
        var currentLevel: Double
        /// Peak level in dB SPL (LCpeak when available).
        var peakLevel: Double
        /// Frequency weighting label: "A", "C", or "Z".
        var weighting: String
        /// True while the measurement is paused (engine not feeding data).
        var isPaused: Bool
    }

    /// User-facing session title shown on the Lock Screen.
    var sessionTitle: String
    /// Session start; used for the auto-updating elapsed-time label.
    var startedAt: Date
}
#endif
