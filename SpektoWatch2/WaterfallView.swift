import SwiftUI
import Combine

// ============================================================================
// MARK: - Turbo colormap LUT (matches HighEndSpectrogramShaders.metal)
// ============================================================================

/// 256-entry Turbo colormap, pre-computed once at first access. The polynomial
/// is from Google Research's Turbo paper — same coefficients the live
/// spectrogram Metal shader uses, so the two surfaces match visually.
///
/// Allocating Color per pixel per frame was burning ~1M allocations/s under the
/// old per-segment colorizer; the LUT keeps the hot path allocation-free.
private enum TurboColormap {
    static let entries: [Color] = (0..<256).map { i in
        sample(t: Float(i) / 255.0)
    }

    /// Looks up a normalized `t` in [0, 1] against the LUT.
    static func color(for t: Float) -> Color {
        let clamped = max(0, min(1, t))
        return entries[Int(clamped * 255)]
    }

    private static func sample(t: Float) -> Color {
        let t2 = t * t
        let t3 = t2 * t
        let t4 = t3 * t
        let t5 = t4 * t
        let r =  0.13572138 +  4.61539260 * t - 42.66032258 * t2 + 132.13108234 * t3 - 152.94239396 * t4 +  59.28637943 * t5
        let g =  0.09140261 +  2.19418839 * t +  4.84296658 * t2 -  14.18503333 * t3 +   4.27729857 * t4 +   2.82956604 * t5
        let b =  0.10667330 + 12.64194608 * t - 60.58204836 * t2 + 110.36276771 * t3 -  89.90310912 * t4 +  27.34824973 * t5
        return Color(
            red: Double(max(0, min(1, r))),
            green: Double(max(0, min(1, g))),
            blue: Double(max(0, min(1, b)))
        )
    }
}

// ============================================================================
// MARK: - Camera projection
// ============================================================================

/// Orthographic 3D-to-2D projection. World box is [-0.5, 0.5]^3;
/// output is in normalized screen space [-0.5, 0.5] (caller scales).
///
/// File-level (internal) rather than nested so the projection math is
/// unit-testable via `@testable import`.
struct WaterfallCameraProjection {
    let pitchRad: Float
    let yawRad: Float

    func project(_ p: SIMD3<Float>) -> (x: Float, y: Float, depth: Float) {
        // Yaw around world Y (vertical / amplitude).
        let cy = cos(yawRad), sy = sin(yawRad)
        let x1 = p.x * cy + p.z * sy
        let y1 = p.y
        let z1 = -p.x * sy + p.z * cy

        // Pitch around world X (horizontal / frequency).
        let cp = cos(pitchRad), sp = sin(pitchRad)
        let y2 = y1 * cp - z1 * sp
        let z2 = y1 * sp + z1 * cp

        // Mild orthographic-with-perspective: scale x/y by a factor
        // that grows with depth so closer slices look slightly larger
        // than far ones. Keeps the projection invertible-ish without
        // a true perspective divide (which would clip at the camera
        // plane). Closer (higher depth, since after pitch the newest
        // slice has positive z) gets ~1.15× scale; farther ~0.85×.
        let perspective = 1.0 + 0.30 * z2

        return (x: x1 * perspective, y: -y2 * perspective, depth: z2)
    }
}

// ============================================================================
// MARK: - Render options
// ============================================================================

/// Tunables that let one renderer serve both the compact dashboard tile and
/// the large analysis surfaces (fullscreen / recording playback) without
/// duplicating the drawing code.
struct WaterfallRenderOptions: Equatable {
    /// Draw amplitude-coloured peak dots. Off by default — they're a major
    /// source of clutter on a dense history.
    var showPeaks: Bool
    /// Overlay max-hold and average spectra in the level-axis (oblique) mode.
    var showStatistics: Bool
    /// Analysis chrome: dB colorbar legend, frequency/time gridlines, tick
    /// labels and the peak readout panel.
    var analysisLayout: Bool
    /// Start the camera looking straight down (filled heatmap) — the most
    /// analysis-friendly default for the fullscreen / playback surfaces.
    var startTopDown: Bool
    /// Cap on how many time-slices are stroked in the line / 3D modes. Storing
    /// more history than this is fine; the draw is strided so adjacent traces
    /// don't merge into an unreadable tangle.
    var maxRenderedTraces: Int
    /// Spectrum mode of the underlying data — lets the crosshair snap to band
    /// centers when the data is 1/3-octave / Bark / octave.
    var spectrumMode: WaterfallSpectrumMode

    init(showPeaks: Bool = false,
         showStatistics: Bool = false,
         analysisLayout: Bool = false,
         startTopDown: Bool = false,
         maxRenderedTraces: Int = 56,
         spectrumMode: WaterfallSpectrumMode = .continuous) {
        self.showPeaks = showPeaks
        self.showStatistics = showStatistics
        self.analysisLayout = analysisLayout
        self.startTopDown = startTopDown
        self.maxRenderedTraces = max(8, maxRenderedTraces)
        self.spectrumMode = spectrumMode
    }

    /// Compact dashboard tile — heatmap when looking top-down, minimal chrome.
    static let widget = WaterfallRenderOptions()

    /// Fullscreen / playback analysis surface — heatmap-first with full chrome.
    static func analysis(spectrumMode: WaterfallSpectrumMode = .continuous,
                         showPeaks: Bool = true,
                         showStatistics: Bool = true) -> WaterfallRenderOptions {
        WaterfallRenderOptions(
            showPeaks: showPeaks,
            showStatistics: showStatistics,
            analysisLayout: true,
            startTopDown: true,
            maxRenderedTraces: 56,
            spectrumMode: spectrumMode
        )
    }
}

// ============================================================================
// MARK: - Analysis helpers (pure, testable)
// ============================================================================

enum WaterfallAnalysis {
    struct Peak: Equatable {
        let binIndex: Int
        let frequency: Float
        let level: Float
    }

    /// Local maxima of a spectrum slice, sorted loudest-first. `minProminence`
    /// (dB above the slice mean) suppresses ripple; returns at most `limit`.
    static func peaks(magnitudes: [Float],
                      frequencies: [Float],
                      minProminence: Float = 3,
                      limit: Int = 6) -> [Peak] {
        guard magnitudes.count > 2 else { return [] }
        let mean = magnitudes.reduce(0, +) / Float(magnitudes.count)
        let upper = min(magnitudes.count, frequencies.count)
        guard upper > 2 else { return [] }
        var found: [Peak] = []
        var i = 1
        while i < upper - 1 {
            let v = magnitudes[i]
            if v > magnitudes[i - 1], v >= magnitudes[i + 1], v > mean + minProminence {
                found.append(Peak(binIndex: i, frequency: frequencies[i], level: v))
            }
            i += 1
        }
        found.sort { $0.level > $1.level }
        return Array(found.prefix(limit))
    }

    /// Per-bin maximum across every slice (max-hold).
    static func maxHold(slices: [[Float]]) -> [Float] {
        guard let first = slices.first, !first.isEmpty else { return [] }
        var out = first
        for slice in slices.dropFirst() where slice.count == out.count {
            for i in 0..<out.count { out[i] = max(out[i], slice[i]) }
        }
        return out
    }

    /// Per-bin linear average across every slice.
    static func average(slices: [[Float]]) -> [Float] {
        guard let first = slices.first, !first.isEmpty else { return [] }
        var out = [Float](repeating: 0, count: first.count)
        var n = 0
        for slice in slices where slice.count == out.count {
            for i in 0..<out.count { out[i] += slice[i] }
            n += 1
        }
        guard n > 0 else { return out }
        for i in 0..<out.count { out[i] /= Float(n) }
        return out
    }

    /// "Nice" frequency gridline anchors that fall inside [lo, hi].
    static func frequencyTicks(lo: Float, hi: Float) -> [Float] {
        let candidates: [Float] = [20, 31.5, 50, 63, 100, 125, 200, 250, 500,
                                   1_000, 2_000, 4_000, 5_000, 8_000, 10_000, 16_000, 20_000]
        return candidates.filter { $0 >= lo && $0 <= hi }
    }
}

// ============================================================================
// MARK: - WaterfallView (renderer)
// ============================================================================

