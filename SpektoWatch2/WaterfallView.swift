import SwiftUI

struct WaterfallView: View {
    let dataSet: WaterfallDataSet
    let highlightedTime: TimeInterval

    /// Camera state for the 3D-style waterfall projection.
    /// In the diagram's coordinate system: X = frequency (horizontal),
    /// Y = time (depth into the scene), Z = amplitude (vertical).
    ///
    /// - `pitch`: 0…1 controls how steep the time recession is. 0 = pure
    ///   side-on (no depth, current spectrum line only), 1 = strongly
    ///   tilted "looking down" (max depth, near top-down).
    /// - `yaw`: −1…+1 controls horizontal shear of the time stack
    ///   (slices recede to the right at +1, to the left at −1).
    /// - `zoom`: 1.0 baseline; >1 zooms in on amplitude, <1 zooms out.
    /// - Reset via double-tap.
    @State private var pitch: CGFloat = 0.5
    @State private var yaw: CGFloat = 1.0
    @State private var zoom: CGFloat = 1.0
    @GestureState private var dragDelta: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1.0

    private static let defaultPitch: CGFloat = 0.5
    private static let defaultYaw: CGFloat = 1.0
    private static let defaultZoom: CGFloat = 1.0

    private var effectivePitch: CGFloat {
        // Vertical drag: down → more tilt; up → flatter.
        let raw = pitch + dragDelta.height / 200
        return max(0, min(1, raw))
    }

    private var effectiveYaw: CGFloat {
        // Horizontal drag: right → recede right; left → recede left.
        let raw = yaw + dragDelta.width / 250
        return max(-1, min(1, raw))
    }

    private var effectiveZoom: CGFloat {
        max(0.25, min(4.0, zoom * magnification))
    }

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
            .contentShape(Rectangle())
            // 1-finger drag: tilt the 3D camera (pitch ↕ + yaw ↔).
            .gesture(
                DragGesture(minimumDistance: 4)
                    .updating($dragDelta) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        pitch = max(0, min(1, pitch + value.translation.height / 200))
                        yaw = max(-1, min(1, yaw + value.translation.width / 250))
                    }
            )
            // 2-finger pinch: zoom the amplitude (Z) axis.
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($magnification) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        zoom = max(0.25, min(4.0, zoom * value))
                    }
            )
            // Double-tap: reset camera + zoom.
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    pitch = Self.defaultPitch
                    yaw = Self.defaultYaw
                    zoom = Self.defaultZoom
                }
            }
            .accessibilityIdentifier("recordingWaterfallView")
        }
    }

    private func draw(in bounds: CGRect, context: inout GraphicsContext) {
        guard !dataSet.isEmpty else { return }

        // Margins reserve space for axis labels OUTSIDE the plot area:
        //  top 22pt: max-dB label + duration
        //  left 42pt: keeps room for the implicit Y scale
        //  bottom 36pt: 20 Hz / 20 kHz tick row + min-dB label
        //  right 12pt: trailing breathing room
        let plot = CGRect(
            x: bounds.minX + 42,
            y: bounds.minY + 22,
            width: max(1, bounds.width - 54),
            height: max(1, bounds.height - 58)
        )
        let sliceCount = dataSet.slices.count

        // Camera-driven perspective. Pitch sets time-axis depth (Y),
        // yaw rotates the recession horizontally (X-shear), zoom
        // scales amplitude (Z).
        let pitchEff = effectivePitch          // 0…1
        let yawEff = effectiveYaw              // −1…+1
        let zoomEff = effectiveZoom            // 0.25…4
        let maxDepthY: CGFloat = 38
        let maxDepthX: CGFloat = 54
        let depthY = pitchEff * min(maxDepthY, plot.height * 0.30)
        let depthX = yawEff * min(maxDepthX, plot.width * 0.20)
        let frontBaseY = plot.maxY - depthY
        let usableHeight = max(1, plot.height - depthY - 10) * zoomEff

        drawGrid(plot: plot, frontBaseY: frontBaseY, depthX: depthX, depthY: depthY, context: &context)

        // The newest slice = the *current* spectrum and lives at the
        // FRONT of the 3D scene (the user's "current spectrum should
        // be in the front" requirement). WaterfallDataBuilder writes
        // oldest→newest in `dataSet.slices`, so age = 1 for index 0
        // (oldest, max recession) and age = 0 for the last index
        // (newest, no recession).
        let lastIndex = sliceCount - 1
        // Draw back-to-front (painter's algorithm): start with oldest
        // (highest age, deepest into the scene) and end with newest.
        for displayIndex in 0...lastIndex {
            let slice = dataSet.slices[displayIndex]
            let age = CGFloat(lastIndex - displayIndex) / CGFloat(max(lastIndex, 1))
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
            // Newest slice = front = 1.8pt for emphasis; others 1pt.
            let lineWidth: CGFloat = (displayIndex == lastIndex) ? 1.8 : 1.0
            context.stroke(path, with: .color(color), lineWidth: lineWidth)

            // Periodic fill highlights to give the stack body.
            if (lastIndex - displayIndex).isMultiple(of: 4) || displayIndex == 0 {
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
        // All labels live in the margin area OUTSIDE `plot` — never on top
        // of the spectrogram trace.
        let topLabelY = bounds.minY + 10
        let bottomLabelY = bounds.maxY - 10

        // Top margin: max dB on the left, duration on the right.
        drawText("\(Int(dataSet.maxDB)) dB", at: CGPoint(x: bounds.minX + 4, y: topLabelY), anchor: .leading, context: &context)
        drawText(formatDuration(dataSet.duration), at: CGPoint(x: bounds.maxX - 4, y: topLabelY), anchor: .trailing, context: &context)

        // Bottom margin: 20 Hz, min dB (center), 20 kHz.
        drawText("20 Hz", at: CGPoint(x: plot.minX, y: bottomLabelY), anchor: .leading, context: &context)
        drawText("\(Int(dataSet.minDB)) dB", at: CGPoint(x: bounds.midX, y: bottomLabelY), anchor: .center, context: &context)
        drawText("20 kHz", at: CGPoint(x: plot.maxX, y: bottomLabelY), anchor: .trailing, context: &context)
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
        let raw = Float(settings["waterfallMinDB"] ?? String(Int(WidgetSettings.defaultWaterfallMinDB))) ?? WidgetSettings.defaultWaterfallMinDB
        // Migration: pre-fix settings stored dBFS-style negative values
        // (e.g. -110). Magnitudes are calibrated dB SPL now, so any
        // saved negative value is from the old scheme — fall back to
        // the SPL default.
        return raw < 0 ? WidgetSettings.defaultWaterfallMinDB : raw
    }
    private var maxDB: Float {
        guard useWidgetOverrides else { return WidgetSettings.defaultWaterfallMaxDB }
        let raw = Float(settings["waterfallMaxDB"] ?? String(Int(WidgetSettings.defaultWaterfallMaxDB))) ?? WidgetSettings.defaultWaterfallMaxDB
        // Migration: a saved max ≤ 0 is also from the old dBFS scheme.
        return raw <= 0 ? WidgetSettings.defaultWaterfallMaxDB : raw
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
