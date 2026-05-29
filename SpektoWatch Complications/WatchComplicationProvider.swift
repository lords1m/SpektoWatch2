import WidgetKit
import Foundation

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
        let defaults = AppGroup.defaults
        let level: Float? = {
            guard defaults.object(forKey: ComplicationSharedKeys.level) != nil else { return nil }
            return defaults.float(forKey: ComplicationSharedKeys.level)
        }()
        let weighting = defaults.string(forKey: ComplicationSharedKeys.weighting) ?? "A"
        return WatchComplicationEntry(date: .now, level: level, weighting: weighting)
    }
}