struct WaterfallView: View {
    let dataSet: WaterfallDataSet
    /// When non-nil, draws a playhead bar at this position in the time axis.
    /// `nil` (live mode) suppresses the bar; recording-detail playback passes
    /// the current scrub time so the user sees where they are in the data.
    let highlightedTime: TimeInterval?
    /// Rendering / chrome configuration. Defaults to the compact tile preset.
    var options: WaterfallRenderOptions = .widget

    // MARK: Camera state

    /// `pitch` (0…1) — 0 = side-on, 1 = looking straight down.
    /// `yaw` (-1…+1) — ±1 = looking along the time axis (side mode).
    /// `zoom` — multiplicative amplitude scaling.
    /// All persist across view ticks; in-flight gestures layer on top via
    /// `@GestureState`.
    @State private var pitch: CGFloat = Self.defaultPitch
    @State private var yaw: CGFloat = Self.defaultYaw
    @State private var zoom: CGFloat = Self.defaultZoom
    /// View-local dB-window shift (2F vertical pan). Non-destructive.
    @State private var zOffsetDB: Float = Self.defaultZOffsetDB
    /// View-local frequency-window pan (2F horizontal pan).
    @State private var xPanFrac: Float = Self.defaultXPanFrac

    /// Crosshair picker state. `pickerEnabled` toggles on single-tap when in
    /// a 2D mode; `crosshair` follows 1-finger drag while the picker is on.
    @State private var pickerEnabled: Bool = false
    @State private var crosshair: CGPoint? = nil
    /// Second ("anchor") cursor for two-cursor Δf / Δt / ΔdB measurements.
    /// Set by a long-press while the picker is active.
    @State private var anchor: CGPoint? = nil
    /// Applies `options.startTopDown` exactly once on first appearance.
    @State private var didApplyStartMode: Bool = false

    @GestureState private var dragDelta: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var twoFingerDelta: CGSize = .zero

    // MARK: Constants

    private static let defaultPitch: CGFloat = 0.28
    private static let defaultYaw: CGFloat = 0.20
    private static let defaultZoom: CGFloat = 1.0
    private static let defaultZOffsetDB: Float = 0
    private static let defaultXPanFrac: Float = 0

    private static let pitchSensitivity: CGFloat = 200
    private static let yawSensitivity: CGFloat = 250
    private static let zoomMin: CGFloat = 0.25
    private static let zoomMax: CGFloat = 4.0
    private static let zPanScale: Float = 0.06       // 100 pt → 6 dB
    private static let xPanScale: Float = 0.001      // 100 pt → 0.10 pan

    /// Mode hysteresis bands keep the label and the picker eligibility
    /// stable when the user drags near a threshold. Mode is read from
    /// the persisted (snapped) `pitch`/`yaw`, not from `effectivePitch`,
    /// so in-flight drags don't flicker the mode label.
    private static let topModeEnter: CGFloat = 0.85
    private static let sideModeEnter: CGFloat = 0.85

    // MARK: View-mode logic

    private enum ViewMode { case oblique3D, topDown2D, sideLevelHistory2D }

    private var viewMode: ViewMode {
        if pitch >= Self.topModeEnter { return .topDown2D }
        if abs(yaw) >= Self.sideModeEnter { return .sideLevelHistory2D }
        return .oblique3D
    }

    private var viewModeLabel: String {
        switch viewMode {
        case .oblique3D:          return "3D · ISO"
        case .topDown2D:          return "2D · TOP"
        case .sideLevelHistory2D: return "2D · SIDE"
        }
    }

    /// 1-finger drag drives the crosshair picker only when (a) the camera
    /// is in a 2D-ish mode and (b) the user has toggled the picker on.
    /// Otherwise 1-finger drag tilts the camera (in 3D) or is a no-op (2D
    /// + picker off).
    private var inPickerMode: Bool {
        switch viewMode {
        case .topDown2D, .sideLevelHistory2D: return true
        case .oblique3D:                      return false
        }
    }

    // MARK: Effective values (camera state + in-flight gesture deltas)

    private var effectivePitch: CGFloat {
        max(0, min(1, pitch + dragDelta.height / Self.pitchSensitivity))
    }

    private var effectiveYaw: CGFloat {
        max(-1, min(1, yaw + dragDelta.width / Self.yawSensitivity))
    }

    private var effectiveZoom: CGFloat {
        max(Self.zoomMin, min(Self.zoomMax, zoom * pinchScale))
    }

    private var effectiveZOffsetDB: Float {
        let live = Float(-twoFingerDelta.height) * Self.zPanScale
        return clampDB(zOffsetDB + live)
    }

    /// Side mode ignores horizontal pan because X is time there, not
    /// frequency. Suppressing the live delta keeps the visible window
    /// fixed while the user 2F-pans for the Z shift in vertical motion.
    private var effectiveXPanFrac: Float {
        guard viewMode != .sideLevelHistory2D else { return xPanFrac }
        let live = Float(-twoFingerDelta.width) * Self.xPanScale
        return clampPan(xPanFrac + live)
    }

    private func clampDB(_ v: Float) -> Float { max(-40, min(40, v)) }
    private func clampPan(_ v: Float) -> Float { max(-1, min(1, v)) }

    private var visibleLeftEdgeFreq: Float {
        frequencyAt(binFrac: CGFloat(effectiveXPanFrac))
    }
    private var visibleRightEdgeFreq: Float {
        frequencyAt(binFrac: CGFloat(effectiveXPanFrac) + 1)
    }

    // MARK: Body

    /// Tag enum for Canvas symbols — avoids per-frame CoreText layout for
    /// labels that change only when the user rotates or pans the camera
    /// (M19 task-3).
    private enum LabelID: Hashable {
        case viewMode, duration, leftFreq, rightFreq, maxDB, minDB
    }

    @ViewBuilder
    private func labelText(_ str: String) -> some View {
        Text(str).font(.caption2).foregroundColor(.white.opacity(0.72))
    }

    private func drawSymbol(_ id: LabelID, at point: CGPoint, anchor: UnitPoint, context: inout GraphicsContext) {
        guard let symbol = context.resolveSymbol(id: id) else { return }
        context.draw(symbol, at: point, anchor: anchor)
    }

