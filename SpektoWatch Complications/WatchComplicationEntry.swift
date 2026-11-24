import WidgetKit
import Foundation

struct WatchComplicationEntry: TimelineEntry {
    let date: Date
    /// Current sound level in dBSPL. Nil when no live data is available.
    let level: Float?
    /// Frequency weighting label shown alongside the value (e.g. "A", "Z").
    let weighting: String
    /// WL-3: when `level` was written (nil = unknown / never).
    var updatedAt: Date? = nil

    static let placeholder = WatchComplicationEntry(date: .now, level: nil, weighting: "A")

    /// `true` when the stored value is older than
    /// `ComplicationSharedKeys.staleAfter` at this entry's date.
    var isStale: Bool {
        guard let updatedAt else { return true }
        return date.timeIntervalSince(updatedAt) > ComplicationSharedKeys.staleAfter
    }

    /// Level to display: `nil` once stale so views render "–".
    var displayLevel: Float? { isStale ? nil : level }

    /// Eyebrow suffix: "LIVE" only for fresh values.
    var freshnessLabel: String { isStale ? "—" : "LIVE" }

    var levelText: String {
        guard let level = displayLevel else { return "–" }
        return String(format: "%.0f", level)
    }

    var labelText: String { "dB\(weighting)" }

    /// 0…1 progress value for gauge/progress views, clamped to 0–120 dBSPL.
    var gaugeValue: Double {
        guard let level = displayLevel else { return 0 }
        return Double(max(0, min(120, level)) / 120)
    }
}
