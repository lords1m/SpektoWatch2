import SwiftUI

struct WaterfallView: View {
    let dataSet: WaterfallDataSet
    let highlightedTime: TimeInterval

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                draw(in: CGRect(origin: .zero, size: size), context: &context)
            }
            .background(Color.black)
            .overlay(alignment: .topLeading) {
                if dataSet.isEmpty {
                    Text("Keine Wasserfall-Daten")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.72))
                        .padding(12)
                }
            }
            .accessibilityIdentifier("recordingWaterfallView")
        }
    }

    private func draw(in bounds: CGRect, context: inout GraphicsContext) {
        guard !dataSet.isEmpty else { return }

        let plot = CGRect(
            x: bounds.minX + 42,
            y: bounds.minY + 16,
            width: max(1, bounds.width - 72),
            height: max(1, bounds.height - 54)
        )
        let sliceCount = dataSet.slices.count
        let depthX = min(54, plot.width * 0.14)
        let depthY = min(38, plot.height * 0.18)
        let frontBaseY = plot.maxY - depthY
        let usableHeight = max(1, plot.height - depthY - 10)

        drawGrid(plot: plot, frontBaseY: frontBaseY, depthX: depthX, depthY: depthY, context: &context)

        for (displayIndex, slice) in dataSet.slices.enumerated().reversed() {
            let age = CGFloat(displayIndex) / CGFloat(max(sliceCount - 1, 1))
            let offsetX = depthX * age
            let offsetY = -depthY * age
            let opacity = 0.20 + 0.70 * (1.0 - age)
            let path = slicePath(
                slice: slice,
                plot: plot,
                baseY: frontBaseY + offsetY,
                offsetX: offsetX,
                usableHeight: usableHeight
            )
            let color = lineColor(for: slice.magnitudes.max() ?? dataSet.minDB).opacity(opacity)
            context.stroke(path, with: .color(color), lineWidth: displayIndex == 0 ? 1.8 : 1.0)

            if displayIndex.isMultiple(of: 4) || displayIndex == sliceCount - 1 {
                let fill = fillPath(from: path, plot: plot, baseY: frontBaseY + offsetY, offsetX: offsetX)
                context.fill(fill, with: .color(color.opacity(0.10)))
            }
        }

        drawPlayhead(plot: plot, frontBaseY: frontBaseY, depthX: depthX, depthY: depthY, context: &context)
        drawLabels(plot: plot, bounds: bounds, context: &context)
    }

    private func drawGrid(
        plot: CGRect,
        frontBaseY: CGFloat,
        depthX: CGFloat,
        depthY: CGFloat,
        context: inout GraphicsContext
    ) {
        let gridColor = Color.white.opacity(0.18)
        var outline = Path()
        outline.move(to: CGPoint(x: plot.minX, y: frontBaseY))
        outline.addLine(to: CGPoint(x: plot.maxX, y: frontBaseY))
        outline.addLine(to: CGPoint(x: plot.maxX + depthX, y: frontBaseY - depthY))
        outline.addLine(to: CGPoint(x: plot.minX + depthX, y: frontBaseY - depthY))
        outline.closeSubpath()
        context.stroke(outline, with: .color(gridColor), lineWidth: 1)

        for fraction in stride(from: CGFloat(0.0), through: 1.0, by: 0.25) {
            let y = frontBaseY - fraction * (plot.height - depthY - 10)
            var path = Path()
            path.move(to: CGPoint(x: plot.minX, y: y))
            path.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(path, with: .color(gridColor.opacity(0.7)), lineWidth: 0.7)
        }

        for fraction in stride(from: CGFloat(0.0), through: 1.0, by: 0.25) {
            let x = plot.minX + fraction * plot.width
            var path = Path()
            path.move(to: CGPoint(x: x, y: frontBaseY))
            path.addLine(to: CGPoint(x: x + depthX, y: frontBaseY - depthY))
            context.stroke(path, with: .color(gridColor.opacity(0.6)), lineWidth: 0.7)
        }
    }

    private func slicePath(
        slice: WaterfallSlice,
        plot: CGRect,
        baseY: CGFloat,
        offsetX: CGFloat,
        usableHeight: CGFloat
    ) -> Path {
        var path = Path()
        guard !slice.magnitudes.isEmpty else { return path }

        for (index, magnitude) in slice.magnitudes.enumerated() {
            let x = plot.minX + CGFloat(index) / CGFloat(max(slice.magnitudes.count - 1, 1)) * plot.width + offsetX
            let normalized = normalizedLevel(magnitude)
            let y = baseY - CGFloat(normalized) * usableHeight
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    private func fillPath(from line: Path, plot: CGRect, baseY: CGFloat, offsetX: CGFloat) -> Path {
        var fill = line
        fill.addLine(to: CGPoint(x: plot.maxX + offsetX, y: baseY))
        fill.addLine(to: CGPoint(x: plot.minX + offsetX, y: baseY))
        fill.closeSubpath()
        return fill
    }

    private func drawPlayhead(
        plot: CGRect,
        frontBaseY: CGFloat,
        depthX: CGFloat,
        depthY: CGFloat,
        context: inout GraphicsContext
    ) {
        guard dataSet.duration > 0 else { return }
        let t = max(0, min(1, highlightedTime / dataSet.duration))
        let age = CGFloat(t)
        let xOffset = depthX * age
        let yOffset = -depthY * age
        var path = Path()
        path.move(to: CGPoint(x: plot.minX + xOffset, y: frontBaseY + yOffset))
        path.addLine(to: CGPoint(x: plot.maxX + xOffset, y: frontBaseY + yOffset))
        context.stroke(path, with: .color(.white.opacity(0.72)), lineWidth: 1.4)
    }

    private func drawLabels(plot: CGRect, bounds: CGRect, context: inout GraphicsContext) {
        drawText("20 Hz", at: CGPoint(x: plot.minX, y: bounds.maxY - 24), anchor: .leading, context: &context)
        drawText("20 kHz", at: CGPoint(x: plot.maxX, y: bounds.maxY - 24), anchor: .trailing, context: &context)
        drawText("\(Int(dataSet.maxDB)) dB", at: CGPoint(x: bounds.minX + 8, y: plot.minY + 8), anchor: .leading, context: &context)
        drawText("\(Int(dataSet.minDB)) dB", at: CGPoint(x: bounds.minX + 8, y: plot.maxY - 42), anchor: .leading, context: &context)
        drawText(formatDuration(dataSet.duration), at: CGPoint(x: bounds.maxX - 8, y: plot.minY + 8), anchor: .trailing, context: &context)
    }

    private func drawText(_ value: String, at point: CGPoint, anchor: UnitPoint, context: inout GraphicsContext) {
        let text = Text(value).font(.caption2).foregroundColor(.white.opacity(0.72))
        context.draw(text, at: point, anchor: anchor)
    }

    private func normalizedLevel(_ value: Float) -> Float {
        let range = max(1, dataSet.maxDB - dataSet.minDB)
        return max(0, min(1, (value - dataSet.minDB) / range))
    }

    private func lineColor(for value: Float) -> Color {
        let t = Double(normalizedLevel(value))
        if t < 0.33 {
            let u = t / 0.33
            return Color(red: 0.08, green: 0.22 + 0.42 * u, blue: 0.85 - 0.35 * u)
        }
        if t < 0.66 {
            let u = (t - 0.33) / 0.33
            return Color(red: 0.08 + 0.82 * u, green: 0.64 + 0.18 * u, blue: 0.50 - 0.42 * u)
        }
        let u = (t - 0.66) / 0.34
        return Color(red: 0.90 + 0.10 * u, green: 0.82 - 0.56 * u, blue: 0.08)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct WaterfallWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    var settings: [String: String]

    @State private var history: [[Float]] = []
    @State private var frequencies: [Float] = []
    @State private var dataSet = WaterfallDataSet(slices: [], frequencies: [], duration: 0, minDB: -110, maxDB: 20)
    @State private var lastBuildTime: TimeInterval = 0

    private var useWidgetOverrides: Bool { WidgetSettings.usesWidgetOverrides(settings) }
    private var weighting: String {
        if useWidgetOverrides {
            return settings["freqWeighting"] ?? audioEngine.frequencyWeighting.rawValue
        }
        return audioEngine.frequencyWeighting.rawValue
    }
    private var sliceCount: Int {
        guard useWidgetOverrides else { return WidgetSettings.defaultWaterfallSliceCount }
        return Int(settings["waterfallSlices"] ?? String(WidgetSettings.defaultWaterfallSliceCount)) ?? WidgetSettings.defaultWaterfallSliceCount
    }
    private var minDB: Float {
        guard useWidgetOverrides else { return WidgetSettings.defaultWaterfallMinDB }
        return Float(settings["waterfallMinDB"] ?? String(Int(WidgetSettings.defaultWaterfallMinDB))) ?? WidgetSettings.defaultWaterfallMinDB
    }
    private var maxDB: Float {
        guard useWidgetOverrides else { return WidgetSettings.defaultWaterfallMaxDB }
        return Float(settings["waterfallMaxDB"] ?? String(Int(WidgetSettings.defaultWaterfallMaxDB))) ?? WidgetSettings.defaultWaterfallMaxDB
    }
    private var maxHistoryFrames: Int {
        max(24, min(240, sliceCount * 2))
    }

    var body: some View {
        WaterfallView(dataSet: dataSet, highlightedTime: 0)
            .overlay(alignment: .topLeading) {
                HStack(spacing: 8) {
                    Image(systemName: "water.waves")
                        .font(.caption.weight(.semibold))
                    Text("Wasserfall")
                        .font(.caption.weight(.semibold))
                    Text(weighting.uppercased())
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.white.opacity(0.82))
                .padding(10)
            }
            .onReceive(audioEngine.spectrogramSubject) { data in
                appendFrame(data)
            }
            .onChange(of: weighting) { _, _ in
                resetHistory()
            }
            .onChange(of: sliceCount) { _, _ in
                trimHistoryIfNeeded()
                rebuildDataSet(force: true)
            }
            .onChange(of: minDB) { _, _ in
                rebuildDataSet(force: true)
            }
            .onChange(of: maxDB) { _, _ in
                rebuildDataSet(force: true)
            }
            .onAppear {
                if let currentData = audioEngine.currentSpectrogramData {
                    appendFrame(currentData)
                }
            }
            .accessibilityIdentifier("waterfallWidget")
    }

    private func appendFrame(_ data: SpectrogramData) {
        let magnitudes = data.magnitudes(for: weighting)
        guard !magnitudes.isEmpty, !data.frequencies.isEmpty else { return }

        history.append(magnitudes)
        frequencies = data.frequencies
        trimHistoryIfNeeded()
        rebuildDataSet(force: false)
    }

    private func trimHistoryIfNeeded() {
        if history.count > maxHistoryFrames {
            history.removeFirst(history.count - maxHistoryFrames)
        }
    }

    private func resetHistory() {
        history.removeAll(keepingCapacity: true)
        dataSet = WaterfallDataSet(slices: [], frequencies: [], duration: 0, minDB: minDB, maxDB: maxDB)
    }

    private func rebuildDataSet(force: Bool) {
        let now = CFAbsoluteTimeGetCurrent()
        guard force || now - lastBuildTime >= 0.12 else { return }
        lastBuildTime = now

        let sampleRate = audioEngine.currentSpectrogramData?.sampleRate ?? 44100.0
        let hopDuration = Double(audioEngine.scrollSpeed.rawValue) / max(1, sampleRate)
        let duration = max(hopDuration * Double(history.count), audioEngine.recordingDuration)
        dataSet = WaterfallDataBuilder.build(
            history: history,
            sourceFrequencies: frequencies,
            duration: duration,
            targetSliceCount: sliceCount,
            targetFrequencyCount: 128,
            minDB: minDB,
            maxDB: maxDB
        )
    }
}