    var body: some View {
        let visibleMaxDB = Int((dataSet.maxDB + effectiveZOffsetDB).rounded())
        let visibleMinDB = Int((dataSet.minDB + effectiveZOffsetDB).rounded())
        GeometryReader { geometry in
            Canvas { context, size in
                draw(in: CGRect(origin: .zero, size: size), context: &context)
            } symbols: {
                labelText(viewModeLabel).tag(LabelID.viewMode)
                labelText(formatDuration(dataSet.duration)).tag(LabelID.duration)
                labelText(formatHz(visibleLeftEdgeFreq)).tag(LabelID.leftFreq)
                labelText(formatHz(visibleRightEdgeFreq)).tag(LabelID.rightFreq)
                labelText("\(visibleMaxDB) dB").tag(LabelID.maxDB)
                labelText("\(visibleMinDB) dB").tag(LabelID.minDB)
            }
            .background(Color.black)
            .overlay(alignment: .center) {
                if dataSet.isEmpty {
                    Text("Keine Wasserfall-Daten")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.72))
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .simultaneousGesture(zoomGesture)
            .simultaneousGesture(anchorLongPressGesture)
            // Tap ordering: count:2 must come BEFORE count:1 so SwiftUI's
            // disambiguation lets the double-tap window resolve first.
            .onTapGesture(count: 2, perform: resetCamera)
            .onTapGesture(count: 1, perform: togglePicker)
            .onAppear(perform: applyStartModeIfNeeded)
            .overlay(
                TwoFingerPanRecognizer(
                    onChange: { delta in twoFingerDelta = delta },
                    onEnd: { delta in
                        commitTwoFingerPan(delta)
                        twoFingerDelta = .zero
                    }
                )
                .allowsHitTesting(true)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("recordingWaterfallView")
            .accessibilityLabel(accessibilityDescription)
        }
    }

    // MARK: Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($dragDelta) { value, state, _ in
                // Only feed the camera-tilt delta when we're driving the
                // camera; in picker mode the drag is for the crosshair.
                if !(inPickerMode && pickerEnabled) {
                    state = value.translation
                }
            }
            .onChanged { value in
                if inPickerMode && pickerEnabled {
                    crosshair = value.location
                }
            }
            .onEnded { value in
                if inPickerMode && pickerEnabled {
                    crosshair = value.location
                    return
                }
                let newPitch = max(0, min(1, pitch + value.translation.height / Self.pitchSensitivity))
                let newYaw   = max(-1, min(1, yaw + value.translation.width / Self.yawSensitivity))
                withAnimation(.easeOut(duration: 0.2)) {
                    if newPitch >= Self.topModeEnter {
                        pitch = 1.0
                        yaw = 0
                    } else if abs(newYaw) >= Self.sideModeEnter {
                        yaw = newYaw >= 0 ? 1.0 : -1.0
                        pitch = 0.5
                    } else {
                        pitch = newPitch
                        yaw = newYaw
                    }
                }
            }
    }

    private var zoomGesture: some Gesture {
        // MagnifyGesture is the iOS 17+ replacement for the deprecated
        // MagnificationGesture (same semantics, new value type).
        MagnifyGesture()
            .updating($pinchScale) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                zoom = max(Self.zoomMin, min(Self.zoomMax, zoom * value.magnification))
            }
    }

    /// Long-press pins the current crosshair as the anchor (cursor B) so the
    /// readout switches to Δf / Δt / ΔdB between the two cursors.
    private var anchorLongPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .onEnded { _ in
                guard inPickerMode, pickerEnabled, let current = crosshair else { return }
                withAnimation(.easeInOut(duration: 0.15)) { anchor = current }
            }
    }

    private func applyStartModeIfNeeded() {
        guard !didApplyStartMode else { return }
        didApplyStartMode = true
        if options.startTopDown {
            pitch = 1.0
            yaw = 0
        }
    }

    private func commitTwoFingerPan(_ delta: CGSize) {
        zOffsetDB = clampDB(zOffsetDB + Float(-delta.height) * Self.zPanScale)
        if viewMode != .sideLevelHistory2D {
            xPanFrac = clampPan(xPanFrac + Float(-delta.width) * Self.xPanScale)
        }
    }

    private func resetCamera() {
        withAnimation(.easeInOut(duration: 0.25)) {
            pitch = Self.defaultPitch
            yaw = Self.defaultYaw
            zoom = Self.defaultZoom
            zOffsetDB = Self.defaultZOffsetDB
            xPanFrac = Self.defaultXPanFrac
            crosshair = nil
            anchor = nil
            pickerEnabled = false
        }
    }

    private func togglePicker() {
        guard inPickerMode else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            pickerEnabled.toggle()
            if !pickerEnabled {
                crosshair = nil
                anchor = nil
            }
        }
    }

    private var accessibilityDescription: String {
        if dataSet.isEmpty { return "Wasserfall: keine Daten" }
        return "Wasserfall, \(viewModeLabel), \(dataSet.slices.count) Slices, \(formatDuration(dataSet.duration))"
    }

    // MARK: Draw entry point

    private func draw(in bounds: CGRect, context: inout GraphicsContext) {
        guard !dataSet.isEmpty else { return }

        // Margins reserve space for axis labels OUTSIDE the plot area. The
        // analysis layout widens the right margin to host the dB colorbar.
        let leftMargin: CGFloat = 42
        let rightMargin: CGFloat = options.analysisLayout ? 56 : 12
        let topMargin: CGFloat = 22
        let bottomMargin: CGFloat = 36
        let plot = CGRect(
            x: bounds.minX + leftMargin,
            y: bounds.minY + topMargin,
            width: max(1, bounds.width - leftMargin - rightMargin),
            height: max(1, bounds.height - topMargin - bottomMargin)
        )

        // Clip the scene to the plot rect — without this, content pans /
        // projects outside `plot` and paints over the axis labels.
        var sceneContext = context
        sceneContext.clip(to: Path(plot))
        if viewMode == .topDown2D {
            // True filled frequency×time heatmap (color = level) — the
            // standard, legible spectrogram surface for measurement.
            drawHeatmap(plot: plot, context: &sceneContext)
        } else {
            drawUnifiedScene(plot: plot, context: &sceneContext)
        }
        if viewMode == .topDown2D {
            drawGrid(plot: plot, context: &sceneContext)
        }
        if let t = highlightedTime, t.isFinite, t >= 0, dataSet.duration > 0 {
            drawPlayhead3D(time: t, plot: plot, context: &sceneContext)
        }

        // Labels render OUTSIDE the clip so they stay visible regardless
        // of plot interior. Crosshair lives in the un-clipped layer too —
        // the readout pill should not be clipped by the plot rect.
        drawLabels(plot: plot, bounds: bounds, context: &context)

        if options.analysisLayout {
            drawColorbar(bounds: bounds, plot: plot, context: &context)
            drawPeakPanel(plot: plot, context: &context)
        }

        if pickerEnabled, inPickerMode, let position = crosshair {
            drawCrosshair(at: position, plot: plot, context: &context)
        }
    }

    // ========================================================================
    // MARK: - Unified 3D pipeline
    // ========================================================================

    /// Renders the waterfall as a single 3D scene through a unified camera
    /// transform. World axes are centered around the origin so rotations
    /// behave predictably:
    /// - x: frequency (-0.5 = pan-left edge, +0.5 = pan-right edge)
    /// - y: amplitude (-0.5 = minDB, +0.5 = maxDB)
    /// - z: time      (-0.5 = oldest, +0.5 = newest)
    ///
    /// One `Path` per slice + one `stroke` per slice replaces the previous
    /// per-bin-segment approach (~100× fewer GPU/Canvas commands per frame).
    /// Amplitude detail is preserved through the world-Y axis displacement
    /// (oblique / side) and through the slice's age-tinted Turbo color.
    private func drawUnifiedScene(plot: CGRect, context: inout GraphicsContext) {
        let slices = dataSet.slices
        guard !slices.isEmpty,
              let firstSlice = slices.first,
              !firstSlice.magnitudes.isEmpty else { return }

        let pitchRad = Float(effectivePitch) * .pi / 2
        let yawRad   = Float(effectiveYaw) * .pi / 2
        let camera = WaterfallCameraProjection(pitchRad: pitchRad, yawRad: yawRad)

        let sliceCount = slices.count
        let lastIndex = sliceCount - 1
        let binCount = firstSlice.magnitudes.count
        let lastBinIndex = binCount - 1
        let panFrac = Float(effectiveXPanFrac)

        let plotCenterX = plot.midX
        let plotCenterY = plot.midY
        // Yaw mixes the frequency (x) and time (z) axes, expanding the projected
        // x range beyond [-0.5, 0.5]. Dividing by the expansion factor keeps the
        // full frequency span visible without side-clipping at any rotation angle.
        let yawExpansion = max(1.0, abs(cos(yawRad)) + abs(sin(yawRad)))
        let plotScaleX = plot.width * CGFloat(1.0 / yawExpansion)
        let plotScaleY = plot.height * effectiveZoom

        // Render-thinning: stroke at most `maxRenderedTraces` ridgelines so a
        // dense history doesn't collapse into a tangle. The newest slice is
        // always drawn; older ones are strided, and the oldest is kept as a
        // floor reference.
        let stride = max(1, Int(ceil(Double(sliceCount) / Double(options.maxRenderedTraces))))
        var rendered: [Int] = []
        var idx = lastIndex
        while idx >= 0 { rendered.append(idx); idx -= stride }
        if rendered.last != 0 { rendered.append(0) }
        // Painter's algorithm: far (smaller depth) first so near slices occlude.
        let drawOrder = rendered.sorted { a, b in
            let za = Float(a) / Float(max(lastIndex, 1)) - 0.5
            let zb = Float(b) / Float(max(lastIndex, 1)) - 0.5
            return camera.project(SIMD3(0, 0, za)).depth < camera.project(SIMD3(0, 0, zb)).depth
        }

        for displayIndex in drawOrder {
            let slice = slices[displayIndex]
            guard !slice.magnitudes.isEmpty else { continue }
            let zWorld = Float(displayIndex) / Float(max(lastIndex, 1)) - 0.5

            // Age 0 = newest, 1 = oldest. Aggressive fade keeps the front
            // ridgelines crisp while older ones recede into the background.
            let age = Float(lastIndex - displayIndex) / Float(max(lastIndex, 1))
            let baseOpacity = 0.10 + 0.90 * pow(Double(1 - age), 1.6)
            let lineWidth: CGFloat = (displayIndex == lastIndex) ? 1.8 : 1.0

            // Per-point amplitude colour: project each bin and remember its
            // normalized level, then stroke as colour-run sub-paths so the
            // hue tracks amplitude along the trace instead of one hue per slice.
            var points: [(point: CGPoint, level: Float)] = []
            points.reserveCapacity(binCount)
            for binIndex in 0..<binCount {
                let binFrac = Float(binIndex) / Float(max(lastBinIndex, 1))
                let xWorld = (binFrac - panFrac) - 0.5
                let level = normalizedLevel(slice.magnitudes[binIndex])
                let projected = camera.project(SIMD3(xWorld, level - 0.5, zWorld))
                points.append((CGPoint(
                    x: plotCenterX + CGFloat(projected.x) * plotScaleX,
                    y: plotCenterY + CGFloat(projected.y) * plotScaleY
                ), level))
            }
            strokeAmplitudeColored(points: points, baseOpacity: baseOpacity, lineWidth: lineWidth, context: &context)
        }

        // Max-hold / average overlay — only meaningful in the oblique mode
        // where x = frequency and y = level. Drawn on the front plane.
        if options.showStatistics, viewMode == .oblique3D {
            let mags = slices.map { $0.magnitudes }
            let maxHold = WaterfallAnalysis.maxHold(slices: mags)
            if !maxHold.isEmpty {
                drawSpectrumCurve(maxHold, zWorld: 0.5, color: .white.opacity(0.85), lineWidth: 1.3,
                                  camera: camera, plotCenterX: plotCenterX, plotCenterY: plotCenterY,
                                  plotScaleX: plotScaleX, plotScaleY: plotScaleY,
                                  panFrac: panFrac, lastBinIndex: lastBinIndex, context: &context)
            }
            let avg = WaterfallAnalysis.average(slices: mags)
            if !avg.isEmpty {
                drawSpectrumCurve(avg, zWorld: 0.5, color: .white.opacity(0.40), lineWidth: 1.0,
                                  camera: camera, plotCenterX: plotCenterX, plotCenterY: plotCenterY,
                                  plotScaleX: plotScaleX, plotScaleY: plotScaleY,
                                  panFrac: panFrac, lastBinIndex: lastBinIndex, context: &context)
            }
        }

        // Optional amplitude-coloured peak dots (opt-in — a major source of
        // clutter). Skipped in side mode where x is time, not frequency.
        guard options.showPeaks, viewMode != .sideLevelHistory2D else { return }
        for displayIndex in drawOrder {
            let slice = slices[displayIndex]
            // Interior local maxima require at least 3 bins; fewer would make the
            // `1..<mags.count - 1` peak loop trap (e.g. count == 1 -> 1..<0).
            guard slice.magnitudes.count > 2 else { continue }
            let zWorld = Float(displayIndex) / Float(max(lastIndex, 1)) - 0.5
            let age = Float(lastIndex - displayIndex) / Float(max(lastIndex, 1))
            let peakOpacity = Double(0.50 + 0.50 * (1 - age))
            let mags = slice.magnitudes
            let sliceAvg = mags.reduce(0.0, +) / Float(mags.count)

            var peaks: [(binIndex: Int, level: Float)] = []
            for i in 1..<mags.count - 1
                where mags[i] > mags[i - 1] && mags[i] > mags[i + 1] && mags[i] > sliceAvg + 3 {
                let norm = normalizedLevel(mags[i])
                if norm >= 0.35 { peaks.append((i, norm)) }
            }
            let dotRadius: CGFloat = displayIndex == lastIndex ? 3.0 : 2.0

            for peak in peaks.sorted(by: { $0.level > $1.level }).prefix(8) {
                let binFrac = Float(peak.binIndex) / Float(max(lastBinIndex, 1))
                let projected = camera.project(SIMD3(
                    (binFrac - panFrac) - 0.5,
                    peak.level - 0.5,
                    zWorld
                ))
                let screen = CGPoint(
                    x: plotCenterX + CGFloat(projected.x) * plotScaleX,
                    y: plotCenterY + CGFloat(projected.y) * plotScaleY
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: screen.x - dotRadius,
                                          y: screen.y - dotRadius,
                                          width: dotRadius * 2,
                                          height: dotRadius * 2)),
                    with: .color(TurboColormap.color(for: peak.level).opacity(peakOpacity))
                )
            }
        }
    }

    /// Strokes a polyline whose colour tracks the per-point normalized level.
    /// Consecutive points sharing a quantized Turbo bucket are stroked as one
    /// sub-path, bounding the command count (≤ buckets per slice) while still
    /// encoding amplitude along the trace.
    private func strokeAmplitudeColored(points: [(point: CGPoint, level: Float)],
                                        baseOpacity: Double,
                                        lineWidth: CGFloat,
                                        context: inout GraphicsContext) {
        guard points.count > 1 else { return }
        let buckets = 16
        func bucket(_ v: Float) -> Int { min(buckets - 1, max(0, Int(v * Float(buckets)))) }

        var path = Path()
        path.move(to: points[0].point)
        var runBucket = bucket(points[0].level)
        for i in 1..<points.count {
            path.addLine(to: points[i].point)
            let b = bucket(points[i].level)
            if b != runBucket || i == points.count - 1 {
                let t = (Float(runBucket) + 0.5) / Float(buckets)
                context.stroke(path, with: .color(TurboColormap.color(for: t).opacity(baseOpacity)), lineWidth: lineWidth)
                path = Path()
                path.move(to: points[i].point)
                runBucket = b
            }
        }
    }

    /// Projects a single spectrum (frequency → level) onto the given time
    /// plane and strokes it as one polyline. Used for the max-hold / average
    /// overlays in the oblique mode.
    private func drawSpectrumCurve(_ magnitudes: [Float],
                                   zWorld: Float,
                                   color: Color,
                                   lineWidth: CGFloat,
                                   camera: WaterfallCameraProjection,
                                   plotCenterX: CGFloat,
                                   plotCenterY: CGFloat,
                                   plotScaleX: CGFloat,
                                   plotScaleY: CGFloat,
                                   panFrac: Float,
                                   lastBinIndex: Int,
                                   context: inout GraphicsContext) {
        var path = Path()
        for bin in 0..<magnitudes.count {
            let binFrac = Float(bin) / Float(max(lastBinIndex, 1))
            let xWorld = (binFrac - panFrac) - 0.5
            let yWorld = normalizedLevel(magnitudes[bin]) - 0.5
            let projected = camera.project(SIMD3(xWorld, yWorld, zWorld))
            let pt = CGPoint(x: plotCenterX + CGFloat(projected.x) * plotScaleX,
                             y: plotCenterY + CGFloat(projected.y) * plotScaleY)
            if bin == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    // ========================================================================
    // MARK: - Top-down heatmap
    // ========================================================================

    /// Filled frequency×time heatmap. Each cell is coloured by its level via
    /// the Turbo LUT — the standard, legible spectrogram surface. Rows/columns
    /// are downsampled to ≈1 cell per pixel so the command count stays bounded
    /// regardless of slice / bin count.
    private func drawHeatmap(plot: CGRect, context: inout GraphicsContext) {
        let slices = dataSet.slices
        guard let first = slices.first, !first.magnitudes.isEmpty else { return }
        let binCount = first.magnitudes.count
        let panFrac = effectiveXPanFrac

        let rows = min(slices.count, max(40, Int(plot.height)))
        let cols = min(binCount, max(64, Int(plot.width)))
        guard rows > 0, cols > 0 else { return }
        let cellW = plot.width / CGFloat(cols)
        let cellH = plot.height / CGFloat(rows)

        for row in 0..<rows {
            // Row 0 = top = oldest; last row = bottom = newest ("aktuell").
            let sliceFrac = rows > 1 ? Float(row) / Float(rows - 1) : 0
            let sliceIdx = min(slices.count - 1, max(0, Int((sliceFrac * Float(slices.count - 1)).rounded())))
            let mags = slices[sliceIdx].magnitudes
            guard !mags.isEmpty else { continue }
            let y = plot.minY + CGFloat(row) * cellH
            let lastMagIndex = mags.count - 1

            for col in 0..<cols {
                // Column maps to the panned frequency window [pan, pan+1].
                let centerFrac = (Float(col) + 0.5) / Float(cols)
                let binFracWindow = centerFrac + panFrac
                if binFracWindow < 0 || binFracWindow > 1 { continue }
                let binIdx = min(lastMagIndex, max(0, Int((binFracWindow * Float(lastMagIndex)).rounded())))
                let norm = normalizedLevel(mags[binIdx])
                if norm <= 0.002 { continue }   // leave the near-floor black
                let rect = CGRect(x: plot.minX + CGFloat(col) * cellW,
                                  y: y,
                                  width: cellW + 0.75,
                                  height: cellH + 0.75)
                context.fill(Path(rect), with: .color(TurboColormap.color(for: norm)))
            }
        }
    }

    /// Frequency (vertical) and time (horizontal) gridlines for the heatmap.
    private func drawGrid(plot: CGRect, context: inout GraphicsContext) {
        guard viewMode == .topDown2D else { return }
        let panFrac = effectiveXPanFrac
        let lineColor = Color.white.opacity(0.12)

        for f in WaterfallAnalysis.frequencyTicks(lo: visibleLeftEdgeFreq, hi: visibleRightEdgeFreq) {
            let colFrac = binFrac(forFrequency: f) - CGFloat(panFrac)
            guard colFrac >= 0, colFrac <= 1 else { continue }
            let x = plot.minX + colFrac * plot.width
            var p = Path()
            p.move(to: CGPoint(x: x, y: plot.minY))
            p.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(p, with: .color(lineColor), lineWidth: 0.5)
            // Tick labels only in the roomy analysis layout, and away from the
            // edges where the corner frequency labels already live.
            if options.analysisLayout, colFrac > 0.06, colFrac < 0.94 {
                drawText(formatHz(f), at: CGPoint(x: x, y: plot.maxY + 12), anchor: .center, context: &context)
            }
        }

        for frac in stride(from: 0.0, through: 1.0, by: 0.25) {
            let y = plot.minY + CGFloat(frac) * plot.height
            var p = Path()
            p.move(to: CGPoint(x: plot.minX, y: y))
            p.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(p, with: .color(lineColor), lineWidth: 0.5)
        }
    }

    // ========================================================================
    // MARK: - Colorbar legend + peak panel
    // ========================================================================

    /// Vertical Turbo dB colorbar in the right margin with min / mid / max
    /// tick labels — lets the heatmap colour be read quantitatively.
    private func drawColorbar(bounds: CGRect, plot: CGRect, context: inout GraphicsContext) {
        let barWidth: CGFloat = 10
        let barX = plot.maxX + 10
        let barRect = CGRect(x: barX, y: plot.minY, width: barWidth, height: plot.height)
        let steps = 64
        let stepH = plot.height / CGFloat(steps)
        for i in 0..<steps {
            let t = Float(i) / Float(steps - 1)            // 0 = bottom, 1 = top
            let y = barRect.maxY - CGFloat(i + 1) * stepH
            context.fill(Path(CGRect(x: barX, y: y, width: barWidth, height: stepH + 0.75)),
                         with: .color(TurboColormap.color(for: t)))
        }
        context.stroke(Path(barRect), with: .color(.white.opacity(0.25)), lineWidth: 0.5)

        let minDB = dataSet.minDB + effectiveZOffsetDB
        let maxDB = dataSet.maxDB + effectiveZOffsetDB
        let mid = (minDB + maxDB) / 2
        let labelX = barX + barWidth + 3
        drawText("\(Int(maxDB.rounded()))", at: CGPoint(x: labelX, y: plot.minY + 4), anchor: .leading, context: &context)
        drawText("\(Int(mid.rounded()))", at: CGPoint(x: labelX, y: plot.midY), anchor: .leading, context: &context)
        drawText("\(Int(minDB.rounded()))", at: CGPoint(x: labelX, y: plot.maxY - 4), anchor: .leading, context: &context)
        drawText("dB", at: CGPoint(x: barX - 1, y: plot.minY - 11), anchor: .leading, context: &context)
    }

    /// Persistent top-peaks readout for the cursor slice (or the newest slice
    /// when no cursor is placed). Replaces the transient peak dots as the main
    /// measurement aid.
    private func drawPeakPanel(plot: CGRect, context: inout GraphicsContext) {
        let slices = dataSet.slices
        guard !slices.isEmpty else { return }

        // Pick the analysed slice: the cursor's time row in top-down/side when
        // the picker is active, otherwise the newest slice.
        let analysed: WaterfallSlice = {
            if pickerEnabled, inPickerMode, let c = crosshair {
                let yFrac = (c.y - plot.minY) / max(1, plot.height)
                let clamped = max(0, min(1, Double(yFrac)))
                let sliceIdx = Int((clamped * Double(slices.count - 1)).rounded())
                return slices[min(max(0, sliceIdx), slices.count - 1)]
            }
            return slices[slices.count - 1]
        }()
        guard !analysed.magnitudes.isEmpty else { return }

        let peaks = WaterfallAnalysis.peaks(magnitudes: analysed.magnitudes,
                                            frequencies: dataSet.frequencies,
                                            limit: 5)
        guard !peaks.isEmpty else { return }

        let zShift = effectiveZOffsetDB
        let lineH: CGFloat = 14
        let panelW: CGFloat = 122
        let panelH: CGFloat = lineH * CGFloat(peaks.count + 1) + 10
        let panelX = plot.maxX - panelW - 6
        let panelY = plot.minY + 6
        context.fill(Path(roundedRect: CGRect(x: panelX, y: panelY, width: panelW, height: panelH), cornerRadius: 6),
                     with: .color(.black.opacity(0.55)))
        drawText("Spitzen", at: CGPoint(x: panelX + 8, y: panelY + 6), anchor: .topLeading, context: &context)
        for (i, peak) in peaks.enumerated() {
            let y = panelY + 6 + lineH * CGFloat(i + 1)
            let line = String(format: "%@   %.0f dB", formatHz(peak.frequency), peak.level + zShift)
            drawText(line, at: CGPoint(x: panelX + 8, y: y), anchor: .topLeading, context: &context)
        }
    }

    /// Draws a horizontal segment in world space at the time matching
    /// `highlightedTime`. Goes through the same `CameraProjection` so it
    /// stays oriented correctly across all view modes (horizontal line on
    /// top-down, vertical line on side, oblique cutaway in 3D).
    private func drawPlayhead3D(time: TimeInterval, plot: CGRect, context: inout GraphicsContext) {
        let t = Float(max(0, min(1, time / dataSet.duration)))
        let zWorld = t - 0.5
        let pitchRad = Float(effectivePitch) * .pi / 2
        let yawRad   = Float(effectiveYaw) * .pi / 2
        let camera = WaterfallCameraProjection(pitchRad: pitchRad, yawRad: yawRad)

        let leftWorld  = SIMD3<Float>(-0.5, 0, zWorld)
        let rightWorld = SIMD3<Float>(+0.5, 0, zWorld)
        let left  = camera.project(leftWorld)
        let right = camera.project(rightWorld)

        let plotCenterX = plot.midX
        let plotCenterY = plot.midY
        let yawExpansion = max(1.0, abs(cos(yawRad)) + abs(sin(yawRad)))
        let scaleX = plot.width * CGFloat(1.0 / yawExpansion)
        let scaleY = plot.height * effectiveZoom

        let p0 = CGPoint(x: plotCenterX + CGFloat(left.x) * scaleX,
                         y: plotCenterY + CGFloat(left.y) * scaleY)
        let p1 = CGPoint(x: plotCenterX + CGFloat(right.x) * scaleX,
                         y: plotCenterY + CGFloat(right.y) * scaleY)
        var path = Path()
        path.move(to: p0)
        path.addLine(to: p1)
        context.stroke(path, with: .color(.white.opacity(0.78)), lineWidth: 1.4)
    }

    // ========================================================================
    // MARK: - Crosshair picker
    // ========================================================================

    private func drawCrosshair(at position: CGPoint, plot: CGRect, context: inout GraphicsContext) {
        let snapped = snappedCrosshair(position, plot: plot)
        let x = max(plot.minX, min(plot.maxX, snapped.x))
        let y = max(plot.minY, min(plot.maxY, snapped.y))

        // Anchor (cursor B): dimmer yellow guides for the Δ measurement.
        if let anchorPosition = anchor {
            let ax = max(plot.minX, min(plot.maxX, anchorPosition.x))
            let ay = max(plot.minY, min(plot.maxY, anchorPosition.y))
            let anchorColor = Color.yellow.opacity(0.7)
            var ah = Path()
            ah.move(to: CGPoint(x: plot.minX, y: ay))
            ah.addLine(to: CGPoint(x: plot.maxX, y: ay))
            context.stroke(ah, with: .color(anchorColor), lineWidth: 0.5)
            var av = Path()
            av.move(to: CGPoint(x: ax, y: plot.minY))
            av.addLine(to: CGPoint(x: ax, y: plot.maxY))
            context.stroke(av, with: .color(anchorColor), lineWidth: 0.5)
            context.fill(Path(ellipseIn: CGRect(x: ax - 2.5, y: ay - 2.5, width: 5, height: 5)),
                         with: .color(.yellow))
        }

        let lineColor = Color.white.opacity(0.65)
        var hLine = Path()
        hLine.move(to: CGPoint(x: plot.minX, y: y))
        hLine.addLine(to: CGPoint(x: plot.maxX, y: y))
        context.stroke(hLine, with: .color(lineColor), lineWidth: 0.5)

        var vLine = Path()
        vLine.move(to: CGPoint(x: x, y: plot.minY))
        vLine.addLine(to: CGPoint(x: x, y: plot.maxY))
        context.stroke(vLine, with: .color(lineColor), lineWidth: 0.5)

        let dotRect = CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)
        context.fill(Path(ellipseIn: dotRect), with: .color(.white))

        let readout: String = {
            if let anchorPosition = anchor {
                return deltaReadout(a: CGPoint(x: x, y: y), b: anchorPosition, plot: plot)
            }
            return crosshairReadout(at: CGPoint(x: x, y: y), plot: plot)
        }()
        let readoutWidth = estimatedReadoutWidth(for: readout)
        let textPoint = readoutAnchor(near: CGPoint(x: x, y: y), plot: plot, width: readoutWidth)
        let pillRect = CGRect(
            x: textPoint.x - 4,
            y: textPoint.y - 2,
            width: readoutWidth + 8,
            height: 16
        )
        context.fill(
            Path(roundedRect: pillRect, cornerRadius: 4),
            with: .color(.black.opacity(0.55))
        )
        drawText(readout, at: textPoint, anchor: .topLeading, context: &context)
    }

    private func crosshairReadout(at point: CGPoint, plot: CGRect) -> String {
        let xFrac = (point.x - plot.minX) / max(1, plot.width)
        let yFrac = (point.y - plot.minY) / max(1, plot.height)

        let panFrac = CGFloat(effectiveXPanFrac)
        let zShift = effectiveZOffsetDB

        switch viewMode {
        case .topDown2D:
            let binFrac = xFrac + panFrac
            let freqHz = frequencyAt(binFrac: binFrac)
            let timeAgo = max(0, dataSet.duration * (1 - Double(yFrac)))
            let level = sampledLevel(binFrac: binFrac, sliceFrac: yFrac)
            return String(format: "%@   %@   %.0f dB",
                          formatHz(freqHz), formatSec(timeAgo), level + zShift)
        case .sideLevelHistory2D:
            let timeAgo = max(0, dataSet.duration * (1 - Double(xFrac)))
            let range = max(1, dataSet.maxDB - dataSet.minDB)
            let level = (dataSet.minDB + zShift) + Float(1 - yFrac) * range
            return String(format: "%@   %.1f dB", formatSec(timeAgo), level)
        case .oblique3D:
            return ""
        }
    }

    /// Snaps the crosshair to the nearest frequency bin/band center in the
    /// top-down heatmap when the data is banded (1/3-octave / Bark / octave),
    /// so the cursor lands on a real band rather than between two.
    private func snappedCrosshair(_ point: CGPoint, plot: CGRect) -> CGPoint {
        guard viewMode == .topDown2D, options.spectrumMode != .continuous else { return point }
        let count = dataSet.frequencies.count
        guard count > 1 else { return point }
        let colFrac = Float((point.x - plot.minX) / max(1, plot.width))
        let binFracWindow = colFrac + effectiveXPanFrac
        let binIdx = Int((binFracWindow * Float(count - 1)).rounded())
        let snappedBinFrac = Float(min(max(0, binIdx), count - 1)) / Float(count - 1)
        let snappedX = plot.minX + CGFloat(snappedBinFrac - effectiveXPanFrac) * plot.width
        return CGPoint(x: snappedX, y: point.y)
    }

    /// Δf / Δt / ΔdB between the live cursor (A) and the pinned anchor (B).
    private func deltaReadout(a: CGPoint, b: CGPoint, plot: CGRect) -> String {
        let ax = (a.x - plot.minX) / max(1, plot.width)
        let ay = (a.y - plot.minY) / max(1, plot.height)
        let bx = (b.x - plot.minX) / max(1, plot.width)
        let by = (b.y - plot.minY) / max(1, plot.height)
        let panFrac = CGFloat(effectiveXPanFrac)

        switch viewMode {
        case .topDown2D:
            let fa = frequencyAt(binFrac: ax + panFrac)
            let fb = frequencyAt(binFrac: bx + panFrac)
            let la = sampledLevel(binFrac: ax + panFrac, sliceFrac: ay) + effectiveZOffsetDB
            let lb = sampledLevel(binFrac: bx + panFrac, sliceFrac: by) + effectiveZOffsetDB
            let dt = dataSet.duration * Double(by - ay)
            return String(format: "Δ%@  Δ%@  %+.0f dB", formatHz(abs(fa - fb)), formatSec(abs(dt)), la - lb)
        case .sideLevelHistory2D:
            let dt = dataSet.duration * Double(bx - ax)
            let range = max(1, dataSet.maxDB - dataSet.minDB)
            let la = Float(1 - ay) * range
            let lb = Float(1 - by) * range
            return String(format: "Δ%@  %+.1f dB", formatSec(abs(dt)), la - lb)
        case .oblique3D:
            return ""
        }
    }

    /// Inverse of `frequencyAt`: the fractional bin position (0…1) of a given
    /// frequency on the (monotonic) frequency axis.
    private func binFrac(forFrequency frequency: Float) -> CGFloat {
        let freqs = dataSet.frequencies
        guard freqs.count > 1, let lowest = freqs.first, let highest = freqs.last else { return 0 }
        if frequency <= lowest { return 0 }
        if frequency >= highest { return 1 }
        var low = 0
        var high = freqs.count - 1
        while low < high {
            let mid = (low + high) / 2
            if freqs[mid] < frequency { low = mid + 1 } else { high = mid }
        }
        let upper = low
        let lower = max(0, upper - 1)
        let span = freqs[upper] - freqs[lower]
        let t = span > 0 ? (frequency - freqs[lower]) / span : 0
        let pos = Float(lower) + t
        return CGFloat(pos / Float(freqs.count - 1))
    }

    /// One source of truth for readout width — same estimator used both
    /// for sizing the pill background and for overflow detection so they
    /// can't disagree.
    private func estimatedReadoutWidth(for text: String) -> CGFloat {
        return CGFloat(text.count) * 5.8
    }

    private func readoutAnchor(near point: CGPoint, plot: CGRect, width: CGFloat) -> CGPoint {
        let textHeight: CGFloat = 14
        let offset: CGFloat = 8

        var anchor = CGPoint(x: point.x + offset, y: point.y + offset)
        if anchor.x + width > plot.maxX {
            anchor.x = point.x - offset - width
        }
        if anchor.y + textHeight > plot.maxY {
            anchor.y = point.y - offset - textHeight
        }
        return anchor
    }

    // ========================================================================
    // MARK: - Labels
    // ========================================================================

    private func drawLabels(plot: CGRect, bounds: CGRect, context: inout GraphicsContext) {
        let topLabelY = bounds.minY + 10
        let bottomLabelY = bounds.maxY - 10

        // Mode tag (top-left) + duration (top-right) — symbol-cached.
        drawSymbol(.viewMode,
                   at: CGPoint(x: bounds.minX + 4, y: topLabelY),
                   anchor: .leading, context: &context)
        drawSymbol(.duration,
                   at: CGPoint(x: bounds.maxX - 4, y: topLabelY),
                   anchor: .trailing, context: &context)

        switch viewMode {
        case .oblique3D:
            drawSymbol(.maxDB,
                       at: CGPoint(x: plot.minX - 4, y: plot.minY + 6),
                       anchor: .trailing, context: &context)
            drawSymbol(.minDB,
                       at: CGPoint(x: plot.minX - 4, y: plot.maxY - 6),
                       anchor: .trailing, context: &context)
            drawSymbol(.leftFreq,
                       at: CGPoint(x: plot.minX, y: bottomLabelY),
                       anchor: .leading, context: &context)
            drawSymbol(.rightFreq,
                       at: CGPoint(x: plot.maxX, y: bottomLabelY),
                       anchor: .trailing, context: &context)

        case .topDown2D:
            // "aktuell"/"älter" are static strings — CoreText's own cache handles them.
            drawText("aktuell",
                     at: CGPoint(x: plot.minX - 4, y: plot.maxY - 6),
                     anchor: .trailing, context: &context)
            drawText("älter",
                     at: CGPoint(x: plot.minX - 4, y: plot.minY + 6),
                     anchor: .trailing, context: &context)
            drawSymbol(.leftFreq,
                       at: CGPoint(x: plot.minX, y: bottomLabelY),
                       anchor: .leading, context: &context)
            drawSymbol(.rightFreq,
                       at: CGPoint(x: plot.maxX, y: bottomLabelY),
                       anchor: .trailing, context: &context)

        case .sideLevelHistory2D:
            drawSymbol(.maxDB,
                       at: CGPoint(x: plot.minX - 4, y: plot.minY + 6),
                       anchor: .trailing, context: &context)
            drawSymbol(.minDB,
                       at: CGPoint(x: plot.minX - 4, y: plot.maxY - 6),
                       anchor: .trailing, context: &context)
            drawText("älter",
                     at: CGPoint(x: plot.minX, y: bottomLabelY),
                     anchor: .leading, context: &context)
            drawText("aktuell",
                     at: CGPoint(x: plot.maxX, y: bottomLabelY),
                     anchor: .trailing, context: &context)
        }
    }

    private func drawText(_ value: String, at point: CGPoint, anchor: UnitPoint, context: inout GraphicsContext) {
        let text = Text(value).font(.caption2).foregroundColor(.white.opacity(0.72))
        context.draw(text, at: point, anchor: anchor)
    }

    // MARK: Helpers

    private func normalizedLevel(_ value: Float) -> Float {
        let zShift = effectiveZOffsetDB
        let minDB = dataSet.minDB + zShift
        let maxDB = dataSet.maxDB + zShift
        let range = max(1, maxDB - minDB)
        var normalized = max(0, min(1, (value - minDB) / range))
        // Soft-knee: fade the bottom 6 dB of the display range smoothly to
        // black using a Hermite curve. This mirrors the spectrogram adapter's
        // kneeWidth mechanism so both widgets handle the floor boundary consistently.
        let kneeNorm: Float = min(0.5, 6.0 / range)
        if normalized > 0 && normalized < kneeNorm {
            let t = normalized / kneeNorm
            normalized *= t * t * (3.0 - 2.0 * t)
        }
        return normalized
    }

    private func frequencyAt(binFrac: CGFloat) -> Float {
        let freqs = dataSet.frequencies
        guard !freqs.isEmpty else { return 0 }
        guard freqs.count > 1 else { return freqs[0] }
        let clamped = max(0, min(1, binFrac))
        // Linearly interpolate between adjacent bins so edge labels track the
        // exact window position instead of snapping to the nearest bin center.
        let pos = clamped * CGFloat(freqs.count - 1)
        let lower = Int(pos)
        let upper = min(lower + 1, freqs.count - 1)
        let t = Float(pos - CGFloat(lower))
        return freqs[lower] + (freqs[upper] - freqs[lower]) * t
    }

    private func sampledLevel(binFrac: CGFloat, sliceFrac: CGFloat) -> Float {
        let slices = dataSet.slices
        guard !slices.isEmpty else { return dataSet.minDB }
        let sliceClamped = max(0, min(1, sliceFrac))
        let sliceIdx = Int((sliceClamped * CGFloat(slices.count - 1)).rounded())
        let slice = slices[min(max(0, sliceIdx), slices.count - 1)]
        guard !slice.magnitudes.isEmpty else { return dataSet.minDB }
        let binClamped = max(0, min(1, binFrac))
        let binIdx = Int((binClamped * CGFloat(slice.magnitudes.count - 1)).rounded())
        return slice.magnitudes[min(max(0, binIdx), slice.magnitudes.count - 1)]
    }

    private func formatHz(_ hz: Float) -> String {
        if hz >= 1000 { return String(format: "%.1f kHz", hz / 1000) }
        return String(format: "%.0f Hz", hz)
    }

    private func formatSec(_ seconds: Double) -> String {
        if seconds >= 1 { return String(format: "%.1fs", seconds) }
        return String(format: "%.0fms", seconds * 1000)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration >= 60 {
            let m = Int(duration) / 60
            let s = Int(duration) % 60
            return String(format: "%02d:%02d", m, s)
        }
        return String(format: "%.1fs", duration)
    }
}

