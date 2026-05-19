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
}
