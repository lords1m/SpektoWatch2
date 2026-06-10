import SwiftUI

/// Which axis (or both) pinch-to-zoom affects.
enum SpectrogramZoomAxis: String, CaseIterable, Identifiable {
    case both
    case time
    case frequency

    var id: String { rawValue }
    var title: String {
        switch self {
        case .both: return "Beides"
        case .time: return "Zeit"
        case .frequency: return "Frequenz"
        }
    }
}

/// A navigable spectrogram for a stored recording.
///
/// Built on the Metal `PlaybackSpectrogramView`, it adds two-axis pan/zoom,
/// tap-to-seek and drag-to-pan, time and frequency rulers, an overview minimap,
/// a value-inspecting crosshair mode, follow-the-playhead, and a level-of-detail
/// overlay that loads a sharper window from disk when zoomed in.
struct NavigableSpectrogramView: View {
    /// Decimated, full-recording history in raw dB SPL (`[column][bin]`).
    var magnitudeHistory: [[Float]]
    /// Bumped by the owner whenever `magnitudeHistory` content changes.
    var dataVersion: Int
    var duration: TimeInterval
    var currentTime: TimeInterval
    var colormapType: Int
    var sampleRate: Float
    var calibrationOffset: Float
    var axisKind: SpectrogramHistoryAxisKind
    var markers: [MeasurementMarker] = []
    var onSeek: (TimeInterval) -> Void
    /// Optional loader for a sharper window covering a sub-range. Returns raw
    /// dB SPL columns, or `nil` when no higher resolution is available.
    var detailTileLoader: ((_ timeRange: ClosedRange<TimeInterval>, _ maxColumns: Int) async -> [[Float]]?)?

    @State private var viewport = SpectrogramViewport.full
    @State private var magnifyBase: SpectrogramViewport?
    @State private var dragBase: SpectrogramViewport?
    @State private var dragStartTime: TimeInterval?
    @State private var isInteracting = false
    @State private var followPlayhead = true
    @State private var inspectMode = false
    @State private var zoomAxis: SpectrogramZoomAxis = .both

    @State private var detailTile: DetailTile?
    @State private var tileRequest: TileRequest?