// ============================================================================
// MARK: - History store (audio-rate ingest, throttled rebuild)
// ============================================================================

/// Holds the rolling waterfall history and rebuilds the displayed
/// `WaterfallDataSet` at a fixed cadence. Splitting this out of
/// `WaterfallWidget` lets the SwiftUI body re-render only when the throttled
/// dataset actually changes (≈8 Hz) instead of on every audio frame
/// (~86 Hz). Storage is a `RingBuffer` so eviction is O(1) per frame.
@MainActor
final class WaterfallHistoryStore: ObservableObject {

    struct Settings: Equatable {
        var capacity: Int
        var sliceCount: Int
        var minDB: Float
        var maxDB: Float
        var rebuildInterval: TimeInterval
        var targetFrequencyCount: Int

        static let `default` = Settings(
            capacity: 720,
            sliceCount: WidgetSettings.defaultWaterfallSliceCount,
            minDB: WidgetSettings.defaultWaterfallMinDB,
            maxDB: WidgetSettings.defaultWaterfallMaxDB,
            rebuildInterval: 0.12,
            targetFrequencyCount: WidgetSettings.defaultWaterfallTargetFrequencyCount
        )
    }

    private struct Frame {
        let magnitudes: [Float]
        let timestamp: Date
    }

    @Published private(set) var dataSet: WaterfallDataSet = WaterfallDataSet.empty

