import WidgetKit
import Foundation

struct WatchComplicationEntry: TimelineEntry {
    let date: Date
    /// Current sound level in dBSPL. Nil when no live data is available.
    let level: Float?
    /// Frequency weighting label shown alongside the value (e.g. "A", "Z").
    let weighting: String

    static let placeholder = WatchComplicationEntry(date: .now, level: nil, weighting: "A")

    var levelText: String {
        guard let level else { return "–" }
        return String(format: "%.0f", level)
    }

    var labelText: String { "dB\(weighting)" }

    /// 0…1 progress value for gauge/progress views, clamped to 0–120 dBSPL.
    var gaugeValue: Double {
        guard let level else { return 0 }
        return Double(max(0, min(120, level)) / 120)
    }
}
