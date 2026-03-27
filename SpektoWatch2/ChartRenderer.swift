#if canImport(UIKit)
import UIKit

enum ChartRenderer {
    static func drawLineChart(
        in context: CGContext,
        rect: CGRect,
        values: [Float],
        minValue: Float? = nil,
        maxValue: Float? = nil,
        strokeColor: UIColor = .systemBlue,
        lineWidth: CGFloat = 1.5
    ) {
        guard values.count >= 2 else { return }
        let minV = minValue ?? (values.min() ?? 0)
        let maxV = maxValue ?? (values.max() ?? 1)
        let niceMin = floor(Double(minV) / 5.0) * 5.0
        let niceMax = ceil(Double(maxV) / 5.0) * 5.0
        let range = max(Float(niceMax - niceMin), 1e-6)
        let leftAxisWidth: CGFloat = 28
        let plotRect = rect.insetBy(dx: 0, dy: 0).inset(by: UIEdgeInsets(top: 4, left: leftAxisWidth, bottom: 12, right: 6))

        let ticks = ScientificAxis.majorTicks(min: niceMin, max: niceMax, targetTicks: 6)

        context.saveGState()
        context.setStrokeColor(UIColor.label.withAlphaComponent(0.18).cgColor)
        context.setLineWidth(0.6)
        for tick in ticks where tick >= niceMin && tick <= niceMax {
            let yNorm = CGFloat(ScientificAxis.normalized(tick, min: niceMin, max: niceMax))
            let y = plotRect.maxY - yNorm * plotRect.height
            context.move(to: CGPoint(x: plotRect.minX, y: y))
            context.addLine(to: CGPoint(x: plotRect.maxX, y: y))
            context.strokePath()

            let label = String(format: "%.0f", tick)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 8, weight: .regular),
                .foregroundColor: UIColor.label.withAlphaComponent(0.75)
            ]
            label.draw(in: CGRect(x: rect.minX, y: y - 5, width: leftAxisWidth - 4, height: 10), withAttributes: attrs)
        }

        context.setStrokeColor(UIColor.label.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(0.9)
        context.move(to: CGPoint(x: plotRect.minX, y: plotRect.minY))
        context.addLine(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
        context.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))
        context.strokePath()

        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineJoin(.round)
        context.setLineCap(.round)

        for (index, value) in values.enumerated() {
            let x = plotRect.minX + CGFloat(index) / CGFloat(values.count - 1) * plotRect.width
            let normalizedY = CGFloat((value - Float(niceMin)) / range)
            let y = plotRect.maxY - normalizedY * plotRect.height
            if index == 0 {
                context.move(to: CGPoint(x: x, y: y))
            } else {
                context.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.strokePath()
        context.restoreGState()
    }

    static func drawBarChart(
        in context: CGContext,
        rect: CGRect,
        values: [Float],
        minValue: Float = 0,
        maxValue: Float? = nil,
        fillColor: UIColor = .systemTeal
    ) {
        guard !values.isEmpty else { return }
        let maxV = maxValue ?? (values.max() ?? 1)
        let niceMin = floor(Double(minValue) / 5.0) * 5.0
        let niceMax = ceil(Double(maxV) / 5.0) * 5.0
        let range = max(Float(niceMax - niceMin), 1e-6)
        let leftAxisWidth: CGFloat = 28
        let plotRect = rect.inset(by: UIEdgeInsets(top: 4, left: leftAxisWidth, bottom: 12, right: 6))
        let barWidth = plotRect.width / CGFloat(values.count)
        let ticks = ScientificAxis.majorTicks(min: niceMin, max: niceMax, targetTicks: 6)

        context.saveGState()
        context.setStrokeColor(UIColor.label.withAlphaComponent(0.18).cgColor)
        context.setLineWidth(0.6)
        for tick in ticks where tick >= niceMin && tick <= niceMax {
            let yNorm = CGFloat(ScientificAxis.normalized(tick, min: niceMin, max: niceMax))
            let y = plotRect.maxY - yNorm * plotRect.height
            context.move(to: CGPoint(x: plotRect.minX, y: y))
            context.addLine(to: CGPoint(x: plotRect.maxX, y: y))
            context.strokePath()

            let label = String(format: "%.0f", tick)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 8, weight: .regular),
                .foregroundColor: UIColor.label.withAlphaComponent(0.75)
            ]
            label.draw(in: CGRect(x: rect.minX, y: y - 5, width: leftAxisWidth - 4, height: 10), withAttributes: attrs)
        }

        context.setStrokeColor(UIColor.label.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(0.9)
        context.move(to: CGPoint(x: plotRect.minX, y: plotRect.minY))
        context.addLine(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
        context.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))
        context.strokePath()

        context.setFillColor(fillColor.cgColor)
        for (index, value) in values.enumerated() {
            let normalized = CGFloat((value - Float(niceMin)) / range)
            let height = max(0, normalized) * plotRect.height
            let barRect = CGRect(
                x: plotRect.minX + CGFloat(index) * barWidth + 1,
                y: plotRect.maxY - height,
                width: max(1, barWidth - 2),
                height: height
            )
            context.fill(barRect)
        }
        context.restoreGState()
    }
}
#endif