    private(set) var settings: Settings
    private var history: RingBuffer<Frame>
    private var lastFrequencies: [Float] = []
    private var lastBinCount: Int = 0
    private var lastRebuild: TimeInterval = 0

    init(settings: Settings = .default) {
        self.settings = settings
        self.history = RingBuffer(capacity: max(8, settings.capacity))
        self.dataSet = WaterfallDataSet.empty.with(minDB: settings.minDB, maxDB: settings.maxDB)
    }

    func update(settings new: Settings) {
        // Capture all change flags BEFORE reassigning `settings`, otherwise the
        // comparisons below would always be false (we'd be comparing `new`
        // against itself).
        let capacityChanged = new.capacity != settings.capacity
        let dbChanged = new.minDB != settings.minDB || new.maxDB != settings.maxDB
        let sliceCountChanged = new.sliceCount != settings.sliceCount
        settings = new
        if capacityChanged {
            history = RingBuffer(capacity: max(8, new.capacity))
            lastBinCount = 0
            lastFrequencies = []
            dataSet = WaterfallDataSet.empty.with(minDB: new.minDB, maxDB: new.maxDB)
            return
        }
        if dbChanged || sliceCountChanged {
            rebuild(force: true)
        }
    }

    func reset() {
        history.removeAll()
        lastBinCount = 0
        lastFrequencies = []
        dataSet = WaterfallDataSet.empty.with(minDB: settings.minDB, maxDB: settings.maxDB)
    }

