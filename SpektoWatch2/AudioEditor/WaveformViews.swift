import SwiftUI

enum WaveformSelectionMode: String, CaseIterable, Identifiable {
    case trim = "Zuschneiden"
    case cut = "Bereich löschen"

    var id: String { rawValue }
}

// MARK: - Overview Minimap (~48pt)

struct WaveformOverviewMinimap: View {
    let bins: [WaveformBin]
    let totalDuration: TimeInterval
    let currentTime: TimeInterval
    let visibleStart: TimeInterval
    let visibleEnd: TimeInterval
    let selectionStart: TimeInterval
    let selectionEnd: TimeInterval
    let selectionMode: WaveformSelectionMode
    let onScrub: (TimeInterval) -> Void

    @Environment(\.designAccent) private var accent

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let dur = max(0.01, totalDuration)

            ZStack(alignment: .leading) {
                Canvas { ctx, size in
                    drawEnvelope(ctx: ctx, size: size)
                    drawSelectionOverlay(ctx: ctx, size: size, duration: dur)
                    drawViewportWindow(ctx: ctx, size: size, duration: dur)
                    drawPlayhead(ctx: ctx, size: size, duration: dur)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let frac = max(0, min(1, value.location.x / w))
                        onScrub(Double(frac) * dur)
                    }
            )
        }
        .frame(height: 48)
        .innerCanvas(cornerRadius: Radius.kernel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wellenform-Übersicht")
    }

    private func drawEnvelope(ctx: GraphicsContext, size: CGSize) {
        guard !bins.isEmpty else { return }
        let midY = size.height / 2
        let count = bins.count
        let step = max(1, count / max(1, Int(size.width)))
        var x: CGFloat = 0
        var idx = 0
        while idx < count {
            var peak: Float = 0
            let endIdx = min(count, idx + step)
            for j in idx..<endIdx {
                peak = max(peak, max(abs(bins[j].min), abs(bins[j].max)))
            }
            let barH = max(2, CGFloat(peak) * (size.height - 8))
            let rect = CGRect(x: x, y: midY - barH / 2, width: 1.5, height: barH)
            ctx.fill(Path(rect), with: .color(Color.primary.opacity(0.42)))
            x += size.width / CGFloat(max(1, count / step))
            idx = endIdx
        }
    }

    private func drawSelectionOverlay(ctx: GraphicsContext, size: CGSize, duration: TimeInterval) {
        let sx = CGFloat(selectionStart / duration) * size.width
        let ex = CGFloat(selectionEnd / duration) * size.width
        let selRect = CGRect(x: sx, y: 2, width: max(2, ex - sx), height: size.height - 4)
        let color: Color = (selectionMode == .trim) ? FerriteColor.accent : FerriteStatus.recording
        ctx.fill(Path(roundedRect: selRect, cornerRadius: 3), with: .color(color.opacity(0.22)))
        ctx.stroke(Path(roundedRect: selRect, cornerRadius: 3), with: .color(color.opacity(0.75)), lineWidth: 1)
    }

    private func drawViewportWindow(ctx: GraphicsContext, size: CGSize, duration: TimeInterval) {
        let vx = CGFloat(visibleStart / duration) * size.width
        let vw = max(8, CGFloat((visibleEnd - visibleStart) / duration) * size.width)
        let rect = CGRect(x: vx, y: 1, width: min(size.width - vx, vw), height: size.height - 2)
        ctx.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(accent.opacity(0.7)), lineWidth: 1.2)
    }

    private func drawPlayhead(ctx: GraphicsContext, size: CGSize, duration: TimeInterval) {
        let px = CGFloat(max(0, min(1, currentTime / duration))) * size.width
        var line = Path()
        line.move(to: CGPoint(x: px, y: 0))
        line.addLine(to: CGPoint(x: px, y: size.height))
        ctx.stroke(line, with: .color(FerriteStatus.recording), lineWidth: 1.5)
    }
}

// MARK: - Main Voice-Memos-Style Detail Waveform Canvas

