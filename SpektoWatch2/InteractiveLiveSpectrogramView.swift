import SwiftUI

/// Interactive wrapper around the live Metal spectrogram.
///
/// Gestures (common-sense, axis-aligned):
/// - One-finger drag scrolls: horizontal pans the time axis, vertical pans the
///   frequency axis (the drag does both at once from one finger).
/// - Pinch zooms in/out around the pinch focus on both axes.
/// - Tap toggles the value picker; while active, drag moves the crosshair and
///   the readout shows the frequency / time (and the picker "captures" the drag
///   instead of panning).
/// - The play/pause button freezes the stream so you can inspect a still frame;
///   time navigation is most useful while frozen.
struct InteractiveLiveSpectrogramView: View {
    @ObservedObject var audioEngine: AudioEngine
    var colormapType: Int
    var timeSpan: SpectrogramTimeSpan
    var scrollSpeed: ScrollSpeed
    var freqWeighting: String
    var sensitivity: Float
    var frequencySmoothing: Float
    var noiseFloor: Float
    var engineStatus: EngineStatus
    /// Shared with the presenting tile so the fullscreen view primes from (and
    /// continues) the same live scroll history rather than starting blank.
    var columnHistory: SpectrogramColumnHistory? = nil

    // Interactive view window. (0,1,0,1) = full, unzoomed.
    @State private var tStart: Float = 0
    @State private var tWidth: Float = 1
    @State private var fStart: Float = 0
    @State private var fHeight: Float = 1

    @State private var dragBase: Viewport?
    @State private var magBase: Viewport?
    @State private var isFrozen = false
    @State private var pickerActive = false
    @State private var pickerPoint: CGPoint?

    private struct Viewport { var t0: Float; var tw: Float; var f0: Float; var fh: Float }
    private var current: Viewport { Viewport(t0: tStart, tw: tWidth, f0: fStart, fh: fHeight) }
    private var isZoomed: Bool { tWidth < 0.999 || fHeight < 0.999 || tStart > 0.001 || fStart > 0.001 }

    private var minHz: Double { audioEngine.spectrogramMinFrequency }
    private var maxHz: Double { audioEngine.spectrogramMaxFrequency }
    private var scale: SpectrogramFrequencyScale { audioEngine.spectrogramFrequencyScale }
    private var spanSeconds: Double { Double(timeSpan.rawValue) }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                HighEndSpectrogramAdapterView(
                    audioEngine: audioEngine,
                    colormapType: colormapType,
                    timeSpan: timeSpan,
                    scrollSpeed: scrollSpeed,
                    isPaused: isFrozen || engineStatus != .running,
                    freqWeighting: freqWeighting,
                    sensitivity: sensitivity,
                    frequencySmoothing: frequencySmoothing,
                    noiseFloor: noiseFloor,
                    frequencyScale: scale,
                    minFrequency: Float(minHz),
                    maxFrequency: Float(maxHz),
                    viewportTimeStart: tStart,
                    viewportTimeWidth: tWidth,
                    viewportFreqStart: fStart,
                    viewportFreqHeight: fHeight,
                    columnHistory: columnHistory
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                frequencyTicks(size: size)
                    .allowsHitTesting(false)

                if pickerActive, let p = pickerPoint {
                    crosshair(at: p, size: size)
                        .allowsHitTesting(false)
                }

                gestureLayer(size: size)

                controlBar(readout: pickerActive ? pickerPoint.map { valueLabel(point: $0, size: size) } : nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    // MARK: - Gestures

    private func gestureLayer(size: CGSize) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .simultaneousGesture(magnify(size: size))
            .simultaneousGesture(drag(size: size))
            .simultaneousGesture(tap)
    }

    private func drag(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if pickerActive {
                    pickerPoint = clampPoint(value.location, in: size)
                    return
                }
                let w = Float(max(size.width, 1))
                let h = Float(max(size.height, 1))
                let base = dragBase ?? current
                if dragBase == nil { dragBase = base }
                // Drag right reveals earlier time; drag down reveals higher freq.
                let t0 = base.t0 + Float(value.translation.width) / w * base.tw
                let f0 = base.f0 + Float(value.translation.height) / h * base.fh
                apply(Viewport(t0: t0, tw: base.tw, f0: f0, fh: base.fh))
            }
            .onEnded { _ in dragBase = nil }
    }

