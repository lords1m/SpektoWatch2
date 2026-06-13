import SwiftUI
import Combine

/// Shared rolling level-history buffer. Hoisted out of `LevelHistoryView` so the
/// dashboard tile and its fullscreen cover render the SAME continuous history
/// instead of each owning a private buffer that restarts empty when presented.
@MainActor
final class LevelHistoryStore: ObservableObject {
    @Published private(set) var levelBuffer: [Float] = []
    @Published private(set) var writeIndex: Int = 0

    private var observedSampleRate: Double = 44100.0
    private var scrollSpeedValue: Int = 1
    private var timeSpanSeconds: Int = 5

    // Wall-clock advance state — see ingest() for the rationale.
    private var lastUpdateTimestamp: TimeInterval = 0
    private var lastBufferedLevel: Float = -120.0

    /// (Re)sizes the buffer for the given axis settings. Called on appear and
    /// whenever the time span / scroll speed changes.
    func configure(timeSpanSeconds: Int, scrollSpeed: Int) {
        let changed = timeSpanSeconds != self.timeSpanSeconds || scrollSpeed != self.scrollSpeedValue
        self.timeSpanSeconds = timeSpanSeconds
        self.scrollSpeedValue = max(1, scrollSpeed)
        if changed || levelBuffer.isEmpty { rebuild() }
    }

    /// Clears history — e.g. when the displayed metric changes and the old
    /// samples no longer correspond to the new series.
    func reset() { rebuild() }

    private func rebuild() {
        let updateRate = observedSampleRate / Double(max(scrollSpeedValue, 1))
        let columns = Int(Double(timeSpanSeconds) * updateRate)
        let safeColumns = max(10, columns)
        levelBuffer = [Float](repeating: -120.0, count: safeColumns)
        writeIndex = 0
        lastUpdateTimestamp = 0
        lastBufferedLevel = -120.0
    }

    /// Advances the ring buffer in wall-clock time so the time axis stays in
    /// sync with the spectrogram (which uses the same approach in
    /// `HighEndSpectrogramAdapter.updateWithFFTMagnitudes`). Without this, the
    /// buffer advanced one slot per FFT callback regardless of how much real
    /// time elapsed — under load the chart visibly compressed relative to the
    /// spectrogram alongside it.
    func ingest(level: Float, sampleRate: Double) {
        if sampleRate > 0 { observedSampleRate = sampleRate }
        guard !levelBuffer.isEmpty else { rebuild(); return }
        let safeLevel = level.isNaN || level.isInfinite ? -120.0 : level
        let now = Date().timeIntervalSinceReferenceDate

        let expectedUpdateRate = observedSampleRate / Double(max(scrollSpeedValue, 1))
        let secondsPerSlot = 1.0 / max(expectedUpdateRate, 1.0)

        let slotsToWrite: Int = {
            guard lastUpdateTimestamp > 0 else { return 1 }
            let dt = max(0, now - lastUpdateTimestamp)
            let raw = Int((dt / secondsPerSlot).rounded())
            return min(max(1, raw), levelBuffer.count)
        }()

        // Copy once, mutate the local copy (no CoW per iteration), assign back once.
        // Without this, each subscript write to the @Published array triggers a
        // separate CoW copy — O(n) per slot when slotsToWrite > 1.
        var localBuffer = levelBuffer
        var localWriteIndex = writeIndex
        let previous = lastBufferedLevel
        if slotsToWrite > 1 {
            // Interpolate intermediate slots so the buffer fills wall-clock
            // time rather than once per callback. Mirrors the
            // `reusableInterpolatedColumnData` path in the spectrogram adapter.
            localBuffer.withUnsafeMutableBufferPointer { buf in
                for step in 1...slotsToWrite {
                    let mix = Float(step) / Float(slotsToWrite)
                    localWriteIndex = (localWriteIndex + 1) % buf.count
                    buf[localWriteIndex] = previous * (1.0 - mix) + safeLevel * mix
                }
            }
        } else {
            localWriteIndex = (localWriteIndex + 1) % localBuffer.count
            localBuffer[localWriteIndex] = safeLevel
        }
        writeIndex = localWriteIndex
        levelBuffer = localBuffer

        lastUpdateTimestamp = now
        lastBufferedLevel = safeLevel
    }
}

/// Pure renderer for the level-history chart. Reads its rolling buffer from a
/// shared `LevelHistoryStore` so the tile and fullscreen views stay continuous.
struct LevelHistoryView: View {
    @ObservedObject var store: LevelHistoryStore
    var settings: [String: String]

    private var useWidgetOverrides: Bool { WidgetSettings.usesWidgetOverrides(settings) }
    var timeSpan: SpectrogramTimeSpan {
        let fallback = WidgetSettings.defaultTimeSpanSeconds
        guard useWidgetOverrides else {
            return SpectrogramTimeSpan(rawValue: fallback) ?? .seconds5
        }
        let raw = Int(settings["timeSpan"] ?? String(fallback)) ?? fallback
        return SpectrogramTimeSpan(rawValue: raw) ?? SpectrogramTimeSpan(rawValue: fallback) ?? .seconds5
    }

    // AudioEngine liefert bereits kalibrierte dB SPL Werte
    let dbOffset: Float = 0.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, size in
                    let levelBuffer = store.levelBuffer
                    let writeIndex = store.writeIndex
                    guard !levelBuffer.isEmpty else { return }

                    let width = size.width
                    let height = size.height
                    let count = levelBuffer.count

                    let leftPadding: CGFloat = 36
                    let rightPadding: CGFloat = 8
                    let topPadding: CGFloat = 8
                    let bottomPadding: CGFloat = 20
                    let chartRect = CGRect(
                        x: leftPadding,
                        y: topPadding,
                        width: max(1, width - leftPadding - rightPadding),
                        height: max(1, height - topPadding - bottomPadding)
                    )