struct WaveformDetailCanvas: View {
    let bins: [WaveformBin]
    let totalDuration: TimeInterval
    let currentTime: TimeInterval
    @Binding var zoomScale: CGFloat
    @Binding var scrollOffsetRatio: CGFloat
    @Binding var selectionStart: TimeInterval
    @Binding var selectionEnd: TimeInterval
    let selectionMode: WaveformSelectionMode
    let onBeginScrub: () -> Void
    let onScrub: (TimeInterval) -> Void
    let onEndScrub: () -> Void

    @Environment(\.designAccent) private var accent
    @State private var baseZoomScale: CGFloat? = nil
    @State private var baseScrollRatio: CGFloat? = nil
    @State private var dragStartSelection: (start: TimeInterval, end: TimeInterval)? = nil
    @State private var lastHapticSide: Int = 0

    private let minSelectionSpan: TimeInterval = 0.08
    private let handleHitWidth: CGFloat = 44
    private let rulerHeight: CGFloat = 20

    var visibleWindow: AudioTimeRange {
        let dur = max(0.05, totalDuration)
        let windowDur = dur / Double(max(1, zoomScale))
        let maxStart = max(0, dur - windowDur)
        let start = max(0, min(maxStart, Double(scrollOffsetRatio) * maxStart))
        return AudioTimeRange(start: start, end: min(dur, start + windowDur))
    }