    private let minimapHeight: CGFloat = 46
    private let axisFrequencies: [Double] = [20, 31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    private var normalizedPlayhead: Float {
        guard duration > 0 else { return 0 }
        return Float(max(0, min(1, currentTime / duration)))
    }

    private var binCount: Int { magnitudeHistory.first?.count ?? 0 }

    var body: some View {
        VStack(spacing: 6) {
            controlBar
            spectrogramArea
            SpectrogramMinimap(
                magnitudeHistory: magnitudeHistory,
                dataVersion: dataVersion,
                colormapType: colormapType,
                sampleRate: sampleRate,
                calibrationOffset: calibrationOffset,
                viewport: viewport,
                normalizedPlayhead: normalizedPlayhead,
                onNavigate: { tNorm, fNorm in
                    followPlayhead = false
                    var vp = viewport
                    vp.timeStart = tNorm - vp.timeWidth / 2
                    vp.freqStart = fNorm - vp.freqWidth / 2
                    vp.clamp()
                    viewport = vp
                    requestDetailTile()
                }
            )
            .frame(height: minimapHeight)
        }
        .onChange(of: currentTime) { _, _ in followPlayheadIfNeeded() }
        .onChange(of: dataVersion) { _, _ in
            detailTile = nil
            requestDetailTile()
        }
        .task(id: tileRequest) {
            await loadDetailTile()
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 10) {
            Picker("Zoom-Achse", selection: $zoomAxis) {
                ForEach(SpectrogramZoomAxis.allCases) { axis in
                    Text(axis.title).tag(axis)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)

            Spacer(minLength: 4)

            Toggle(isOn: $followPlayhead) {
                Image(systemName: "location.fill")
            }
            .toggleStyle(.button)
            .accessibilityLabel("Wiedergabe folgen")

            Button {
                inspectMode.toggle()
            } label: {
                Image(systemName: inspectMode ? "scope" : "dot.viewfinder")
            }
            .buttonStyle(.bordered)
            .tint(inspectMode ? .orange : .secondary)
            .accessibilityLabel(inspectMode ? "Messmodus aktiv" : "Messmodus")

            Button {
                resetViewport()
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .disabled(viewport.isFitted)
            .accessibilityLabel("Ansicht zurücksetzen")
        }
        .font(.subheadline)
    }

    // MARK: - Spectrogram area

    private var spectrogramArea: some View {
        GeometryReader { geo in
            let size = geo.size
            let playheadLocalX = viewport.localX(forNormalizedTime: normalizedPlayhead)

            ZStack(alignment: .topLeading) {
                baseRenderer(size: size)
                detailOverlay(size: size)

                markerOverlay(size: size)
                playheadOverlay(localX: playheadLocalX, size: size)

                SpectrogramFrequencyRuler(
                    axisKind: axisKind,
                    binCount: binCount,
                    sampleRate: sampleRate,
                    freqStart: viewport.freqStart,
                    freqWidth: viewport.freqWidth,
                    frequencies: axisFrequencies
                )
                .allowsHitTesting(false)

                VStack {
                    Spacer()
                    SpectrogramTimeRuler(
                        startTime: TimeInterval(viewport.timeStart) * duration,
                        endTime: TimeInterval(viewport.timeEnd) * duration
                    )
                    .allowsHitTesting(false)
                }

                if inspectMode {
                    SpectrogramCrosshairOverlay { x, y in
                        inspector(viewX: x, viewY: y, size: size)
                    }
                }
            }
            .contentShape(Rectangle())
            .modifier(NavigationGestures(
                enabled: !inspectMode,
                size: size,
                viewport: $viewport,
                magnifyBase: $magnifyBase,
                dragBase: $dragBase,
                dragStartTime: $dragStartTime,
                isInteracting: $isInteracting,
                followPlayhead: $followPlayhead,
                zoomAxis: zoomAxis,
                duration: duration,
                onSeek: onSeek,
                onInteractionEnd: requestDetailTile
            ))
        }
        .frame(height: 280)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func baseRenderer(size: CGSize) -> some View {
        PlaybackSpectrogramView(
            magnitudeHistory: magnitudeHistory,
            dataVersion: dataVersion,
            colormapType: colormapType,
            viewportStart: viewport.timeStart,
            viewportWidth: viewport.timeWidth,
            freqViewportStart: viewport.freqStart,
            freqViewportWidth: viewport.freqWidth,
            totalDuration: duration,
            sampleRate: sampleRate,
            viewWidth: size.width,
            viewHeight: size.height,
            calibrationOffset: calibrationOffset,
            axisKind: axisKind
        )
    }

    @ViewBuilder
    private func detailOverlay(size: CGSize) -> some View {
        if let tile = detailTile, tile.matches(viewport: viewport, version: dataVersion) {
            PlaybackSpectrogramView(
                magnitudeHistory: tile.bins,
                dataVersion: tile.renderVersion,
                colormapType: colormapType,
                viewportStart: 0,
                viewportWidth: 1,
                freqViewportStart: viewport.freqStart,
                freqViewportWidth: viewport.freqWidth,
                totalDuration: duration,
                sampleRate: sampleRate,
                viewWidth: size.width,
                viewHeight: size.height,
                calibrationOffset: calibrationOffset,
                axisKind: axisKind
            )
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func markerOverlay(size: CGSize) -> some View {
        ForEach(markers) { marker in
            let nt = duration > 0 ? Float(marker.time / duration) : 0
            let localX = viewport.localX(forNormalizedTime: nt)
            if localX >= 0 && localX <= 1 {
                Rectangle()
                    .fill(Color.red.opacity(0.85))
                    .frame(width: 1.5, height: size.height)
                    .offset(x: size.width * CGFloat(localX))
            }
        }
    }

    @ViewBuilder
    private func playheadOverlay(localX: Float, size: CGSize) -> some View {
        if localX >= 0 && localX <= 1 {
            let x = size.width * CGFloat(localX)
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: size.height)
                .offset(x: x)
                .shadow(color: .black.opacity(0.5), radius: 2)
            Text(formatTime(currentTime))
                .font(.caption2.monospacedDigit())
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.white)
                .offset(x: max(0, min(x - 18, size.width - 46)), y: 4)
        }
    }

    private func inspector(viewX: CGFloat, viewY: CGFloat, size: CGSize) -> (time: TimeInterval, frequency: Float, magnitude: Float)? {
        let probe = PlaybackSpectrogramView(
            magnitudeHistory: magnitudeHistory,
            colormapType: colormapType,
            viewportStart: viewport.timeStart,
            viewportWidth: viewport.timeWidth,
            freqViewportStart: viewport.freqStart,
            freqViewportWidth: viewport.freqWidth,
            totalDuration: duration,
            sampleRate: sampleRate,
            viewWidth: size.width,
            viewHeight: size.height,
            calibrationOffset: calibrationOffset,
            axisKind: axisKind
        )
        return probe.valueAt(viewX: viewX, viewY: viewY)
    }

    // MARK: - Follow playhead

    private func followPlayheadIfNeeded() {
        guard followPlayhead, !isInteracting, !viewport.isFitted else { return }
        let nt = normalizedPlayhead
        let margin = viewport.timeWidth * 0.12
        if nt < viewport.timeStart + margin || nt > viewport.timeEnd - margin {
            var vp = viewport
            vp.centerTime(on: nt)
            viewport = vp
        }
    }

    private func resetViewport() {
        viewport = .full
        detailTile = nil
        tileRequest = nil
    }

    // MARK: - Level of detail

    private func requestDetailTile() {
        guard detailTileLoader != nil, duration > 0, viewport.timeWidth < 0.6 else {
            tileRequest = nil
            return
        }
        tileRequest = TileRequest(
            timeStart: (viewport.timeStart * 500).rounded() / 500,
            timeWidth: (viewport.timeWidth * 500).rounded() / 500,
            version: dataVersion
        )
    }

    private func loadDetailTile() async {
        guard let request = tileRequest, let loader = detailTileLoader else { return }
        // Debounce: let rapid gesture-driven requests settle first.
        try? await Task.sleep(nanoseconds: 180_000_000)
        if Task.isCancelled { return }

        let lower = TimeInterval(request.timeStart) * duration
        let upper = TimeInterval(min(1, request.timeStart + request.timeWidth)) * duration
        guard upper > lower else { return }

        let bins = await loader(lower...upper, 2400)
        if Task.isCancelled { return }
        guard let bins, !bins.isEmpty else { return }

        detailTile = DetailTile(
            bins: bins,
            timeStart: request.timeStart,
            timeWidth: request.timeWidth,
            version: request.version,
            renderVersion: (detailTile?.renderVersion ?? 0) &+ 1
        )
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - LOD support types

private struct TileRequest: Equatable {
    let timeStart: Float
    let timeWidth: Float
    let version: Int
}

private struct DetailTile {
    let bins: [[Float]]
    let timeStart: Float
    let timeWidth: Float
    let version: Int
    let renderVersion: Int

    func matches(viewport: SpectrogramViewport, version currentVersion: Int) -> Bool {
        version == currentVersion &&
        abs(timeStart - viewport.timeStart) < 0.004 &&
        abs(timeWidth - viewport.timeWidth) < 0.004
    }
}

// MARK: - Gesture modifier

/// Encapsulates pinch-zoom, drag-pan/seek, and tap-to-seek so the gesture
/// bookkeeping lives outside the main view body.
private struct NavigationGestures: ViewModifier {
    let enabled: Bool
    let size: CGSize
    @Binding var viewport: SpectrogramViewport
    @Binding var magnifyBase: SpectrogramViewport?
    @Binding var dragBase: SpectrogramViewport?
    @Binding var dragStartTime: TimeInterval?
    @Binding var isInteracting: Bool
    @Binding var followPlayhead: Bool
    let zoomAxis: SpectrogramZoomAxis
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void
    let onInteractionEnd: () -> Void

    func body(content: Content) -> some View {
        guard enabled else { return AnyView(content) }
        return AnyView(
            content
                .simultaneousGesture(magnifyGesture)
                .simultaneousGesture(dragGesture)
                .simultaneousGesture(tapGesture)
        )
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                let base = magnifyBase ?? viewport
                if magnifyBase == nil {
                    magnifyBase = base
                    isInteracting = true
                    followPlayhead = false
                }
                let factor = Float(1.0 / max(value.magnification, 0.05))
                let focusX = Float(value.startAnchor.x)
                let focusYFromBottom = Float(1 - value.startAnchor.y)

                var vp = base
                if zoomAxis != .frequency {
                    vp.zoomTime(by: factor, focus: focusX)
                }
                if zoomAxis != .time {
                    vp.zoomFreq(by: factor, focus: focusYFromBottom)
                }
                viewport = vp
            }
            .onEnded { _ in
                magnifyBase = nil
                isInteracting = false
                onInteractionEnd()
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let width = max(size.width, 1)
                let height = max(size.height, 1)
                if viewport.isFitted {
                    // Fitted: horizontal drag scrubs the playhead.
                    if dragStartTime == nil {
                        isInteracting = true
                        let frac = Float(max(0, min(1, value.startLocation.x / width)))
                        dragStartTime = TimeInterval(viewport.normalizedTime(forLocalX: frac)) * duration
                        onSeek(dragStartTime ?? 0)
                        return
                    }
                    let secondsPerPoint = duration / TimeInterval(width)
                    let delta = TimeInterval(value.translation.width) * secondsPerPoint
                    onSeek(max(0, min((dragStartTime ?? 0) + delta, duration)))
                } else {
                    // Zoomed: one-finger drag pans the window (content follows finger).
                    let base = dragBase ?? viewport
                    if dragBase == nil {
                        dragBase = base
                        isInteracting = true
                        followPlayhead = false
                    }
                    let dt = -Float(value.translation.width / width) * base.timeWidth
                    let df = -Float(value.translation.height / height) * base.freqWidth
                    var vp = base
                    vp.pan(dt: dt, df: df)
                    viewport = vp
                }
            }
            .onEnded { _ in
                dragStartTime = nil
                dragBase = nil
                isInteracting = false
                onInteractionEnd()
            }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let width = max(size.width, 1)
                let frac = Float(max(0, min(1, value.location.x / width)))
                let t = TimeInterval(viewport.normalizedTime(forLocalX: frac)) * duration
                onSeek(max(0, min(t, duration)))
            }
    }
}

// MARK: - Frequency ruler

private struct SpectrogramFrequencyRuler: View {
    let axisKind: SpectrogramHistoryAxisKind
    let binCount: Int
    let sampleRate: Float
    let freqStart: Float
    let freqWidth: Float
    let frequencies: [Double]

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let maxFreq = min(Double(sampleRate) / 2.0, 20_000)
            ZStack(alignment: .topLeading) {
                ForEach(frequencies.filter { $0 <= maxFreq }, id: \.self) { freq in
                    if let y = yPosition(for: freq, height: height) {
                        Text(label(for: freq))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.8), radius: 2)
                            .position(x: 24, y: y)
                    }
                }
            }
        }
        .padding(4)
    }

