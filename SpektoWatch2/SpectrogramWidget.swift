import SwiftUI

struct SpectrogramWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    var settings: [String: String]

    private var useWidgetOverrides: Bool { WidgetSettings.usesWidgetOverrides(settings) }
    var colormapType: Int {
        let fallback = String(WidgetSettings.defaultSpectrogramColormap)
        guard useWidgetOverrides else {
            return WidgetSettings.defaultSpectrogramColormap
        }
        return Int(settings["colormap"] ?? fallback) ?? WidgetSettings.defaultSpectrogramColormap
    }
    var timeSpan: SpectrogramTimeSpan {
        let fallback = WidgetSettings.defaultTimeSpanSeconds
        guard useWidgetOverrides else {
            return SpectrogramTimeSpan(rawValue: fallback) ?? .seconds5
        }
        let raw = Int(settings["timeSpan"] ?? String(fallback)) ?? fallback
        return SpectrogramTimeSpan(rawValue: raw) ?? SpectrogramTimeSpan(rawValue: fallback) ?? .seconds5
    }
    var scrollSpeed: ScrollSpeed { audioEngine.scrollSpeed }
    var freqWeighting: String {
        if useWidgetOverrides {
            return settings["freqWeighting"] ?? audioEngine.frequencyWeighting.rawValue
        }
        return audioEngine.frequencyWeighting.rawValue
    }
    var sensitivity: Float {
        guard useWidgetOverrides else {
            return WidgetSettings.defaultSpectrogramSensitivity
        }
        return Float(settings["sensitivity"] ?? String(Int(WidgetSettings.defaultSpectrogramSensitivity))) ?? WidgetSettings.defaultSpectrogramSensitivity
    }

    var body: some View {
        HighEndSpectrogramAdapterWithAxes(
            audioEngine: audioEngine,
            colormapType: colormapType,
            timeSpan: timeSpan,
            scrollSpeed: scrollSpeed,
            isPaused: false,
            scrollOffset: 0.0,
            freqWeighting: freqWeighting,
            sensitivity: sensitivity,
            frequencySmoothing: audioEngine.spectrogramFrequencySmoothing
        )
        .onAppear {
            print("[SpectrogramWidget] View appeared with colormap: \(colormapType), timeSpan: \(timeSpan), sensitivity: \(sensitivity), override=\(useWidgetOverrides)")
        }
    }
}
