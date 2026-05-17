import WidgetKit
import Foundation

enum ComplicationDefaultsKey {
    static let level = "spw.complication.level"
    static let weighting = "spw.complication.weighting"
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
        // Expire after 60 s; WatchConnectivityManager triggers explicit reloads on live data.
        let expiry = Date.now.addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(expiry)))
    }

    private func currentEntry() -> WatchComplicationEntry {
        let defaults = UserDefaults.standard
        let level: Float? = {
            guard defaults.object(forKey: ComplicationDefaultsKey.level) != nil else { return nil }
            return defaults.float(forKey: ComplicationDefaultsKey.level)
        }()
        let weighting = defaults.string(forKey: ComplicationDefaultsKey.weighting) ?? "A"
        return WatchComplicationEntry(date: .now, level: level, weighting: weighting)
    }
}
