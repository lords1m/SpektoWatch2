import SwiftUI

struct SingleValueWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    var settings: [String: String]
    @StateObject private var loudnessCalculator = LoudnessCalculator()
    
    private var useWidgetOverrides: Bool { WidgetSettings.usesWidgetOverrides(settings) }
    var metricKey: String {
        if useWidgetOverrides {
            return settings["metric"] ?? WidgetSettings.defaultSingleValueMetric
        }
        return WidgetSettings.defaultSingleValueMetric
    }
    
    var displayTitle: String {
        switch metricKey {
        case "LAF": return "LAF (Aktuell)"
        case "LAeq": return "LAeq (Mittel)"
        case "LAFmin": return "LAFmin (Min)"
        case "LAFmax": return "LAFmax (Max)"
        case "LAF5": return "LAF5 (5%)"
        case "LAF95": return "LAF95 (95%)"
        case "LAFT5": return "LAFT5 (Takt)"
        case "LAFTeq": return "LAFTeq (Takt Mittel)"
        case "LCpeak": return "LCpeak (Spitze)"
        case "PHON": return "Lautheit"
        case "SONE": return "Wahrg. Lautheit"
        default: return metricKey
        }
    }

    var unitLabel: String {
        switch metricKey {
        case "PHON": return "Phon"
        case "SONE": return "Sone"
        default: return "dB"
        }
    }
    
    @State private var value: Float? = nil

    private var displayValue: String {
        guard let v = value, audioEngine.engineStatus == .running else {
            return "0.0"
        }
        if metricKey == "SONE" {
            return String(format: "%.2f", v)
        }
        return String(format: "%.1f", v)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(displayTitle)
                .font(.caption)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            Spacer()

            Text(displayValue)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(audioEngine.engineStatus == .running ? .primary : .gray)
                .minimumScaleFactor(0.5)

            Text(unitLabel)
                .font(.headline)
                .foregroundColor(.gray)

            Spacer()
        }
        .onReceive(audioEngine.$currentSpectrogramData) { data in
            guard let data = data else {
                self.value = nil
                return
            }
            if metricKey == "PHON" || metricKey == "SONE" {
                updateLoudnessValue(from: data)
            } else {
                self.value = data.levels[metricKey] ?? 0.0
            }
        }
        .onReceive(audioEngine.$engineStatus) { status in
            if status != .running {
                self.value = nil
            }
        }
    }

    private func updateLoudnessValue(from data: SpectrogramData) {
        guard !data.frequencies.isEmpty, !data.magnitudes.isEmpty else {
            value = nil
            return
        }

        let safeCount = min(data.frequencies.count, data.magnitudes.count)
        guard safeCount > 0 else {
            value = nil
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
            value = nil
            return
        }

        if metricKey == "PHON" {
            value = Float(result.phon)
        } else {
            value = Float(result.sone)
        }
    }
}
