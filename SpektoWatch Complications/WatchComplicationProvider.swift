import WidgetKit
import Foundation

/// Shared UserDefaults suite written by WatchConnectivityManager and read here.
private let sharedDefaults = UserDefaults(suiteName: "group.BrandtAcoustics.SpektoWatch2")

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
        let level: Float? = sharedDefaults.flatMap {
            let raw = $0.double(forKey: ComplicationDefaultsKey.level)
            return raw == 0 ? nil : Float(raw)
        }
        let weighting = sharedDefaults?.string(forKey: ComplicationDefaultsKey.weighting) ?? "A"
        return WatchComplicationEntry(date: .now, level: level, weighting: weighting)
    }
}
