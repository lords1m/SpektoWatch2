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
        // Rely on explicit `WidgetCenter.shared.reloadTimelines` calls from
        // `ComplicationFeed.publish` (throttled to ≥ 60 s). WL-3: a second,
        // pre-computed entry at `updatedAt + staleAfter` flips the face to
        // "–" when no new data arrives, without spending refresh budget.
        var entries = [entry]
        if let updatedAt = entry.updatedAt, !entry.isStale {
            let staleDate = updatedAt.addingTimeInterval(ComplicationSharedKeys.staleAfter + 1)
            entries.append(WatchComplicationEntry(
                date: staleDate, level: entry.level, weighting: entry.weighting, updatedAt: updatedAt))
        }
        completion(Timeline(entries: entries, policy: .never))
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
        let stamp = defaults.double(forKey: ComplicationSharedKeys.updatedAt)
        let updatedAt: Date? = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        return WatchComplicationEntry(date: .now, level: level, weighting: weighting, updatedAt: updatedAt)
    }
}
