import SwiftUI
import Combine

/// UI-13: owns the throttled metric subscription. Building the throttled
/// publisher inside `body` re-created (and reset) the throttle on every
/// render, so the refresh-rate setting had no effect. The subscription is
/// rebuilt only when rate, metric or noise floor change.
@MainActor
final class SingleValueFeed: ObservableObject {
    @Published private(set) var value: Float?

    private struct Key: Equatable {
        let rate: SingleValueRefreshRate
        let metric: String
        let floor: Float
    }
    private var key: Key?
    private var cancellable: AnyCancellable?
    private var clearCancellable: AnyCancellable?

    func configure(live: LiveAcousticState, rate: SingleValueRefreshRate, metric: String, floor: Float) {
        let newKey = Key(rate: rate, metric: metric, floor: floor)
        guard newKey != key else { return }
        key = newKey
        cancellable = live.$currentSpectrogramData
            .compactMap { $0 }
            .throttledForSingleValueDisplay(rate: rate)
            .sink { [weak self] data in
                // PHON and SONE are populated by AcousticMetricsCalculator, so
                // all metrics use the same levels dict path.
                let raw = data.levels[metric] ?? 0.0
                // Suppress display when the signal is at or below the noise floor.
                self?.value = (floor > -119 && raw <= floor) ? nil : raw
            }
        clearCancellable = live.$currentSpectrogramData
            .filter { $0 == nil }
            .sink { [weak self] _ in self?.value = nil }
    }

    func clear() { value = nil }
}

struct SingleValueWidget: View {
    @ObservedObject private var live: LiveAcousticState
    @StateObject private var feed = SingleValueFeed()
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
    
    private var value: Float? { feed.value }
    @State private var engineStatus: EngineStatus = .idle

    private func configureFeed() {
        feed.configure(
            live: live,
            rate: refreshRate,
            metric: metricKey,
            floor: WidgetSettings.noiseFloorDB(settings)
        )
    }

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
        // Frameless layout: rely on the card's own header for the widget
        // name + dB(A) meta pill, so the kernel surfaces only the value
        // and its unit. No internal title row, no surrounding padding —
        // numerals fill the kernel area edge-to-edge and animate with
        // SwiftUI's numericText content transition.
        VStack(spacing: 0) {
            Text(displayValue)
                .font(.numerals(numerals, size: 36, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(engineStatus == .running ? .primary : .gray)
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
        .innerCanvas(cornerRadius: 0)
        .onAppear(perform: configureFeed)
        .onChange(of: settings) { _, _ in configureFeed() }
        .onReceive(engineStatusPublisher) { status in
            engineStatus = status
            if status != .running {
                feed.clear()
            }
        }
    }
}
