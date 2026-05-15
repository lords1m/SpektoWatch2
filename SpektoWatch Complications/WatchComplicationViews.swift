import SwiftUI
import WidgetKit

// MARK: - Circular

struct CircularComplicationView: View {
    let entry: WatchComplicationEntry

    var body: some View {
        Gauge(value: entry.gaugeValue) {
            Text(entry.labelText)
                .font(.system(size: 8, weight: .medium))
        } currentValueLabel: {
            Text(entry.levelText)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
        }
        .gaugeStyle(.accessoryCircular)
    }
}

// MARK: - Rectangular

struct RectangularComplicationView: View {
    let entry: WatchComplicationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SPL")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(entry.levelText)
                    .font(.system(size: 28, weight: .bold).monospacedDigit())
                Text(entry.labelText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            Gauge(value: entry.gaugeValue) {}
                .gaugeStyle(.accessoryLinear)
                .tint(gaugeColor(for: entry.level))
        }
    }

    private func gaugeColor(for level: Float?) -> Color {
        guard let level else { return .gray }
        switch level {
        case ..<70: return .green
        case 70..<85: return .yellow
        default: return .red
        }
    }
}

// MARK: - Inline

struct InlineComplicationView: View {
    let entry: WatchComplicationEntry

    var body: some View {
        if let level = entry.level {
            Label(
                String(format: "%.0f \(entry.labelText)", level),
                systemImage: "waveform"
            )
        } else {
            Label("– dB", systemImage: "waveform")
        }
    }
}