    func append(magnitudes: [Float], frequencies: [Float], timestamp: Date) {
        guard !magnitudes.isEmpty, !frequencies.isEmpty else { return }
        // Bin-count drift (e.g. FFT-size change, mel/linear toggle) makes
        // older frames meaningless against the new axis. Drop history
        // rather than rendering an axis-misaligned stripe.
        let axisDrift = lastBinCount != 0 && magnitudes.count != lastBinCount
        if axisDrift {
            history.removeAll()
        }
        history.append(Frame(magnitudes: magnitudes, timestamp: timestamp))
        lastBinCount = magnitudes.count
        lastFrequencies = frequencies
        if axisDrift {
            // Rebuild immediately — throttling would leave the previous axis on screen.
            lastRebuild = 0
        }
        rebuildIfDue()
    }

    private func rebuildIfDue() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastRebuild >= settings.rebuildInterval else { return }
        lastRebuild = now
        rebuild(force: false)
    }

    private func rebuild(force: Bool) {
        let frames = history.inOrder()
        guard !frames.isEmpty, !lastFrequencies.isEmpty else {
            if !dataSet.isEmpty {
                dataSet = WaterfallDataSet.empty.with(minDB: settings.minDB, maxDB: settings.maxDB)
            }
            return
        }
        // Duration derived from frame timestamps — always honest about
        // what the visible slices actually cover.
        let span: TimeInterval = {
            guard let first = frames.first?.timestamp,
                  let last = frames.last?.timestamp else { return 0 }
            return max(0, last.timeIntervalSince(first))
        }()
        let magnitudes = frames.map { $0.magnitudes }
        dataSet = WaterfallDataBuilder.build(
            history: magnitudes,
            sourceFrequencies: lastFrequencies,
            duration: span,
            targetSliceCount: settings.sliceCount,
            targetFrequencyCount: settings.targetFrequencyCount,
            minDB: settings.minDB,
            maxDB: settings.maxDB
        )
    }
}

