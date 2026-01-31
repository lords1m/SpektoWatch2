import SwiftUI
import Charts

/// Widget zur Visualisierung der Zeit-Frequenz-Unsicherheit (Heisenberg)
struct HeisenbergResolutionWidget: View {
    @ObservedObject var fftConfig: FFTConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "atom")
                    .foregroundStyle(.purple)
                Text("Zeit-Frequenz-Unsicherheit")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }

            // Heisenberg Chart
            HeisenbergChartWidget(
                blockSize: fftConfig.blockSize,
                allSizes: FFTBlockSize.allCases
            )
            .frame(maxHeight: .infinity)

            // Resolution Details
            HStack(spacing: 8) {
                ResolutionCardWidget(
                    icon: "waveform",
                    label: "Frequenz (f)",
                    value: String(format: "%.2f Hz", fftConfig.frequencyResolution),
                    color: .blue
                )

                ResolutionCardWidget(
                    icon: "clock",
                    label: "Zeit (t)",
                    value: String(format: "%.1f ms", fftConfig.timeResolutionMs),
                    color: .orange
                )

                ResolutionCardWidget(
                    icon: "number",
                    label: "Bins",
                    value: "\(fftConfig.binCount)",
                    color: .green
                )
            }
        }
        .padding(12)
    }
}

// MARK: - Helper Views

private struct HeisenbergChartWidget: View {
    let blockSize: FFTBlockSize
    let allSizes: [FFTBlockSize]

    var body: some View {
        let data = allSizes.map { size in
            (
                size: size,
                freqRes: 44100.0 / Float(size.rawValue),
                timeRes: Float(size.rawValue) / 44100.0 * 1000.0
            )
        }

        Chart(data, id: \.size) { point in
            PointMark(
                x: .value("t (ms)", point.timeRes),
                y: .value("f (Hz)", point.freqRes)
            )
            .foregroundStyle(point.size == blockSize ? .purple : .gray.opacity(0.4))
            .symbolSize(point.size == blockSize ? 150 : 60)

            if point.size == blockSize {
                RuleMark(x: .value("t", point.timeRes))
                    .foregroundStyle(.purple.opacity(0.3))
                    .lineStyle(StrokeStyle(dash: [4, 4]))
                RuleMark(y: .value("f", point.freqRes))
                    .foregroundStyle(.purple.opacity(0.3))
                    .lineStyle(StrokeStyle(dash: [4, 4]))
            }
        }
        .chartXAxisLabel("t (ms)", position: .bottom)
        .chartYAxisLabel("f (Hz)", position: .leading)
        .chartXScale(type: .log)
        .chartYScale(type: .log)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Float.self) {
                        Text(String(format: "%.0f", v))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Float.self) {
                        Text(String(format: "%.0f", v))
                            .font(.caption2)
                    }
                }
            }
        }
    }
}

private struct ResolutionCardWidget: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.caption2)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
}
