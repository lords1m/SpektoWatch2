import SwiftUI

/// Small visual helpers used by `RecordingDetailView`. Extracted from
/// the main file as part of M13 task-2 (split RecordingDetailView).
///
/// These views own no shared state with the parent — they receive
/// data via plain parameters — so the extraction is purely mechanical.

struct MiniLineChart: View {
    let values: [Float]

    var body: some View {
        GeometryReader { geo in
            let leftPadding: CGFloat = 32
            let rightPadding: CGFloat = 8
            let topPadding: CGFloat = 8
            let bottomPadding: CGFloat = 16
            let chartRect = CGRect(
                x: leftPadding,
                y: topPadding,
                width: max(1, geo.size.width - leftPadding - rightPadding),
                height: max(1, geo.size.height - topPadding - bottomPadding)
            )

            let measuredMin = Double(values.min() ?? -120)
            let measuredMax = Double(values.max() ?? -120)
            let minValue = floor((measuredMin - 2) / 5.0) * 5.0
            let maxValue = ceil((measuredMax + 2) / 5.0) * 5.0
            let majorTicks = ScientificAxis.majorTicks(min: minValue, max: maxValue, targetTicks: 5)
            let minorTicks = ScientificAxis.minorTicks(major: majorTicks, subdivisions: 2)

            Canvas { context, size in
                for tick in minorTicks where tick >= minValue && tick <= maxValue {
                    let yNorm = ScientificAxis.normalized(tick, min: minValue, max: maxValue)
                    let y = chartRect.maxY - CGFloat(yNorm) * chartRect.height
                    var path = Path()
                    path.move(to: CGPoint(x: chartRect.minX, y: y))
                    path.addLine(to: CGPoint(x: chartRect.maxX, y: y))
                    context.stroke(path, with: .color(ScientificChartPalette.gridMinor), lineWidth: 0.5)
                }

                for tick in majorTicks where tick >= minValue && tick <= maxValue {
                    let yNorm = ScientificAxis.normalized(tick, min: minValue, max: maxValue)
                    let y = chartRect.maxY - CGFloat(yNorm) * chartRect.height
                    var path = Path()
                    path.move(to: CGPoint(x: chartRect.minX, y: y))
                    path.addLine(to: CGPoint(x: chartRect.maxX, y: y))
                    context.stroke(path, with: .color(ScientificChartPalette.gridMajor), lineWidth: 0.8)
                    context.draw(
                        Text("\(Int(tick))").font(.system(size: 8, weight: .regular, design: .monospaced)).foregroundColor(ScientificChartPalette.axis),
                        at: CGPoint(x: chartRect.minX - 14, y: y)
                    )
                }

                guard values.count > 1 else { return }

                var seriesPath = Path()
                for (index, value) in values.enumerated() {
                    let x = chartRect.minX + chartRect.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                    let yNorm = ScientificAxis.normalized(Double(value), min: minValue, max: maxValue)
                    let y = chartRect.maxY - CGFloat(yNorm) * chartRect.height
                    if index == 0 {
                        seriesPath.move(to: CGPoint(x: x, y: y))
                    } else {
                        seriesPath.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                var fillPath = seriesPath
                fillPath.addLine(to: CGPoint(x: chartRect.maxX, y: chartRect.maxY))
                fillPath.addLine(to: CGPoint(x: chartRect.minX, y: chartRect.maxY))
                fillPath.closeSubpath()
                context.fill(fillPath, with: .color(ScientificChartPalette.fill))
                context.stroke(seriesPath, with: .color(ScientificChartPalette.series), lineWidth: 1.6)

                var axis = Path()
                axis.move(to: CGPoint(x: chartRect.minX, y: chartRect.minY))
                axis.addLine(to: CGPoint(x: chartRect.minX, y: chartRect.maxY))
                axis.addLine(to: CGPoint(x: chartRect.maxX, y: chartRect.maxY))
                context.stroke(axis, with: .color(ScientificChartPalette.axis), lineWidth: 1.0)
            }
        }
    }
}

struct StatRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }
}
