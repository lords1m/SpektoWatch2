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
// MARK: - WaterfallView (renderer)
// ============================================================================

struct WaterfallView: View {
    let dataSet: WaterfallDataSet
    /// When non-nil, draws a playhead bar at this position in the time axis.
    /// `nil` (live mode) suppresses the bar; recording-detail playback passes
    /// the current scrub time so the user sees where they are in the data.
    let highlightedTime: TimeInterval?

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

    @GestureState private var dragDelta: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var twoFingerDelta: CGSize = .zero

    // MARK: Constants

    private static let defaultPitch: CGFloat = 0.4
    private static let defaultYaw: CGFloat = 0.35
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
            // Tap ordering: count:2 must come BEFORE count:1 so SwiftUI's
            // disambiguation lets the double-tap window resolve first.
            .onTapGesture(count: 2, perform: resetCamera)
            .onTapGesture(count: 1, perform: togglePicker)
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
            pickerEnabled = false
        }
    }

    private func togglePicker() {
        guard inPickerMode else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            pickerEnabled.toggle()
            if !pickerEnabled { crosshair = nil }
        }
    }

    private var accessibilityDescription: String {
        if dataSet.isEmpty { return "Wasserfall: keine Daten" }
        return "Wasserfall, \(viewModeLabel), \(dataSet.slices.count) Slices, \(formatDuration(dataSet.duration))"
    }

    // MARK: Draw entry point

    private func draw(in bounds: CGRect, context: inout GraphicsContext) {
        guard !dataSet.isEmpty else { return }

        // Margins reserve space for axis labels OUTSIDE the plot area.
        let plot = CGRect(
            x: bounds.minX + 42,
            y: bounds.minY + 22,
            width: max(1, bounds.width - 54),
            height: max(1, bounds.height - 58)
        )

        // Clip the unified scene to the plot rect — without this, content
        // pans / projects outside `plot` and paints over the axis labels.
        var sceneContext = context
        sceneContext.clip(to: Path(plot))
        drawUnifiedScene(plot: plot, context: &sceneContext)
        if let t = highlightedTime, t.isFinite, t >= 0, dataSet.duration > 0 {
            drawPlayhead3D(time: t, plot: plot, context: &sceneContext)
        }

        // Labels render OUTSIDE the clip so they stay visible regardless
        // of plot interior. Crosshair lives in the un-clipped layer too —
        // the readout pill should not be clipped by the plot rect.
        drawLabels(plot: plot, bounds: bounds, context: &context)

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
        let camera = CameraProjection(pitchRad: pitchRad, yawRad: yawRad)

        let sliceCount = slices.count
        let lastIndex = sliceCount - 1
        let binCount = firstSlice.magnitudes.count
        let lastBinIndex = binCount - 1
        let panFrac = Float(effectiveXPanFrac)

        // Sort slices by post-rotation depth (painter's algorithm). The
        // closer-to-camera slice is drawn last and occludes farther ones.
        let drawOrder: [Int] = (0...lastIndex)
            .map { i -> (Int, Float) in
                let zWorld = Float(i) / Float(max(lastIndex, 1)) - 0.5
                return (i, camera.project(SIMD3(0, 0, zWorld)).depth)
            }
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }

        let plotCenterX = plot.midX
        let plotCenterY = plot.midY
        let plotScaleX = plot.width
        let plotScaleY = plot.height * effectiveZoom

        // In top-down mode the amplitude axis collapses — pixels can no
        // longer encode amplitude positionally, so we boost the per-slice
        // color saturation by routing the slice's PEAK amplitude through
        // the colormap instead of its age fraction.
        let topDownTint = (viewMode == .topDown2D)

        for displayIndex in drawOrder {
            let slice = slices[displayIndex]
            guard !slice.magnitudes.isEmpty else { continue }
            let zWorld = Float(displayIndex) / Float(max(lastIndex, 1)) - 0.5

            // Age 0 = newest, 1 = oldest. Old slices fade so the front of
            // the mountain range stays readable.
            let age = Float(lastIndex - displayIndex) / Float(max(lastIndex, 1))
            let baseOpacity = Double(0.30 + 0.70 * (1 - age))

            // Slice tint: in top-down mode use the slice's peak amplitude
            // so loud rows pop in the heatmap. Otherwise tint by recency
            // (newest = warm Turbo, oldest = cool).
            let tintT: Float = {
                if topDownTint {
                    let peak = slice.magnitudes.max() ?? dataSet.minDB
                    return normalizedLevel(peak)
                }
                return 0.20 + (1 - age) * 0.75 // 0.20 (cool) → 0.95 (warm)
            }()
            let strokeColor = TurboColormap.color(for: tintT)
                .opacity(baseOpacity)

            // Build the slice polyline as a single Path.
            var path = Path()
            for binIndex in 0..<binCount {
                let binFrac = Float(binIndex) / Float(max(lastBinIndex, 1))
                let xWorld = (binFrac - panFrac) - 0.5
                let yWorld = normalizedLevel(slice.magnitudes[binIndex]) - 0.5
                let projected = camera.project(SIMD3(xWorld, yWorld, zWorld))
                let screen = CGPoint(
                    x: plotCenterX + CGFloat(projected.x) * plotScaleX,
                    y: plotCenterY + CGFloat(projected.y) * plotScaleY
                )
                if binIndex == 0 {
                    path.move(to: screen)
                } else {
                    path.addLine(to: screen)
                }
            }

            let lineWidth: CGFloat = (displayIndex == lastIndex) ? 1.8 : 1.0
            context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)
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
        let camera = CameraProjection(pitchRad: pitchRad, yawRad: yawRad)

        let leftWorld  = SIMD3<Float>(-0.5, 0, zWorld)
        let rightWorld = SIMD3<Float>(+0.5, 0, zWorld)
        let left  = camera.project(leftWorld)
        let right = camera.project(rightWorld)

        let plotCenterX = plot.midX
        let plotCenterY = plot.midY
        let scaleX = plot.width
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

    /// Orthographic 3D-to-2D projection. World box is [-0.5, 0.5]^3;
    /// output is in normalized screen space [-0.5, 0.5] (caller scales).
    private struct CameraProjection {
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

    // ========================================================================
    // MARK: - Crosshair picker
    // ========================================================================

    private func drawCrosshair(at position: CGPoint, plot: CGRect, context: inout GraphicsContext) {
        let x = max(plot.minX, min(plot.maxX, position.x))
        let y = max(plot.minY, min(plot.maxY, position.y))

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

        let readout = crosshairReadout(at: CGPoint(x: x, y: y), plot: plot)
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
        let clamped = max(0, min(1, binFrac))
        let idx = Int((clamped * CGFloat(freqs.count - 1)).rounded())
        return freqs[min(max(0, idx), freqs.count - 1)]
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
            targetFrequencyCount: 128
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
        let capacityChanged = new.capacity != settings.capacity
        let dbChanged = new.minDB != settings.minDB || new.maxDB != settings.maxDB
        settings = new
        if capacityChanged {
            history = RingBuffer(capacity: max(8, new.capacity))
            lastBinCount = 0
            lastFrequencies = []
            dataSet = WaterfallDataSet.empty.with(minDB: new.minDB, maxDB: new.maxDB)
            return
        }
        if dbChanged || new.sliceCount != settings.sliceCount {
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
        if lastBinCount != 0, magnitudes.count != lastBinCount {
            history.removeAll()
        }
        history.append(Frame(magnitudes: magnitudes, timestamp: timestamp))
        lastBinCount = magnitudes.count
        lastFrequencies = frequencies
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
// MARK: - WaterfallWidget (data plumbing)
// ============================================================================

struct WaterfallWidget: View {
    private let audioEngine: AudioEngine
    var settings: [String: String]

    @StateObject private var store = WaterfallHistoryStore()

    init(audioEngine: AudioEngine, settings: [String: String]) {
        self.audioEngine = audioEngine
        self.settings = settings
    }

    // Settings derivation. With the mel visual pipeline `visualMagnitudes`
    // is always present and weighting-agnostic, so the per-widget weighting
    // override is intentionally not threaded into the store any more.
    private var useWidgetOverrides: Bool { WidgetSettings.usesWidgetOverrides(settings) }

    private var sliceCount: Int {
        guard useWidgetOverrides else { return WidgetSettings.defaultWaterfallSliceCount }
        return Int(settings["waterfallSlices"] ?? "") ?? WidgetSettings.defaultWaterfallSliceCount
    }

    private var minDB: Float {
        guard useWidgetOverrides else { return WidgetSettings.defaultWaterfallMinDB }
        let raw = Float(settings["waterfallMinDB"] ?? "") ?? WidgetSettings.defaultWaterfallMinDB
        // Pre-2026-05 settings stored dBFS-style negatives; fall back to default.
        return raw < 0 ? WidgetSettings.defaultWaterfallMinDB : raw
    }

    private var maxDB: Float {
        guard useWidgetOverrides else { return WidgetSettings.defaultWaterfallMaxDB }
        let raw = Float(settings["waterfallMaxDB"] ?? "") ?? WidgetSettings.defaultWaterfallMaxDB
        return raw <= 0 ? WidgetSettings.defaultWaterfallMaxDB : raw
    }

    /// History capacity sized for ~6 seconds at 86 Hz — long enough to
    /// give the time axis meaningful depth without paying for a huge
    /// ring buffer.
    private var capacity: Int {
        max(120, sliceCount * 6)
    }

    private var resolvedSettings: WaterfallHistoryStore.Settings {
        // Cross-validate: if user sets min ≥ max via the steppers, clamp so
        // there is always at least 5 dB of range (same pattern as SpectrumBandChartView).
        let lo = minDB
        let hi = maxDB
        return WaterfallHistoryStore.Settings(
            capacity: capacity,
            sliceCount: sliceCount,
            minDB: min(lo, hi - 5),
            maxDB: max(hi, lo + 5),
            rebuildInterval: 0.12,
            targetFrequencyCount: 128
        )
    }

    var body: some View {
        // No widget-level header overlay: the card chrome
        // (`WidgetCardView`) already labels the widget. Keeping the canvas
        // surface clean leaves the mode tag drawn by `WaterfallView`
        // unambiguous.
        WaterfallView(dataSet: store.dataSet, highlightedTime: nil)
            .onReceive(audioEngine.spectrogramSubject) { data in
                let magnitudes = data.visualMagnitudes ?? data.magnitudes(for: audioEngine.frequencyWeighting.rawValue)
                let frequencies = data.visualFrequencies ?? data.frequencies
                store.append(
                    magnitudes: magnitudes,
                    frequencies: frequencies,
                    timestamp: data.timestamp
                )
            }
            .onChange(of: resolvedSettings) { _, new in
                store.update(settings: new)
            }
            .onAppear {
                store.update(settings: resolvedSettings)
                if let current = audioEngine.live.currentSpectrogramData {
                    let m = current.visualMagnitudes ?? current.magnitudes(for: audioEngine.frequencyWeighting.rawValue)
                    let f = current.visualFrequencies ?? current.frequencies
                    store.append(magnitudes: m, frequencies: f, timestamp: current.timestamp)
                }
            }
            .accessibilityIdentifier("waterfallWidget")
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
