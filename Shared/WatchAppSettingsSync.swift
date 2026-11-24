import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Phone → watch persistence and delivery for watch-app settings.
///
/// WC-5: every synced key carries a `<key>.updatedAt` timestamp (seconds
/// since 1970) in the application context. The watch keeps the timestamp of
/// the value it currently holds (local edit or last applied push) and
/// applies an incoming key only when its timestamp is not older. A missing
/// timestamp reads as 0, so pre-M22 phones still apply on a fresh watch but
/// can no longer revert a value the user changed on the watch.
public enum WatchAppSettingsSync {
    /// Keys that participate in last-writer-wins merging.
    public static let timestampedKeys: [String] = [
        PersistenceKeys.Watch.measurementSourcePreference,
        PersistenceKeys.Watch.meterLayoutConfig,
        PersistenceKeys.Watch.gain,
        PersistenceKeys.spectrogramResolution,
    ]

    public static func timestampKey(_ key: String) -> String { key + ".updatedAt" }

    /// Timestamp of the value currently held locally for `key` (0 = never).
    public static func localTimestamp(for key: String, defaults: UserDefaults = .standard) -> Double {
        defaults.double(forKey: timestampKey(key))
    }

    /// Record that the user changed `key` on this device.
    public static func markLocalChange(_ key: String, at date: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(date.timeIntervalSince1970, forKey: timestampKey(key))
    }

    /// Timestamp carried by a context for `key` (0 when absent).
    public static func incomingTimestamp(for key: String, in context: [String: Any]) -> Double {
        if let n = context[timestampKey(key)] as? NSNumber { return n.doubleValue }
        if let d = context[timestampKey(key)] as? Double { return d }
        return 0
    }

    /// Last-writer-wins check for one key of an incoming context.
    public static func shouldApply(_ key: String, from context: [String: Any], defaults: UserDefaults = .standard) -> Bool {
        guard context[key] != nil else { return false }
        return incomingTimestamp(for: key, in: context) >= localTimestamp(for: key, defaults: defaults)
    }

    /// Adds `updatedAt` stamps for keys whose value changed relative to
    /// `previous` (unchanged keys keep their previous stamp so an unrelated
    /// push never looks newer than a watch-side edit).
    /// Context values round-trip through property lists, so a `Float` may
    /// come back as `NSNumber`; compare numerically where possible.
    private static func valuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        if let l = lhs as? NSNumber, let r = rhs as? NSNumber {
            return abs(l.doubleValue - r.doubleValue) < 1e-6
        }
        if let l = lhs as? String, let r = rhs as? String { return l == r }
        return String(describing: lhs) == String(describing: rhs)
    }

    public static func stampingChangedKeys(
        _ updates: [String: Any],
        previous: [String: Any],
        now: Date = Date()
    ) -> [String: Any] {
        var result = updates
        for key in timestampedKeys {
            guard let newValue = updates[key] else { continue }
            let oldValue = previous[key]
            let unchanged = oldValue.map { valuesEqual($0, newValue) } ?? false
            if unchanged, let oldStamp = previous[timestampKey(key)] {
                result[timestampKey(key)] = oldStamp
            } else {
                result[timestampKey(key)] = now.timeIntervalSince1970
            }
        }
        return result
    }

    public static func applyMeasurementSourcePreference(_ preference: WatchMeasurementSourcePreference) {
        UserDefaults.standard.set(preference.rawValue, forKey: PersistenceKeys.Watch.measurementSourcePreference)
        UserDefaults.standard.set(preference == .appleWatch, forKey: PersistenceKeys.Watch.standaloneEnabled)
        NotificationCenter.default.post(
            name: .watchMeasurementSourcePreferenceChanged,
            object: preference
        )
    }

    public static func applyMeterLayoutConfig(_ config: WatchMeterLayoutConfig) {
        config.save()
        NotificationCenter.default.post(
            name: .watchMeterLayoutConfigChanged,
            object: config
        )
    }

    public static func applyWatchGain(_ gain: Float) {
        UserDefaults.standard.set(gain, forKey: PersistenceKeys.Watch.gain)
        NotificationCenter.default.post(
            name: .gainOrBandwidthChangedNotification,
            object: gain
        )
    }

    public static func applySpectrogramResolution(_ resolution: SpectrogramResolution) {
        UserDefaults.standard.set(resolution.rawValue, forKey: PersistenceKeys.spectrogramResolution)
        NotificationCenter.default.post(
            name: .spectrogramResolutionChanged,
            object: resolution
        )
    }

    #if canImport(WatchConnectivity)
    /// Merges watch settings into `applicationContext` for background delivery.
    public static func mergedApplicationContext(
        meterLayout: WatchMeterLayoutConfig? = nil,
        measurementSource: WatchMeasurementSourcePreference? = nil,
        gain: Float? = nil,
        spectrogramResolution: SpectrogramResolution? = nil
    ) -> [String: Any] {
        var context = WCSession.default.receivedApplicationContext
        if let meterLayout,
           let data = meterLayout.encode(),
           let string = String(data: data, encoding: .utf8) {
            context[PersistenceKeys.Watch.meterLayoutConfig] = string
        }
        if let measurementSource {
            context[PersistenceKeys.Watch.measurementSourcePreference] = measurementSource.rawValue
        }
        if let gain {
            context[PersistenceKeys.Watch.gain] = gain
        }
        if let spectrogramResolution {
            context[PersistenceKeys.spectrogramResolution] = spectrogramResolution.rawValue
        }
        return context
    }

    public static func applyApplicationContext(_ context: [String: Any], defaults: UserDefaults = .standard) {
        func adopt(_ key: String) {
            defaults.set(incomingTimestamp(for: key, in: context), forKey: timestampKey(key))
        }
        let sourceKey = PersistenceKeys.Watch.measurementSourcePreference
        if shouldApply(sourceKey, from: context, defaults: defaults),
           let raw = context[sourceKey] as? String,
           let preference = WatchMeasurementSourcePreference(rawValue: raw) {
            applyMeasurementSourcePreference(preference)
            adopt(sourceKey)
        }
        let layoutKey = PersistenceKeys.Watch.meterLayoutConfig
        if shouldApply(layoutKey, from: context, defaults: defaults),
           let configString = context[layoutKey] as? String,
           let data = configString.data(using: .utf8),
           let config = WatchMeterLayoutConfig.decode(from: data) {
            applyMeterLayoutConfig(config)
            adopt(layoutKey)
        }
        let gainKey = PersistenceKeys.Watch.gain
        if shouldApply(gainKey, from: context, defaults: defaults) {
            if let gainNumber = context[gainKey] as? NSNumber {
                applyWatchGain(gainNumber.floatValue)
                adopt(gainKey)
            } else if let gain = context[gainKey] as? Float {
                applyWatchGain(gain)
                adopt(gainKey)
            }
        }
        let resolutionKey = PersistenceKeys.spectrogramResolution
        if shouldApply(resolutionKey, from: context, defaults: defaults),
           let raw = context[resolutionKey] as? String,
           let resolution = SpectrogramResolution(rawValue: raw) {
            applySpectrogramResolution(resolution)
            adopt(resolutionKey)
        }
    }
    #endif
}
