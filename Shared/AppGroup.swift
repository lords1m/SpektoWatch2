import Foundation

/// Single source of truth for the App Group used to share state between the
/// watch app (`SpektoWatch Watch App`) and the WidgetKit complication
/// extension (`SpektoWatch Complications`).
///
/// Widget extensions run in a separate process from their host app, so
/// `UserDefaults.standard` is NOT shared between the two — each process has
/// its own. The complication previously read from `UserDefaults.standard`
/// while the watch app wrote to it, meaning the complication has effectively
/// always shown the placeholder value. Routing both sides through
/// `UserDefaults(suiteName: AppGroup.identifier)` fixes that.
///
/// ⚠️ **The App Group must also be enabled in the Apple Developer Portal
/// and added to both targets' entitlements**. The matching `.entitlements`
/// files live alongside this constant. Until the Xcode build setting
/// `CODE_SIGN_ENTITLEMENTS` is wired for both targets and the App Group is
/// registered in the provisioning profile, `UserDefaults(suiteName:)` will
/// return `nil` and the code falls back to `UserDefaults.standard` (i.e. the
/// pre-fix behavior).
public enum AppGroup {
    public static let identifier = "group.BrandtAcoustics.SpektoWatch2.shared"

    /// Shared defaults backed by the App Group suite. Falls back to
    /// `UserDefaults.standard` so the app does not crash if the entitlement
    /// isn't yet wired in the build settings.
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

/// Centralized keys used to communicate live measurement state from the watch
/// app to the complication extension via the shared App Group defaults.
public enum ComplicationSharedKeys {
    public static let level = "spw.complication.level"
    public static let weighting = "spw.complication.weighting"
    /// WL-3: `timeIntervalSince1970` of the last level write. Lets the
    /// complication show "–" instead of a frozen value once data goes stale.
    public static let updatedAt = "spw.complication.updatedAt"
    /// A value older than this is shown as stale.
    public static let staleAfter: TimeInterval = 5 * 60
}

#if os(watchOS) && canImport(WidgetKit)
import WidgetKit

/// WL-3: single writer API for the complication feed, used by the watch's own
/// engine (primary — works watch-only) and by the phone stream mirror
/// (secondary). Reloads are throttled to protect the daily WidgetKit budget.
public enum ComplicationFeed {
    public static let widgetKinds = [
        "SpektoWatchLevelCircular",
        "SpektoWatchLevelRectangular",
        "SpektoWatchLevelInline",
        "SpektoWatchLevelCorner"
    ]
    public static let minimumReloadInterval: TimeInterval = 60

    private static let lock = NSLock()
    private static var lastReload = Date.distantPast

    /// Stores the level and reloads timelines at most once per
    /// `minimumReloadInterval` unless `force` (e.g. recording stopped).
    public static func publish(level: Float, weighting: String, force: Bool = false, now: Date = Date()) {
        guard level.isFinite else { return }
        lock.lock()
        let due = force || now.timeIntervalSince(lastReload) >= minimumReloadInterval
        if due { lastReload = now }
        lock.unlock()
        guard due else { return }

        let shared = AppGroup.defaults
        shared.set(level, forKey: ComplicationSharedKeys.level)
        shared.set(weighting, forKey: ComplicationSharedKeys.weighting)
        shared.set(now.timeIntervalSince1970, forKey: ComplicationSharedKeys.updatedAt)
        widgetKinds.forEach { WidgetCenter.shared.reloadTimelines(ofKind: $0) }
    }
}
#endif
