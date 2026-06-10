import Foundation

enum WaterfallSpectrumMode: String, CaseIterable, Equatable {
    case continuous
    case thirdOctave
    case bark
    case octave

    var title: String {
        switch self {
        case .continuous: return "Linie"
        case .thirdOctave: return "Terz"
        case .bark: return "Bark"
        case .octave: return "Oktav"
        }
    }
}

/// Shared waterfall display parameters for the live widget and recording playback.
struct WaterfallDisplaySettings: Equatable {
    var sliceCount: Int
    var minDB: Float
    var maxDB: Float
    var targetFrequencyCount: Int
    var spectrumMode: WaterfallSpectrumMode
    /// Render-only: show amplitude-coloured peak dots / the peak readout panel.
    var showPeaks: Bool = false
    /// Render-only: overlay max-hold + average spectra in the oblique mode.
    var showStatistics: Bool = false

    static let liveDefault = WaterfallDisplaySettings(
        sliceCount: WidgetSettings.defaultWaterfallSliceCount,
        minDB: WidgetSettings.defaultWaterfallMinDB,
        maxDB: WidgetSettings.defaultWaterfallMaxDB,
        targetFrequencyCount: WidgetSettings.defaultWaterfallTargetFrequencyCount,
        spectrumMode: .continuous,
        showPeaks: false,
        showStatistics: false
    )

    /// Stored `.spekto` spectra are dB SPL — same display band as the live dashboard.
    static let playbackDefault = liveDefault

    func clampedDBRange() -> (minDB: Float, maxDB: Float) {
        let lo = minDB
        let hi = maxDB
        return (min(lo, hi - 5), max(hi, lo + 5))
    }

    func historyStoreSettings(capacity: Int, rebuildInterval: TimeInterval = 0.12) -> WaterfallHistoryStore.Settings {
        let range = clampedDBRange()
        return WaterfallHistoryStore.Settings(
            capacity: capacity,
            sliceCount: sliceCount,
            minDB: range.minDB,
            maxDB: range.maxDB,
            rebuildInterval: rebuildInterval,
            targetFrequencyCount: targetFrequencyCount
        )
    }

    static func fromWidgetSettings(_ settings: [String: String], engineWeighting: String) -> WaterfallDisplaySettings {
        let useOverrides = WidgetSettings.usesWidgetOverrides(settings)
        let sliceCount: Int = {
            guard useOverrides else { return WidgetSettings.defaultWaterfallSliceCount }
            return Int(settings["waterfallSlices"] ?? "") ?? WidgetSettings.defaultWaterfallSliceCount
        }()
        let minDB: Float = {
            guard useOverrides else { return WidgetSettings.defaultWaterfallMinDB }
            let raw = Float(settings["waterfallMinDB"] ?? "") ?? WidgetSettings.defaultWaterfallMinDB
            return raw < 0 ? WidgetSettings.defaultWaterfallMinDB : raw
        }()
        let maxDB: Float = {
            guard useOverrides else { return WidgetSettings.defaultWaterfallMaxDB }
            let raw = Float(settings["waterfallMaxDB"] ?? "") ?? WidgetSettings.defaultWaterfallMaxDB
            return raw <= 0 ? WidgetSettings.defaultWaterfallMaxDB : raw
        }()
        let spectrumMode = WaterfallSpectrumMode(
            rawValue: settings["waterfallSpectrumMode"] ?? WidgetSettings.defaultWaterfallSpectrumMode
        ) ?? .continuous
        let showPeaks: Bool = {
            guard useOverrides else { return WidgetSettings.defaultWaterfallShowPeaks }
            return (settings["waterfallShowPeaks"] ?? (WidgetSettings.defaultWaterfallShowPeaks ? "true" : "false")) == "true"
        }()
        _ = engineWeighting
        return WaterfallDisplaySettings(
            sliceCount: sliceCount,
            minDB: minDB,
            maxDB: maxDB,
            targetFrequencyCount: WidgetSettings.defaultWaterfallTargetFrequencyCount,
            spectrumMode: spectrumMode,
            showPeaks: showPeaks,
            showStatistics: false
        )
    }
}
