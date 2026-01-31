import SwiftUI

struct SingleValueWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    var settings: [String: String]
    
    var metricKey: String { settings["metric"] ?? "LAF" }
    
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
        default: return metricKey
        }
    }
    
    @State private var value: Float? = nil

    private var displayValue: String {
        guard let v = value, audioEngine.engineStatus == .running else {
            return "0.0"
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

            Text("dB")
                .font(.headline)
                .foregroundColor(.gray)

            Spacer()
        }
        .onReceive(audioEngine.$currentSpectrogramData) { data in
            guard let data = data else {
                self.value = nil
                return
            }
            self.value = data.levels[metricKey] ?? 0.0
        }
        .onReceive(audioEngine.$engineStatus) { status in
            if status != .running {
                self.value = nil
            }
        }
    }
}