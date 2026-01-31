import SwiftUI
import Charts

/// Widget zur Visualisierung der aktuellen Fensterfunktion
struct WindowFunctionWidget: View {
    @ObservedObject var fftConfig: FFTConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "waveform.path")
                    .foregroundStyle(.green)
                Text(fftConfig.windowFunction.localizedName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()

                // Quick selector
                Menu {
                    ForEach(WindowFunction.allCases) { window in
                        Button {
                            fftConfig.windowFunction = window
                        } label: {
                            HStack {
                                Text(window.localizedName)
                                if window == fftConfig.windowFunction {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Window Shape Chart
            WindowShapeChartWidget(windowFunction: fftConfig.windowFunction)
                .frame(height: 80)

            // Stats Row
            HStack(spacing: 16) {
                StatBoxWidget(
                    label: "Hauptlappen",
                    value: String(format: "%.1f\u{00D7}", fftConfig.windowFunction.mainLobeWidth),
                    color: .blue
                )
                StatBoxWidget(
                    label: "Seitenlappen",
                    value: "\(Int(fftConfig.windowFunction.sidelobeAttenuation)) dB",
                    color: .orange
                )
                StatBoxWidget(
                    label: "Gain",
                    value: String(format: "%.2f", fftConfig.windowFunction.coherentGain),
                    color: .green
                )
            }

            Spacer()

            // Description
            Text(fftConfig.windowFunction.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
    }
}

// MARK: - Helper Views

private struct WindowShapeChartWidget: View {
    let windowFunction: WindowFunction

    var body: some View {
        let values = windowFunction.generate(size: 128)
        let data = values.enumerated().map { (index: $0.offset, value: $0.element) }

        Chart(data, id: \.index) { point in
            LineMark(
                x: .value("Sample", point.index),
                y: .value("Amplitude", point.value)
            )
            .foregroundStyle(.green.gradient)

            AreaMark(
                x: .value("Sample", point.index),
                y: .value("Amplitude", point.value)
            )
            .foregroundStyle(.green.opacity(0.2))
        }
        .chartYScale(domain: 0...1.1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

private struct StatBoxWidget: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