    private func yPosition(for freq: Double, height: CGFloat) -> CGFloat? {
        let gNorm = SpectrogramHistoryAxis.normalizedPosition(
            forFrequency: Float(freq),
            kind: axisKind,
            binCount: max(binCount, 2),
            sampleRate: Double(sampleRate)
        )
        guard freqWidth > 0 else { return nil }
        let local = (gNorm - freqStart) / freqWidth   // 0…1 from bottom of window
        guard local >= 0, local <= 1 else { return nil }
        return height * (1 - CGFloat(local))
    }

    private func label(for freq: Double) -> String {
        freq >= 1000 ? String(format: "%.0fk", freq / 1000) : String(format: "%.0f", freq)
    }
}

// MARK: - Time ruler

private struct SpectrogramTimeRuler: View {
    let startTime: TimeInterval
    let endTime: TimeInterval

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let span = max(endTime - startTime, 0.001)
            let step = niceStep(forSpan: span)
            let firstTick = (startTime / step).rounded(.up) * step
            let ticks = stride(from: firstTick, through: endTime, by: step).map { $0 }
            ZStack(alignment: .topLeading) {
                ForEach(ticks, id: \.self) { tick in
                    let x = CGFloat((tick - startTime) / span) * width
                    Text(format(tick))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.65))
                        .position(x: max(14, min(width - 14, x)), y: 8)
                }
            }
        }
        .frame(height: 16)
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }

    private func niceStep(forSpan span: TimeInterval) -> TimeInterval {
        switch span {
        case ..<3: return 0.5
        case ..<8: return 1
        case ..<20: return 2
        case ..<60: return 5
        case ..<180: return 15
        case ..<600: return 60
        default: return 300
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let rounded = Int(t.rounded())
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }
}