private extension WaterfallDataSet {
    static let empty = WaterfallDataSet(slices: [], frequencies: [], duration: 0, minDB: 30, maxDB: 110)

    func with(minDB: Float, maxDB: Float) -> WaterfallDataSet {
        WaterfallDataSet(slices: slices, frequencies: frequencies, duration: duration, minDB: minDB, maxDB: maxDB)
    }
}

// ============================================================================
// MARK: - Spectral frame selection (testable)
// ============================================================================

enum WaterfallSpectralFrame {
    /// Mel/visual magnitudes when present; otherwise band magnitudes for `freqWeighting`.
    static func magnitudesAndFrequencies(
        from data: SpectrogramData,
        freqWeighting: String
    ) -> (magnitudes: [Float], frequencies: [Float]) {
        if let visual = data.visualMagnitudes, !visual.isEmpty {
            return (visual, data.visualFrequencies ?? data.frequencies)
        }
        return (data.magnitudes(for: freqWeighting), data.frequencies)
    }
}

// ============================================================================
// MARK: - WaterfallWidget (data plumbing)
// ============================================================================

struct WaterfallWidget: View {
    private let audioEngine: AudioEngine
    var settings: [String: String]

    private let frequencyWeightingPublisher: Published<FrequencyWeighting>.Publisher

