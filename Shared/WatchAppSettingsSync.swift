import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Phone → watch persistence and delivery for watch-app settings.
public enum WatchAppSettingsSync {
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

    public static func applyApplicationContext(_ context: [String: Any]) {
        if let raw = context[PersistenceKeys.Watch.measurementSourcePreference] as? String,
           let preference = WatchMeasurementSourcePreference(rawValue: raw) {
            applyMeasurementSourcePreference(preference)
        }
        if let configString = context[PersistenceKeys.Watch.meterLayoutConfig] as? String,
           let data = configString.data(using: .utf8),
           let config = WatchMeterLayoutConfig.decode(from: data) {
            applyMeterLayoutConfig(config)
        }
        if let gainNumber = context[PersistenceKeys.Watch.gain] as? NSNumber {
            applyWatchGain(gainNumber.floatValue)
        } else if let gain = context[PersistenceKeys.Watch.gain] as? Float {
            applyWatchGain(gain)
        }
        if let raw = context[PersistenceKeys.spectrogramResolution] as? String,
           let resolution = SpectrogramResolution(rawValue: raw) {
            applySpectrogramResolution(resolution)
        }
    }
    #endif
}