                    let minDB = Double(WidgetSettings.chartYMinDB(settings))
                    let maxDB = Double(WidgetSettings.chartYMaxDB(settings))
                    let majorTicks = ScientificAxis.majorTicks(min: minDB, max: maxDB, targetTicks: 9)
                    let minorTicks = ScientificAxis.minorTicks(major: majorTicks, subdivisions: 2)

                    for tick in minorTicks where tick >= minDB && tick <= maxDB {
                        let yNorm = ScientificAxis.normalized(tick, min: minDB, max: maxDB)
                        let y = chartRect.maxY - CGFloat(yNorm) * chartRect.height
                        var grid = Path()
                        grid.move(to: CGPoint(x: chartRect.minX, y: y))
                        grid.addLine(to: CGPoint(x: chartRect.maxX, y: y))
                        context.stroke(grid, with: .color(ScientificChartPalette.gridMinor), lineWidth: 0.5)
                    }

                    for tick in majorTicks where tick >= minDB && tick <= maxDB {
                        let yNorm = ScientificAxis.normalized(tick, min: minDB, max: maxDB)
                        let y = chartRect.maxY - CGFloat(yNorm) * chartRect.height
                        var grid = Path()
                        grid.move(to: CGPoint(x: chartRect.minX, y: y))
                        grid.addLine(to: CGPoint(x: chartRect.maxX, y: y))
                        context.stroke(grid, with: .color(ScientificChartPalette.gridMajor), lineWidth: 0.8)

                        let label = Text("\(Int(tick))").font(.readout(size: 9, weight: .regular)).foregroundColor(ScientificChartPalette.axis)
                        context.draw(label, at: CGPoint(x: chartRect.minX - 16, y: y))
                    }

                    let timeDivisions = 5
                    for division in 0...timeDivisions {
                        let x = chartRect.minX + CGFloat(division) / CGFloat(timeDivisions) * chartRect.width
                        var vGrid = Path()
                        vGrid.move(to: CGPoint(x: x, y: chartRect.minY))
                        vGrid.addLine(to: CGPoint(x: x, y: chartRect.maxY))
                        context.stroke(vGrid, with: .color(ScientificChartPalette.gridMinor), lineWidth: 0.5)

                        let secondsFromNow = Double(timeSpan.rawValue) * (Double(division) / Double(timeDivisions) - 1.0)
                        let label = Text(String(format: "%.1fs", secondsFromNow))
                            .font(.readout(size: 8, weight: .regular))
                            .foregroundColor(ScientificChartPalette.axis)
                        context.draw(label, at: CGPoint(x: x, y: chartRect.maxY + 10))
                    }

                    let offsetSamples = 0
                    let rawValues: [Float] = (0..<count).map { i in
                        let index = (writeIndex + offsetSamples - i + 2 * count) % count
                        return levelBuffer[index]
                    }
                    func xFor(_ i: Int) -> CGFloat {
                        chartRect.minX + chartRect.width * CGFloat(i) / CGFloat(max(count - 1, 1))
                    }
                    func yFor(_ v: Float) -> CGFloat {
                        let level = Double(v + dbOffset)
                        let clampedLevel = min(max(level, minDB), maxDB)
                        let yNorm = ScientificAxis.normalized(clampedLevel, min: minDB, max: maxDB)
                        return chartRect.maxY - CGFloat(yNorm) * chartRect.height
                    }

                    // Slots never written hold the pre-fill sentinel (-120 dB).
                    // Render those as a gap — breaking the line — instead of a
                    // plunge to the axis floor, which otherwise reads as a sudden
                    // silence at the leading edge of a partially-filled buffer.
                    let dataFloor: Float = -119.0
                    var runStart: Int? = nil
                    func flushRun(_ end: Int) {
                        defer { runStart = nil }
                        guard let start = runStart, end >= start else { return }
                        // A run of one valid sample (isolated between gaps) would
                        // otherwise be a move-only path with no visible stroke;
                        // draw it as a small dot so a lone reading still shows.
                        if start == end {
                            let p = CGPoint(x: xFor(start), y: yFor(rawValues[start]))
                            let dot = Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3))
                            context.fill(dot, with: .color(ScientificChartPalette.series))
                            return
                        }
                        var line = Path()
                        for i in start...end {
                            let p = CGPoint(x: xFor(i), y: yFor(rawValues[i]))
                            if i == start { line.move(to: p) } else { line.addLine(to: p) }
                        }
                        var fill = line
                        fill.addLine(to: CGPoint(x: xFor(end), y: chartRect.maxY))
                        fill.addLine(to: CGPoint(x: xFor(start), y: chartRect.maxY))
                        fill.closeSubpath()
                        context.fill(fill, with: .color(ScientificChartPalette.fill))
                        context.stroke(line, with: .color(ScientificChartPalette.series), lineWidth: 1.6)
                    }
                    for i in 0..<count {
                        if rawValues[i] > dataFloor {
                            if runStart == nil { runStart = i }
                        } else {
                            flushRun(i - 1)
                        }
                    }
                    flushRun(count - 1)

                    var axisPath = Path()
                    axisPath.move(to: CGPoint(x: chartRect.minX, y: chartRect.minY))
                    axisPath.addLine(to: CGPoint(x: chartRect.minX, y: chartRect.maxY))
                    axisPath.addLine(to: CGPoint(x: chartRect.maxX, y: chartRect.maxY))
                    context.stroke(axisPath, with: .color(ScientificChartPalette.axis), lineWidth: 1.0)
                }
            }
            .drawingGroup()
        }
    }
}
