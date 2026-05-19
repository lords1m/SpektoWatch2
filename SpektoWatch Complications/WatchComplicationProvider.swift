import WidgetKit
import Foundation

// MARK: - App Group bridge
//
// These constants MUST match the values in `Shared/AppGroup.swift`. They are
// duplicated here because the WidgetKit complication extension target does
// not currently include `Shared/AppGroup.swift` in its compile sources.
// To eliminate the duplication, add `Shared/AppGroup.swift` to the
// "SpektoWatch Complications" target's membership in Xcode (Target → Build
// Phases → Compile Sources), then delete the constants below and import the
// shared module instead.
private enum ComplicationAppGroup {
    static let identifier = "group.BrandtAcoustics.SpektoWatch2.shared"
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    enum Keys {
        static let level = "spw.complication.level"
        static let weighting = "spw.complication.weighting"
    }
}

struct WatchComplicationProvider: TimelineProvider {

    func placeholder(in context: Context) -> WatchComplicationEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchComplicationEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchComplicationEntry>) -> Void) {
        let entry = currentEntry()
        // Rely entirely on explicit `WidgetCenter.shared.reloadTimelines`
        // calls from `Shared/WatchConnectivityManager.updateComplicationState`,
        // which already throttles to ≥ 60 s. A timer-based `.after(60)` policy
        // doubles budget consumption against the watchOS daily refresh cap
        // without adding any new information (the explicit reload fires when
        // new data actually arrives).
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func currentEntry() -> WatchComplicationEntry {
        // Read via the App Group suite shared with the watch app. Previously
        // this read from `UserDefaults.standard`, which the widget extension's
        // process never sees — the complication has been showing only the
        // placeholder value since the feature shipped.
        let defaults = ComplicationAppGroup.defaults
        let level: Float? = {
            guard defaults.object(forKey: ComplicationAppGroup.Keys.level) != nil else { return nil }
            return defaults.float(forKey: ComplicationAppGroup.Keys.level)
        }()
        let weighting = defaults.string(forKey: ComplicationAppGroup.Keys.weighting) ?? "A"
        return WatchComplicationEntry(date: .now, level: level, weighting: weighting)
    }
}
