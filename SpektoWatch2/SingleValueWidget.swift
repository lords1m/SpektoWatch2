import SwiftUI
import Combine

struct SingleValueWidget: View {
    @ObservedObject private var live: LiveAcousticState
    @Environment(\.designNumerals) private var numerals
    private let engineStatusPublisher: Published<EngineStatus>.Publisher
    var settings: [String: String]

    init(audioEngine: AudioEngine, settings: [String: String]) {
        _live = ObservedObject(initialValue: audioEngine.live)
        self.engineStatusPublisher = audioEngine.$engineStatus
        self.settings = settings
    }
    var metricKey: String {
        // Per-widget metric is always the source of truth — there is no
        // app-global single-value metric to fall back to, and the primary
        // use case is multiple widgets each showing a *different* metric.
        settings["metric"] ?? WidgetSettings.defaultSingleValueMetric
    }

    private var refreshRate: SingleValueRefreshRate {
        WidgetSettings.singleValueRefreshRate(settings)
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
    @State private var engineStatus: EngineStatus = .idle

    private var displayValue: String {
        guard let v = value, engineStatus == .running else {
            return "—"
        }
        if metricKey == "SONE" {
            return String(format: "%.2f", v)
        }
        return String(format: "%.1f", v)
    }

    var body: some View {
        // The card header is hidden for value widgets when idle, so the kernel
        // itself carries the value's designation (metric name + unit) — that is
        // what tells the otherwise-identical single-value cards apart.
        VStack(spacing: 2) {
            Text(displayValue)
                .font(.numerals(numerals, size: 34, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(engineStatus == .running ? .primary : .gray)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(value ?? 0)))
                .animation(.easeOut(duration: 0.2), value: value)

            (Text(displayTitle) + Text("  \(unitLabel)"))
                .font(.readout(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .innerCanvas(cornerRadius: 0)
        .onReceive(live.$currentSpectrogramData) { data in
            if data == nil {
                self.value = nil
            }
        }
        .onReceive(
            live.$currentSpectrogramData
                .compactMap { $0 }
                .throttledForSingleValueDisplay(rate: refreshRate)
        ) { data in
            // PHON and SONE are now populated by AcousticMetricsCalculator,
            // so all metrics including loudness use the same levels dict path.
            let raw = data.levels[metricKey] ?? 0.0
            let floor = WidgetSettings.noiseFloorDB(settings)
            // Suppress display when the signal is at or below the noise floor.
            self.value = (floor > -119 && raw <= floor) ? nil : raw
        }
        .onReceive(engineStatusPublisher) { status in
            engineStatus = status
            if status != .running {
                self.value = nil
            }
        }
    }
}
