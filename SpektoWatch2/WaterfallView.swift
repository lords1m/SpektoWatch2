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

    /// View-local **Z range overlay** (dB shift). Non-destructive: does
    /// NOT write to the persisted widget settings. Reset on double-tap.
    /// Positive → shifts the visible dB window upward (display window
    /// reveals louder content); negative → downward.
    @State private var zOffsetDB: Float = 0
    /// View-local **X range overlay** (frequency-window pan). Fraction
    /// of the spectrum's full bin range, −1…+1. 0 = full bin range
    /// shown across the plot; +0.5 = visible window starts mid-spectrum
    /// (high frequencies fall off the right edge); −0.5 = visible
    /// window ends mid-spectrum (high frequencies pushed off-left).
    /// Reset on double-tap.
    @State private var xPanFrac: Float = 0

    /// Live deltas from the in-flight 2-finger pan (driven by the
    /// UIKit recognizer below). Committed into `zOffsetDB` / `xPanFrac`
    /// on gesture end.
    @State private var twoFingerDelta: CGSize = .zero

    private static let defaultPitch: CGFloat = 0.5
    private static let defaultYaw: CGFloat = 1.0
    private static let defaultZoom: CGFloat = 1.0
    private static let defaultZOffsetDB: Float = 0
    private static let defaultXPanFrac: Float = 0

    /// Discrete render mode picked from `effectivePitch`.
    /// - `.frontSpectrum2D`: pitch ≤ 0.15 — only the current/newest
    ///   slice is drawn, full-bleed, no depth. Pure 2D spectrum.
    /// - `.topDown2D`: pitch ≥ 0.85 — every slice rendered as a
    ///   horizontal band of colored cells (classic spectrogram).
    ///   X = frequency, Y = time, color = amplitude.
    /// - `.oblique3D`: in between — the existing 3D waterfall.
    private enum ViewMode { case frontSpectrum2D, oblique3D, topDown2D }

    private var viewMode: ViewMode {
        let p = effectivePitch
        if p <= 0.15 { return .frontSpectrum2D }
        if p >= 0.85 { return .topDown2D }
        return .oblique3D
    }

    private var viewModeLabel: String {
        switch viewMode {
        case .frontSpectrum2D: return "2D · Spektrum"
        case .oblique3D:        return "3D"
        case .topDown2D:       return "2D · Spektrogramm"
        }
    }

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

    /// Live Z dB shift, including the in-flight 2-finger pan delta.
    /// 2F vertical pan: 100pt → ~6 dB shift (scaled so a full-screen
    /// pan walks the dB window by a meaningful chunk).
    private var effectiveZOffsetDB: Float {
        let live = Float(-twoFingerDelta.height) * 0.06
        return clampDB(zOffsetDB + live)
    }

    /// Live X frequency-window pan, including the in-flight 2-finger
    /// pan delta. 2F horizontal pan: 100pt → ~0.10 (10%) shift.
    private var effectiveXPanFrac: Float {
        let live = Float(-twoFingerDelta.width) * 0.001
        return clampPan(xPanFrac + live)
    }

    private func clampDB(_ v: Float) -> Float { max(-40, min(40, v)) }
    private func clampPan(_ v: Float) -> Float { max(-1, min(1, v)) }

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
            // Double-tap: reset camera + zoom + view-local Z/X overlays.
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    pitch = Self.defaultPitch
                    yaw = Self.defaultYaw
                    zoom = Self.defaultZoom
                    zOffsetDB = Self.defaultZOffsetDB
                    xPanFrac = Self.defaultXPanFrac
                }
            }
            // 2-finger pan: vertical → Z dB-window shift, horizontal →
            // X frequency-window pan. View-local overlay, never written
            // to widget settings. Layered as an overlay so the UIKit
            // recognizer can coexist with the SwiftUI 1F drag + pinch.
            .overlay(
                TwoFingerPanRecognizer(
                    onChange: { delta in twoFingerDelta = delta },
                    onEnd: { delta in
                        zOffsetDB = clampDB(zOffsetDB + Float(-delta.height) * 0.06)
                        xPanFrac = clampPan(xPanFrac + Float(-delta.width) * 0.001)
                        twoFingerDelta = .zero
                    }
                )
                .allowsHitTesting(true)
            )
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
        switch viewMode {
        case .frontSpectrum2D:
            drawFrontSpectrum(plot: plot, context: &context)
        case .topDown2D:
            drawTopDownSpectrogram(plot: plot, context: &context)
        case .oblique3D:
            drawOblique3D(plot: plot, context: &context)
        }

        drawLabels(plot: plot, bounds: bounds, context: &context)
    }

    // MARK: - Render modes

    /// Pitch ≤ 0.15. Only the current (newest) spectrum is shown,
    /// rendered front-on like a regular spectrum widget.
    private func drawFrontSpectrum(plot: CGRect, context: inout GraphicsContext) {
        let zoomEff = effectiveZoom
        let baseY = plot.maxY
        let usableHeight = max(1, plot.height - 10) * zoomEff
        drawGrid(plot: plot, frontBaseY: baseY, depthX: 0, depthY: 0, context: &context)

        guard let current = dataSet.slices.last else { return }
        let path = slicePath(slice: current, plot: plot, baseY: baseY, offsetX: 0, usableHeight: usableHeight)
        let color = lineColor(for: current.magnitudes.max() ?? dataSet.minDB)
        let fill = fillPath(from: path, plot: plot, baseY: baseY, offsetX: 0)
        context.fill(fill, with: .color(color.opacity(0.15)))
        context.stroke(path, with: .color(color), lineWidth: 1.8)
    }

    /// Pitch ≥ 0.85. Spectrogram heatmap. Each slice = one
    /// horizontal row; each bin = one cell; cell color = amplitude
    /// (uses the same `lineColor` ramp the 3D / 2D modes use).
    /// Y-axis: top = oldest, bottom = newest (so the current
    /// spectrum is at the FRONT, matching the 3D mode).
    /// X-axis: same panFrac-aware mapping as `slicePath`.
    private func drawTopDownSpectrogram(plot: CGRect, context: inout GraphicsContext) {
        let slices = dataSet.slices
        guard !slices.isEmpty,
              let firstSlice = slices.first,
              !firstSlice.magnitudes.isEmpty else { return }

        let sliceCount = slices.count
        let binCount = firstSlice.magnitudes.count
        let panFrac = CGFloat(effectiveXPanFrac)
        let cellHeight = plot.height / CGFloat(sliceCount)
        let cellWidth = plot.width / CGFloat(max(binCount - 1, 1))

        for (sliceIndex, slice) in slices.enumerated() {
            // Newest slice → bottom row; oldest → top.
            let rowY = plot.minY + CGFloat(sliceIndex) * cellHeight
            for (binIndex, magnitude) in slice.magnitudes.enumerated() {
                let normalized = normalizedLevel(magnitude)
                guard normalized > 0.02 else { continue }
                let binFrac = CGFloat(binIndex) / CGFloat(max(binCount - 1, 1))
                let visibleFrac = binFrac - panFrac
                let x = plot.minX + visibleFrac * plot.width
                let rect = CGRect(
                    x: x,
                    y: rowY,
                    width: cellWidth + 0.5, // overlap to avoid 1px seams
                    height: cellHeight + 0.5
                )
                let color = lineColor(for: magnitude)
                context.fill(Path(rect), with: .color(color.opacity(0.6 + 0.4 * Double(normalized))))
            }
        }
    }

    /// 0.15 < pitch < 0.85. Existing 3D oblique waterfall.
    private func drawOblique3D(plot: CGRect, context: inout GraphicsContext) {
        let sliceCount = dataSet.slices.count
        let pitchEff = effectivePitch
        let yawEff = effectiveYaw
        let zoomEff = effectiveZoom
        let maxDepthY: CGFloat = 38
        let maxDepthX: CGFloat = 54
        let depthY = pitchEff * min(maxDepthY, plot.height * 0.30)
        let depthX = yawEff * min(maxDepthX, plot.width * 0.20)
        let frontBaseY = plot.maxY - depthY
        let usableHeight = max(1, plot.height - depthY - 10) * zoomEff

        drawGrid(plot: plot, frontBaseY: frontBaseY, depthX: depthX, depthY: depthY, context: &context)

        let lastIndex = sliceCount - 1
        for displayIndex in 0...lastIndex {
            let slice = dataSet.slices[displayIndex]
            let age = CGFloat(lastIndex - displayIndex) / CGFloat(max(lastIndex, 1))
            let offsetX = depthX * age
            let offsetY = -depthY * age
            let opacity = 0.20 + 0.70 * (1.0 - age)
            let path = slicePath(slice: slice, plot: plot, baseY: frontBaseY + offsetY,
                                 offsetX: offsetX, usableHeight: usableHeight)
            let color = lineColor(for: slice.magnitudes.max() ?? dataSet.minDB).opacity(opacity)
            let lineWidth: CGFloat = (displayIndex == lastIndex) ? 1.8 : 1.0
            context.stroke(path, with: .color(color), lineWidth: lineWidth)

            if (lastIndex - displayIndex).isMultiple(of: 4) || displayIndex == 0 {
                let fill = fillPath(from: path, plot: plot, baseY: frontBaseY + offsetY, offsetX: offsetX)
                context.fill(fill, with: .color(color.opacity(0.10)))
            }
        }

        drawPlayhead(plot: plot, frontBaseY: frontBaseY, depthX: depthX, depthY: depthY, context: &context)
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

        // 2F horizontal pan: shifts the visible frequency window. The
        // bin → x mapping subtracts xPanFracEff (−1…+1) so positive
        // pan slides the spectrum left (high frequencies enter the
        // view from the right). Bins that fall outside the plot rect
        // are still drawn but clipped by the surrounding chrome.
        let panFrac = CGFloat(effectiveXPanFrac)
        let denominator = CGFloat(max(slice.magnitudes.count - 1, 1))

        for (index, magnitude) in slice.magnitudes.enumerated() {
            let binFrac = CGFloat(index) / denominator
            let visibleFrac = binFrac - panFrac
            let x = plot.minX + visibleFrac * plot.width + offsetX
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
        // All labels live in the margin area OUTSIDE `plot` — never on
        // top of the trace. With Z-offset applied via the 2F pan, show
        // the SHIFTED window endpoints, not the dataset's raw min/max.
        let zShift = effectiveZOffsetDB
        let visibleMaxDB = Int((dataSet.maxDB + zShift).rounded())
        let visibleMinDB = Int((dataSet.minDB + zShift).rounded())

        let topLabelY = bounds.minY + 10
        let bottomLabelY = bounds.maxY - 10

        // Top margin: view-mode tag on the left, duration on the right.
        drawText(viewModeLabel, at: CGPoint(x: bounds.minX + 4, y: topLabelY),
                 anchor: .leading, context: &context)
        drawText(formatDuration(dataSet.duration), at: CGPoint(x: bounds.maxX - 4, y: topLabelY),
                 anchor: .trailing, context: &context)

        // Y-axis (left margin): max dB at the top of the plot rect,
        // min dB at the bottom of the plot rect. Both sit OUTSIDE the
        // plot, anchored to the trailing edge so the digits line up
        // along the chart's left edge.
        drawText("\(visibleMaxDB) dB",
                 at: CGPoint(x: plot.minX - 4, y: plot.minY + 6),
                 anchor: .trailing, context: &context)
        drawText("\(visibleMinDB) dB",
                 at: CGPoint(x: plot.minX - 4, y: plot.maxY - 6),
                 anchor: .trailing, context: &context)

        // X-axis (bottom margin): frequency endpoints below the plot.
        // Top-down mode swaps the bottom-row meaning: bottom-left is
        // still 20 Hz, bottom-right still 20 kHz — the X axis is the
        // same in all three modes, only Y changes meaning. So a single
        // label set works.
        drawText("20 Hz",
                 at: CGPoint(x: plot.minX, y: bottomLabelY),
                 anchor: .leading, context: &context)
        drawText("20 kHz",
                 at: CGPoint(x: plot.maxX, y: bottomLabelY),
                 anchor: .trailing, context: &context)
    }

    private func drawText(_ value: String, at point: CGPoint, anchor: UnitPoint, context: inout GraphicsContext) {
        let text = Text(value).font(.caption2).foregroundColor(.white.opacity(0.72))
        context.draw(text, at: point, anchor: anchor)
    }

    private func normalizedLevel(_ value: Float) -> Float {
        // 2F vertical pan: shifts the dB window. zOffsetDB > 0 moves
        // the window UP (display reveals louder content; the same raw
        // value normalises to a lower position). Keep the window
        // width unchanged.
        let zShift = effectiveZOffsetDB
        let minDB = dataSet.minDB + zShift
        let maxDB = dataSet.maxDB + zShift
        let range = max(1, maxDB - minDB)
        return max(0, min(1, (value - minDB) / range))
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

// MARK: - Two-finger pan recognizer (UIKit bridge)
//
// SwiftUI's DragGesture is 1-finger only. To get a true 2-finger pan
// that coexists with SwiftUI's MagnificationGesture (pinch) and the
// 1-finger DragGesture (tilt), we drop a transparent UIView into the
// view tree as an overlay and attach a UIPanGestureRecognizer with
// minimumNumberOfTouches = 2.
//
// Touch routing
// -------------
// The wrapping UIView only "claims" touch events when 2+ fingers are
// down. With 0 or 1 finger, hitTest returns nil so touches fall through
// to the SwiftUI layer beneath (where the 1-finger DragGesture lives).
// Once 2 fingers are detected, the recognizer fires .changed events with
// translation, which we feed back into SwiftUI state via the closures.
//
// Simultaneous recognition with MagnificationGesture works because UIKit
// dispatches pinch and 2-finger pan to separate recognizers based on
// motion type (parallel vs. opposing). Both fire at once if both motion
// signatures are present.
private struct TwoFingerPanRecognizer: UIViewRepresentable {
    let onChange: (CGSize) -> Void
    let onEnd: (CGSize) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = TwoFingerPassThroughView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        let recognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        recognizer.minimumNumberOfTouches = 2
        recognizer.maximumNumberOfTouches = 2
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let parent: TwoFingerPanRecognizer
        init(_ parent: TwoFingerPanRecognizer) { self.parent = parent }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let translation = recognizer.translation(in: recognizer.view)
            let delta = CGSize(width: translation.x, height: translation.y)
            switch recognizer.state {
            case .began, .changed:
                parent.onChange(delta)
            case .ended, .cancelled, .failed:
                parent.onEnd(delta)
            default:
                break
            }
        }

        // Allow this recognizer to fire at the same time as the SwiftUI
        // MagnificationGesture (pinch). Without this, UIKit would
        // arbitrate and one would win exclusively.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            return true
        }
    }
}

/// Transparent UIView that passes single-finger touches through to
/// the SwiftUI layer beneath and only intercepts events with 2+
/// active touches (where its UIPanGestureRecognizer will fire).
private final class TwoFingerPassThroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Counting allTouches is the cheapest way to disambiguate.
        // Single-finger drags arriving while this view is on top would
        // otherwise be swallowed and never reach the SwiftUI 1F drag.
        let touchCount = event?.allTouches?.count ?? 0
        if touchCount >= 2 {
            return super.hitTest(point, with: event)
        }
        return nil
    }
}