    @StateObject private var store = WaterfallHistoryStore()
    @State private var engineFrequencyWeighting: String

    init(audioEngine: AudioEngine, settings: [String: String]) {
        self.audioEngine = audioEngine
        self.settings = settings
        self.frequencyWeightingPublisher = audioEngine.$frequencyWeighting
        _engineFrequencyWeighting = State(initialValue: audioEngine.frequencyWeighting.rawValue)
    }

    private var useWidgetOverrides: Bool { WidgetSettings.usesWidgetOverrides(settings) }

    private var freqWeighting: String {
        if useWidgetOverrides {
            return settings["freqWeighting"] ?? engineFrequencyWeighting
        }
        return engineFrequencyWeighting
    }

    private var displaySettings: WaterfallDisplaySettings {
        WaterfallDisplaySettings.fromWidgetSettings(settings, engineWeighting: engineFrequencyWeighting)
    }

    /// History capacity sized for ~6 seconds at 86 Hz — long enough to
    /// give the time axis meaningful depth without paying for a huge
    /// ring buffer.
    private var capacity: Int {
        max(120, displaySettings.sliceCount * 6)
    }

    private var resolvedSettings: WaterfallHistoryStore.Settings {
        displaySettings.historyStoreSettings(capacity: capacity)
    }

    private static func appendSpectrogramFrame(
        _ data: SpectrogramData,
        to store: WaterfallHistoryStore,
        weighting: String,
        mode: WaterfallSpectrumMode
    ) {
        let frame = WaterfallSpectralFrame.magnitudesAndFrequencies(from: data, freqWeighting: weighting)
        let remapped = WaterfallDataBuilder.remapHistory(
            history: [frame.magnitudes],
            sourceFrequencies: frame.frequencies,
            mode: mode
        )
        guard let mapped = remapped.history.first, !mapped.isEmpty, !remapped.frequencies.isEmpty else { return }
        store.append(magnitudes: mapped, frequencies: remapped.frequencies, timestamp: data.timestamp)
    }

    @State private var showFullscreen = false

    /// Compact tile: heatmap when looking down, amplitude-coloured thinned
    /// ridgelines when oblique. The fullscreen cover uses the heatmap-first
    /// `.analysis` preset (colorbar, gridlines, peaks) over the same store.
    private var renderOptions: WaterfallRenderOptions {
        var options = WaterfallRenderOptions.widget
        options.showPeaks = displaySettings.showPeaks
        options.spectrumMode = displaySettings.spectrumMode
        return options
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WaterfallView(dataSet: store.dataSet, highlightedTime: nil, options: renderOptions)
                .onReceive(audioEngine.spectrogramSubject) { data in
                    let weighting = freqWeighting
                    let mode = displaySettings.spectrumMode
                    DispatchQueue.main.async { [weak store] in
                        guard let store else { return }
                        Self.appendSpectrogramFrame(data, to: store, weighting: weighting, mode: mode)
                    }
                }
                .onReceive(frequencyWeightingPublisher) { engineFrequencyWeighting = $0.rawValue }
                .onChange(of: resolvedSettings) { _, new in
                    store.update(settings: new)
                }
                .onChange(of: freqWeighting) { _, _ in
                    store.reset()
                }
                .onChange(of: displaySettings.spectrumMode) { _, _ in
                    store.reset()
                }
                .onAppear {
                    store.update(settings: resolvedSettings)
                    if let current = audioEngine.live.currentSpectrogramData {
                        Self.appendSpectrogramFrame(
                            current,
                            to: store,
                            weighting: freqWeighting,
                            mode: displaySettings.spectrumMode
                        )
                    }
                }
                .accessibilityIdentifier("waterfallWidget")
                .accessibilityLabel("Wasserfall")
                .accessibilityHint("Doppeltippen setzt die Ansicht zurück. In 2D-Ansicht Einzeltipp für Messwerte.")

            Button { showFullscreen = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.black.opacity(0.5)))
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .padding(8)
            .accessibilityLabel("Wasserfall vergrößern")
            .accessibilityIdentifier("waterfallExpandButton")
        }
        .innerCanvas(cornerRadius: 0)
        .fullScreenCover(isPresented: $showFullscreen) {
            // Share the SAME history store so the live measurement continues
            // seamlessly — the presenting tile stays in the hierarchy while the
            // cover is shown, so its subscription keeps feeding this store.
            WaterfallFullscreenView(
                store: store,
                options: .analysis(
                    spectrumMode: displaySettings.spectrumMode,
                    showPeaks: displaySettings.showPeaks,
                    showStatistics: true
                )
            )
        }
    }
}

private struct WaterfallFullscreenView: View {
    @Environment(\.dismiss) private var dismiss
    /// Shared with the presenting tile — keeps the rolling history (and thus
    /// the same live measurement) continuous across the fullscreen transition
    /// instead of spinning up an empty store that refills from scratch.
    @ObservedObject var store: WaterfallHistoryStore
    let options: WaterfallRenderOptions

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            WaterfallView(dataSet: store.dataSet, highlightedTime: nil, options: options)
                .ignoresSafeArea()
                .accessibilityIdentifier("waterfallWidgetFullscreen")

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(12)
            .accessibilityLabel("Wasserfall schließen")
        }
    }
}

// ============================================================================
// MARK: - Two-finger pan recognizer (UIKit bridge)
// ============================================================================
//
// SwiftUI's DragGesture is 1-finger only. To get a true 2-finger pan that
// coexists with the SwiftUI MagnifyGesture (pinch) and the 1-finger drag,
// we drop a transparent UIView into the view tree as an overlay and attach
// a UIPanGestureRecognizer with minimumNumberOfTouches = 2.
//
// The wrapping UIView only "claims" touch events when 2+ fingers are down
// — `hitTest` returns nil for 0–1 touches so events fall through to the
// SwiftUI layer beneath.

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

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            return true
        }
    }
}

private final class TwoFingerPassThroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let touchCount = event?.allTouches?.count ?? 0
        if touchCount >= 2 {
            return super.hitTest(point, with: event)
        }
        return nil
    }
}
