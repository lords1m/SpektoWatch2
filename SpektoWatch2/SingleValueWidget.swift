import SwiftUI

struct SingleValueWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.designNumerals) private var numerals
    var settings: [String: String]
    private var useWidgetOverrides: Bool { WidgetSettings.usesWidgetOverrides(settings) }
    var metricKey: String {
        if useWidgetOverrides {
            return settings["metric"] ?? WidgetSettings.defaultSingleValueMetric
        }
        return WidgetSettings.defaultSingleValueMetric
    }
    
    var displayTitle: AttributedString {
        var result = AttributedString()
        
        switch metricKey {
        case "LAF":
            result = "L"
            result += AttributedString("A,F", attributes: AttributeContainer([.baselineOffset: -3, .font: Font.caption.weight(.regular)]))
        case "LAeq":
            result = "L"
            result += AttributedString("A,eq", attributes: AttributeContainer([.baselineOffset: -3, .font: Font.caption.weight(.regular)]))
        case "LAFmin":
            result = "L"
            result += AttributedString("A,F,min", attributes: AttributeContainer([.baselineOffset: -3, .font: Font.caption.weight(.regular)]))
        case "LAFmax":
            result = "L"
            result += AttributedString("A,F,max", attributes: AttributeContainer([.baselineOffset: -3, .font: Font.caption.weight(.regular)]))
        case "LAF5":
            result = "L"
            result += AttributedString("A,F,5", attributes: AttributeContainer([.baselineOffset: -3, .font: Font.caption.weight(.regular)]))
        case "LAF95":
            result = "L"
            result += AttributedString("A,F,95", attributes: AttributeContainer([.baselineOffset: -3, .font: Font.caption.weight(.regular)]))
        case "LAFT5":
            result = "L"
            result += AttributedString("A,FT,5", attributes: AttributeContainer([.baselineOffset: -3, .font: Font.caption.weight(.regular)]))
        case "LAFTeq":
            result = "L"
            result += AttributedString("A,FT,eq", attributes: AttributeContainer([.baselineOffset: -3, .font: Font.caption.weight(.regular)]))
        case "LCpeak":
            result = "L"
            result += AttributedString("C,peak", attributes: AttributeContainer([.baselineOffset: -3, .font: Font.caption.weight(.regular)]))
        case "PHON":
            result = "Lautheit"
        case "SONE":
            result = "Wahrg. Lautheit"
        default:
            result = AttributedString(metricKey)
        }
        
        return result
    }

    var unitLabel: String {
        switch metricKey {
        case "PHON": return "Phon"
        case "SONE": return "Sone"
        default:
            if metricKey.hasPrefix("LA") { return "dB(A)" }
            if metricKey.hasPrefix("LC") { return "dB(C)" }
            if metricKey.hasPrefix("LZ") { return "dB(Z)" }
            return "dB"
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
        // Frameless layout: rely on the card's own header for the widget
        // name + dB(A) meta pill, so the kernel surfaces only the value
        // and its unit. No internal title row, no surrounding padding —
        // numerals fill the kernel area edge-to-edge and animate with
        // SwiftUI's numericText content transition.
        VStack(spacing: 0) {
            Text(displayValue)
                .font(.numerals(numerals, size: 36, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(audioEngine.engineStatus == .running ? .primary : .gray)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(value ?? 0)))
                .animation(.easeOut(duration: 0.2), value: value)

            Text(unitLabel)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(audioEngine.live.$currentSpectrogramData) { data in
            guard let data = data else {
                self.value = nil
                return
            }
            // PHON and SONE are now populated by AcousticMetricsCalculator,
            // so all metrics including loudness use the same levels dict path.
            let raw = data.levels[metricKey] ?? 0.0
            let floor = WidgetSettings.noiseFloorDB(settings)
            // Suppress display when the signal is at or below the noise floor.
            self.value = (floor > -119 && raw <= floor) ? nil : raw
        }
        .onReceive(audioEngine.$engineStatus) { status in
            if status != .running {
                self.value = nil
            }
        }
    }
}
