import SwiftUI
import WidgetKit

/// Phosphor green from the iOS redesign accent palette. Hardcoded for
/// now — sharing iOS `AccentChoice` to the complication target needs
/// App Group plumbing (M6 task-4 outstanding).
private let phosphor = Color(red: 0.45, green: 0.93, blue: 0.55)

// MARK: - Circular Small (arc + centered number)

struct CircularComplicationView: View {
    let entry: WatchComplicationEntry

    var body: some View {
        Gauge(value: entry.gaugeValue) {
            Text(entry.labelText)
                .font(.system(size: 8, weight: .regular, design: .monospaced))
        } currentValueLabel: {
            Text(entry.levelText)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
        .tint(phosphor)
    }
}

// MARK: - Corner (eyebrow + big readout + bar at outer edge)

struct CornerComplicationView: View {
    let entry: WatchComplicationEntry

    var body: some View {
        Text(entry.levelText)
            .font(.system(size: 18, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(phosphor)
            .widgetLabel {
                Gauge(value: entry.gaugeValue) {
                    Text("LAF · slow")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .tracking(1.0)
                } currentValueLabel: {
                    Text(entry.labelText)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                }
                .tint(phosphor)
            }
    }
}

// MARK: - Rectangular / Smart Stack (eyebrow + hero + gauge)
//
// Sparkline + Leq/Lmax/Δ stats from the redesign spec require
// extending WatchComplicationEntry — deferred. This pass refreshes
// the chrome (mono numerals, eyebrow tracking, phosphor tint).

struct RectangularComplicationView: View {
    let entry: WatchComplicationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("LAF · LIVE")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(entry.levelText)
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(phosphor)
                Text(entry.labelText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
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
        case ..<70: return phosphor
        case 70..<85: return Color(red: 0.99, green: 0.74, blue: 0.27)
        default: return Color(red: 0.93, green: 0.38, blue: 0.30)
        }
    }
}

// MARK: - Inline ("SPEKTO  50 dB(A)")
//
// "peak 78" suffix from the redesign requires extending
// WatchComplicationEntry with peak — deferred.

struct InlineComplicationView: View {
    let entry: WatchComplicationEntry

    var body: some View {
        if let level = entry.level {
            Label(
                String(format: "SPEKTO  %.0f %@", level, entry.labelText),
                systemImage: "waveform"
            )
        } else {
            Label("SPEKTO  — \(entry.labelText)", systemImage: "waveform")
        }
    }
}