    private func magnify(size: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                let base = magBase ?? current
                if magBase == nil { magBase = base }
                let factor = Float(1.0 / max(value.magnification, 0.05))
                let fx = Float(value.startAnchor.x)            // 0…1 left→right (time)
                let fyBottom = Float(1 - value.startAnchor.y)  // 0…1 bottom→top (freq)

                let tw = base.tw * factor
                let t0 = base.t0 + (base.tw - tw) * fx
                let fh = base.fh * factor
                let f0 = base.f0 + (base.fh - fh) * fyBottom
                apply(Viewport(t0: t0, tw: tw, f0: f0, fh: fh))
            }
            .onEnded { _ in magBase = nil }
    }

    private var tap: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                if pickerActive {
                    pickerActive = false
                    pickerPoint = nil
                } else {
                    pickerActive = true
                    pickerPoint = value.location
                }
            }
    }

    /// Clamp a candidate viewport to valid sub-windows and commit it.
    private func apply(_ vp: Viewport) {
        let tw = min(max(vp.tw, 0.02), 1)
        let t0 = min(max(vp.t0, 0), 1 - tw)
        let fh = min(max(vp.fh, 0.02), 1)
        let f0 = min(max(vp.f0, 0), 1 - fh)
        tWidth = tw; tStart = t0; fHeight = fh; fStart = f0
    }

    private func clampPoint(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), size.width), y: min(max(p.y, 0), size.height))
    }

    // MARK: - Controls

    private func controlBar(readout: String?) -> some View {
        HStack(spacing: 14) {
            Button {
                isFrozen.toggle()
            } label: {
                Image(systemName: isFrozen ? "play.fill" : "pause.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
            }
            .accessibilityLabel(isFrozen ? "Fortsetzen" : "Einfrieren")

            if let readout {
                Text(readout)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
            }

            Spacer()

            if isZoomed {
                Button {
                    apply(Viewport(t0: 0, tw: 1, f0: 0, fh: 1))
                } label: {
                    Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                }
                .accessibilityLabel("Ansicht zurücksetzen")
            }
        }
        .padding(12)
    }

    // MARK: - Picker crosshair + readout

    private func crosshair(at p: CGPoint, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.white.opacity(0.9))
                .frame(width: 1, height: size.height)
                .offset(x: p.x)
            Rectangle().fill(Color.white.opacity(0.9))
                .frame(width: size.width, height: 1)
                .offset(y: p.y)
            Circle().stroke(Color.white, lineWidth: 1.5)
                .frame(width: 14, height: 14)
                .position(p)
        }
        .shadow(color: .black.opacity(0.6), radius: 2)
    }

    /// Frequency + time-ago at a picker point, derived from the active viewport,
    /// frequency scale and display range.
    private func valueLabel(point: CGPoint, size: CGSize) -> String {
        let uvX = Double(point.x / max(size.width, 1))
        let uvY = Double(point.y / max(size.height, 1))
        let winX = Double(tStart) + uvX * Double(tWidth)          // 0 = newest … 1 = oldest
        let timeAgo = winX * spanSeconds
        let fullFrac = Double(fStart) + (1 - uvY) * Double(fHeight)
        let f = hz(forFrac: min(max(fullFrac, 0), 1))
        return "\(frequencyLabel(f))  •  −\(String(format: "%.2f", timeAgo)) s"
    }

    // MARK: - Frequency <-> normalized helpers

    private func hz(forFrac frac: Double) -> Double {
        let lo = max(1, min(minHz, maxHz))
        let hi = max(lo + 1, maxHz)
        switch scale {
        case .logarithmic: return lo * pow(hi / lo, frac)
        case .linear: return lo + frac * (hi - lo)
        }
    }

    private func frac(forHz hz: Double) -> Double {
        let lo = max(1, min(minHz, maxHz))
        let hi = max(lo + 1, maxHz)
        switch scale {
        case .logarithmic: return log(hz / lo) / log(hi / lo)
        case .linear: return (hz - lo) / (hi - lo)
        }
    }

    private func frequencyLabel(_ hz: Double) -> String {
        hz >= 1000 ? String(format: "%.1f kHz", hz / 1000) : String(format: "%.0f Hz", hz)
    }

    // MARK: - Frequency tick overlay (viewport-aware)

    private func frequencyTicks(size: CGSize) -> some View {
        let ticks = SpectrogramAxisMath.axisTickFrequencies(
            scale: scale, minFrequency: minHz, maxFrequency: maxHz
        )
        return ZStack(alignment: .topLeading) {
            ForEach(ticks, id: \.self) { f in
                if let y = tickY(for: f, height: size.height) {
                    Text(frequencyLabel(f))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.8), radius: 2)
                        .position(x: 30, y: y)
                }
            }
        }
    }

    /// Screen-Y for a frequency, accounting for the freq viewport window.
    private func tickY(for hz: Double, height: CGFloat) -> CGFloat? {
        let full = frac(forHz: hz)                       // 0…1 over the base range
        let visible = (full - Double(fStart)) / Double(max(fHeight, 0.0001))
        guard visible >= 0, visible <= 1 else { return nil }
        return height * CGFloat(1 - visible)
    }
}