// MARK: - Minimap

/// Whole-recording overview with a draggable viewport rectangle.
private struct SpectrogramMinimap: View {
    let magnitudeHistory: [[Float]]
    let dataVersion: Int
    let colormapType: Int
    let sampleRate: Float
    let calibrationOffset: Float
    let viewport: SpectrogramViewport
    let normalizedPlayhead: Float
    /// `(timeNorm, freqNorm)` of the requested centre, both `0…1`.
    let onNavigate: (Float, Float) -> Void

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                PlaybackSpectrogramView(
                    magnitudeHistory: magnitudeHistory,
                    dataVersion: dataVersion,
                    colormapType: colormapType,
                    viewportStart: 0,
                    viewportWidth: 1,
                    freqViewportStart: 0,
                    freqViewportWidth: 1,
                    totalDuration: 1,
                    sampleRate: sampleRate,
                    viewWidth: size.width,
                    viewHeight: size.height,
                    calibrationOffset: calibrationOffset
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                // Viewport rectangle (freq high = top, so flip Y).
                let rectX = CGFloat(viewport.timeStart) * size.width
                let rectW = CGFloat(viewport.timeWidth) * size.width
                let rectY = CGFloat(1 - viewport.freqEnd) * size.height
                let rectH = CGFloat(viewport.freqWidth) * size.height
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                    .background(Color.white.opacity(0.12).clipShape(RoundedRectangle(cornerRadius: 3)))
                    .frame(width: max(rectW, 4), height: max(rectH, 4))
                    .offset(x: rectX, y: rectY)

                Rectangle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 1.5, height: size.height)
                    .offset(x: CGFloat(normalizedPlayhead) * size.width)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let tNorm = Float(max(0, min(1, value.location.x / max(size.width, 1))))
                        let fNorm = Float(max(0, min(1, 1 - value.location.y / max(size.height, 1))))
                        onNavigate(tNorm, fNorm)
                    }
            )
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
