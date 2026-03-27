import SwiftUI

struct LevelHistoryWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    var settings: [String: String]
    @StateObject private var loudnessCalculator = LoudnessCalculator()
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
    
    var metricLabel: String {
        "L\(resolvedFrequencyWeighting)\(resolvedTimeWeighting.prefix(1))"
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
        .onReceive(audioEngine.$currentSpectrogramData) { data in
            guard let data = data else {
                phonValue = nil
                soneValue = nil
                return
            }
            updateLoudness(from: data)
        }
    }

    private func updateLoudness(from data: SpectrogramData) {
        guard !data.frequencies.isEmpty, !data.magnitudes.isEmpty else {
            phonValue = nil
            soneValue = nil
            return
        }

        let safeCount = min(data.frequencies.count, data.magnitudes.count)
        guard safeCount > 0 else {
            phonValue = nil
            soneValue = nil
            return
        }

        var dominantIndex = 0
        var dominantMagnitude = data.magnitudes[0]
        for i in 1..<safeCount {
            if data.magnitudes[i] > dominantMagnitude {
                dominantMagnitude = data.magnitudes[i]
                dominantIndex = i
            }
        }

        let dominantFrequency = max(20.0, min(12500.0, Double(data.frequencies[dominantIndex])))
        let spl = Double(data.levels["LAF"] ?? data.broadbandLevel)
        loudnessCalculator.calculate(spl: spl, frequency: dominantFrequency)

        guard let result = loudnessCalculator.result else {
            phonValue = nil
            soneValue = nil
            return
        }

        phonValue = result.phon
        soneValue = result.sone
    }
}
