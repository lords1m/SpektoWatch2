import SwiftUI

struct LevelHistoryWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    var settings: [String: String]
    @State private var phonValue: Double?
    @State private var soneValue: Double?

    private var useWidgetOverrides: Bool { WidgetSettings.usesWidgetOverrides(settings) }
    private var resolvedFrequencyWeighting: String {
        if useWidgetOverrides {
            return settings["freqWeighting"] ?? audioEngine.frequencyWeighting.rawValue
        }
        return audioEngine.frequencyWeighting.rawValue
    }
    private var resolvedTimeWeighting: String {
        if useWidgetOverrides {
            return settings["timeWeighting"] ?? audioEngine.timeWeighting.rawValue
        }
        return audioEngine.timeWeighting.rawValue
    }
    private var selectedHistoryMetric: String {
        if useWidgetOverrides {
            return settings["historyMetric"] ?? WidgetSettings.defaultLevelHistoryMetric
        }
        return WidgetSettings.defaultLevelHistoryMetric
    }
    private var resolvedMetricKey: String {
        if selectedHistoryMetric == WidgetSettings.defaultLevelHistoryMetric {
            return "L\(resolvedFrequencyWeighting)\(resolvedTimeWeighting.prefix(1))"
        }
        return selectedHistoryMetric
    }
    
    var metricLabel: String {
        resolvedMetricKey
    }
    
    var body: some View {
        LevelHistoryView(
            audioEngine: audioEngine,
            settings: settings,
            scrollSpeed: .fast,
            isPaused: false,
            scrollOffset: 0.0
        )
        .cornerRadius(10)
        .overlay(alignment: .topLeading) {
            Text(metricLabel)
                .font(.caption)
                .foregroundColor(.white)
                .padding(4)
                .background(Color.black.opacity(0.5))
                .cornerRadius(4)
                .padding(4)
        }
        .overlay(alignment: .topTrailing) {
            if let phon = phonValue, let sone = soneValue {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f phon", phon))
                    Text(String(format: "%.2f sone", sone))
                }
                .font(.caption2)
                .foregroundColor(.white)
                .padding(4)
                .background(Color.black.opacity(0.5))
                .cornerRadius(4)
                .padding(4)
            }
        }
        .onReceive(audioEngine.live.$currentSpectrogramData) { data in
            guard let data = data else {
                phonValue = nil
                soneValue = nil
                return
            }
            updateLoudness(from: data)
        }
    }

    private func updateLoudness(from data: SpectrogramData) {
        if let p = data.levels["PHON"], let s = data.levels["SONE"] {
            phonValue = Double(p)
            soneValue = Double(s)
        } else {
            phonValue = nil
            soneValue = nil
        }
    }
}