    var body: some View {
        let window = visibleWindow
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let h = max(1, geo.size.height)
            let waveHeight = max(40, h - rulerHeight)

            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    drawRuler(ctx: ctx, width: size.width, window: window)
                    let waveRect = CGRect(x: 0, y: rulerHeight, width: size.width, height: waveHeight)
                    drawWaveformBars(ctx: ctx, rect: waveRect, window: window)
                    drawSelectionRegion(ctx: ctx, rect: waveRect, window: window)
                    drawPlayhead(ctx: ctx, rect: waveRect, window: window)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            if zoomScale > 1.02 && abs(value.translation.width) > 6 {
                                if baseScrollRatio == nil { baseScrollRatio = scrollOffsetRatio }
                                let dur = max(0.05, totalDuration)
                                let visDur = window.duration
                                let maxScroll = max(0.001, dur - visDur)
                                let dt = -Double(value.translation.width / w) * visDur
                                let newStart = max(0, min(maxScroll, (Double(baseScrollRatio ?? 0) * maxScroll) + dt))
                                scrollOffsetRatio = CGFloat(newStart / maxScroll)
                            } else {
                                if dragStartSelection == nil {
                                    onBeginScrub()
                                    dragStartSelection = (selectionStart, selectionEnd)
                                }
                                let t = time(atX: value.location.x, width: w, window: window)
                                onScrub(t)
                            }
                        }
                        .onEnded { value in
                            if dragStartSelection != nil {
                                dragStartSelection = nil
                                onEndScrub()
                            } else if abs(value.translation.width) < 4 {
                                let t = time(atX: value.location.x, width: w, window: window)
                                onScrub(t)
                            }
                            baseScrollRatio = nil
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            if baseZoomScale == nil { baseZoomScale = zoomScale }
                            let next = max(1.0, min(32.0, (baseZoomScale ?? 1.0) * value))
                            zoomScale = next
                        }
                        .onEnded { _ in
                            baseZoomScale = nil
                        }
                )

                // Draggable Left Handle
                selectionHandle(
                    isStart: true,
                    timeValue: selectionStart,
                    width: w,
                    waveHeight: waveHeight,
                    window: window
                )

                // Draggable Right Handle
                selectionHandle(
                    isStart: false,
                    timeValue: selectionEnd,
                    width: w,
                    waveHeight: waveHeight,
                    window: window
                )
            }
        }
        .frame(height: 170)
        .innerCanvas(cornerRadius: Radius.kernel)
    }

    @ViewBuilder
    private func selectionHandle(
        isStart: Bool,
        timeValue: TimeInterval,
        width: CGFloat,
        waveHeight: CGFloat,
        window: AudioTimeRange
    ) -> some View {
        let x = xPosition(forTime: timeValue, width: width, window: window)
        let isVisible = x >= -24 && x <= width + 24
        if isVisible {
            let clampedX = max(8, min(width - 8, x))
            let handleColor: Color = (selectionMode == .trim) ? FerriteColor.accent : FerriteStatus.warning

            ZStack {
                Rectangle()
                    .fill(handleColor)
                    .frame(width: 3, height: waveHeight)
                Circle()
                    .fill(handleColor)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Image(systemName: isStart ? "chevron.right" : "chevron.left")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(selectionMode == .trim ? FerriteColor.onAccent : Color.black)
                    )
                    .offset(y: isStart ? -waveHeight / 2 + 10 : waveHeight / 2 - 10)
            }
            .frame(width: handleHitWidth, height: waveHeight)
            .contentShape(Rectangle())
            .position(x: clampedX, y: rulerHeight + waveHeight / 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let newT = time(atX: value.location.x, width: width, window: window)
                        let sideTag = isStart ? 1 : 2
                        if lastHapticSide != sideTag {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            lastHapticSide = sideTag
                        }
                        if isStart {
                            selectionStart = max(0, min(newT, selectionEnd - minSelectionSpan))
                        } else {
                            selectionEnd = min(totalDuration, max(newT, selectionStart + minSelectionSpan))
                        }
                    }
                    .onEnded { _ in
                        lastHapticSide = 0
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(isStart ? "Auswahl-Startpunkt" : "Auswahl-Endpunkt")
            .accessibilityValue(AudioTimeFormatting.timestamp(timeValue))
            .accessibilityAdjustableAction { direction in
                let step = max(0.05, window.duration * 0.03)
                let delta = (direction == .increment) ? step : -step
                if isStart {
                    selectionStart = max(0, min(selectionStart + delta, selectionEnd - minSelectionSpan))
                } else {
                    selectionEnd = min(totalDuration, max(selectionEnd + delta, selectionStart + minSelectionSpan))
                }
            }
        }
    }

    // MARK: - Canvas Drawing

    private func drawRuler(ctx: GraphicsContext, width: CGFloat, window: AudioTimeRange) {
        let dur = max(0.05, window.duration)
        let desiredTicks = max(3, Int(width / 70))
        let rawStep = dur / Double(desiredTicks)
        let niceSteps: [Double] = [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300]
        let step = niceSteps.first { $0 >= rawStep } ?? 300

        let firstTick = ceil(window.start / step) * step
        var t = firstTick
        while t <= window.end + 0.0001 {
            let x = xPosition(forTime: t, width: width, window: window)
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: rulerHeight - 5))
            tick.addLine(to: CGPoint(x: x, y: rulerHeight))
            ctx.stroke(tick, with: .color(.secondary.opacity(0.45)), lineWidth: 1)

            let label = Text(AudioTimeFormatting.shortRuler(t, subSecond: step < 1.0))
                .font(.readout(size: 9))
                .foregroundStyle(.secondary)
            ctx.draw(label, at: CGPoint(x: min(width - 20, max(20, x)), y: 8), anchor: .center)
            t += step
        }

        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: rulerHeight))
        baseline.addLine(to: CGPoint(x: width, y: rulerHeight))
        ctx.stroke(baseline, with: .color(.primary.opacity(0.1)), lineWidth: 0.5)
    }

    private func drawWaveformBars(ctx: GraphicsContext, rect: CGRect, window: AudioTimeRange) {
        guard !bins.isEmpty, totalDuration > 0 else { return }
        let midY = rect.midY
        let maxHalfH = (rect.height - 12) / 2
        let barPitch: CGFloat = 3.0
        let barCount = max(1, Int(rect.width / barPitch))

        // Center zero line
        var zero = Path()
        zero.move(to: CGPoint(x: 0, y: midY))
        zero.addLine(to: CGPoint(x: rect.width, y: midY))
        ctx.stroke(zero, with: .color(.primary.opacity(0.12)), lineWidth: 0.5)

        for i in 0..<barCount {
            let x = CGFloat(i) * barPitch
            let t0 = window.start + (Double(i) / Double(barCount)) * window.duration
            let t1 = window.start + (Double(i + 1) / Double(barCount)) * window.duration
            let b0 = max(0, min(bins.count - 1, Int((t0 / totalDuration) * Double(bins.count))))
            let b1 = max(b0, min(bins.count - 1, Int((t1 / totalDuration) * Double(bins.count))))

            var peak: Float = 0
            for b in b0...b1 {
                peak = max(peak, max(abs(bins[b].min), abs(bins[b].max)))
            }

            let centerT = (t0 + t1) * 0.5
            let inSelection = centerT >= selectionStart && centerT <= selectionEnd
            let isKept = (selectionMode == .trim) ? inSelection : !inSelection
            let barColor = isKept ? accent.opacity(0.92) : Color.primary.opacity(0.24)

            let halfH = max(1.5, CGFloat(peak) * maxHalfH)
            let barRect = CGRect(x: x, y: midY - halfH, width: 2.0, height: halfH * 2)
            ctx.fill(Path(roundedRect: barRect, cornerRadius: 1), with: .color(barColor))
        }
    }

    private func drawSelectionRegion(ctx: GraphicsContext, rect: CGRect, window: AudioTimeRange) {
        let sx = max(0, min(rect.width, xPosition(forTime: selectionStart, width: rect.width, window: window)))
        let ex = max(0, min(rect.width, xPosition(forTime: selectionEnd, width: rect.width, window: window)))
        guard ex > sx else { return }

        let selRect = CGRect(x: sx, y: rect.minY, width: ex - sx, height: rect.height)
        if selectionMode == .trim {
            // Dim outside selection
            if sx > 0 {
                ctx.fill(Path(CGRect(x: 0, y: rect.minY, width: sx, height: rect.height)), with: .color(.black.opacity(0.32)))
            }
            if ex < rect.width {
                ctx.fill(Path(CGRect(x: ex, y: rect.minY, width: rect.width - ex, height: rect.height)), with: .color(.black.opacity(0.32)))
            }
            ctx.stroke(Path(selRect), with: .color(FerriteColor.accent.opacity(0.65)), lineWidth: 1)
        } else {
            // Cut mode: shade interior selection to be deleted
            ctx.fill(Path(selRect), with: .color(FerriteStatus.recording.opacity(0.24)))
            ctx.stroke(Path(selRect), with: .color(FerriteStatus.warning.opacity(0.8)), lineWidth: 1)
        }
    }

    private func drawPlayhead(ctx: GraphicsContext, rect: CGRect, window: AudioTimeRange) {
        guard currentTime >= window.start && currentTime <= window.end else { return }
        let px = xPosition(forTime: currentTime, width: rect.width, window: window)
        var line = Path()
        line.move(to: CGPoint(x: px, y: rect.minY - 4))
        line.addLine(to: CGPoint(x: px, y: rect.maxY))
        ctx.stroke(line, with: .color(FerriteStatus.recording), lineWidth: 2)

        let head = CGRect(x: px - 4, y: rect.minY - 6, width: 8, height: 8)
        ctx.fill(Path(ellipseIn: head), with: .color(FerriteStatus.recording))
    }

    private func xPosition(forTime t: TimeInterval, width: CGFloat, window: AudioTimeRange) -> CGFloat {
        let span = max(0.01, window.duration)
        return CGFloat((t - window.start) / span) * width
    }

    private func time(atX x: CGFloat, width: CGFloat, window: AudioTimeRange) -> TimeInterval {
        let frac = max(0, min(1, Double(x / max(1, width))))
        return max(0, min(totalDuration, window.start + frac * window.duration))
    }
}

// MARK: - Time Formatting Helper

enum AudioTimeFormatting {
    static func timestamp(_ seconds: TimeInterval) -> String {
        let safe = max(0, seconds)
        let mins = Int(safe) / 60
        let secs = Int(safe) % 60
        let tenths = Int((safe - floor(safe)) * 10)
        return String(format: "%02d:%02d.%d", mins, secs, tenths)
    }

    static func shortRuler(_ seconds: TimeInterval, subSecond: Bool) -> String {
        let safe = max(0, seconds)
        let mins = Int(safe) / 60
        let secs = Int(safe) % 60
        if subSecond {
            let tenths = Int((safe - floor(safe)) * 10)
            return String(format: "%d:%02d.%d", mins, secs, tenths)
        }
        return String(format: "%02d:%02d", mins, secs)
    }
}
