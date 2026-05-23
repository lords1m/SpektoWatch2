import SwiftUI
import Combine

struct WatchSpectrogramView: View {
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager
    @EnvironmentObject var audioEngine: WatchAudioEngine
    private static let maxFrames = 60
    @State private var frames: RingBuffer<[Float]> = RingBuffer(capacity: WatchSpectrogramView.maxFrames)
    @State private var zoomLevel: Double = 1.0
    #if DEBUG
    @State private var debugCounter: Int = 0
    #endif
    @State private var latestFrequencies: [Float] = []
    @State private var latestSampleRate: Double = 44100.0
    @State private var latestMagnitudesCount: Int = 1024
    @FocusState private var isFocused: Bool

    private let maxFrames = WatchSpectrogramView.maxFrames
    private let displayBins = 40
    private let minDB: Float = -180.0
    private let maxDB: Float = -40.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                Canvas { context, size in
                    let width = size.width
                    let height = size.height
                    let colWidth = width / CGFloat(maxFrames)
                    let rowHeight = height / CGFloat(displayBins)

                    let orderedFrames = frames.inOrder()
                    for (i, magnitudes) in orderedFrames.enumerated() {
                        let x = CGFloat(i) * colWidth
                        let effectiveCount = Int(Double(magnitudes.count) * zoomLevel)
                        let chunkSize = max(1, effectiveCount / displayBins)

                        for f in 0..<displayBins {
                            let start = f * chunkSize
                            let end = min(start + chunkSize, effectiveCount)
                            let mag = (start < end && start < magnitudes.count)
                                ? (magnitudes[start..<min(end, magnitudes.count)].max() ?? minDB)
                                : minDB
                            let normalized = (mag - minDB) / (maxDB - minDB)

                            if normalized > 0.05 {
                                let color = spectrogramColor(Double(normalized))
                                let y = height - CGFloat(f + 1) * rowHeight
                                let rect = CGRect(x: x, y: y, width: colWidth + 0.5, height: rowHeight + 0.5)
                                context.fill(Path(rect), with: .color(color))
                            }
                        }
                    }
                }
                .ignoresSafeArea()

                axisLabels

                VStack(spacing: 0) {
                    topStatusStrip
                    Spacer()
                    bottomStftPill
                    HStack {
                        Circle()
                            .fill(audioEngine.isRecording ? Color.red : (connectivityManager.isReachable ? Color.green : Color.gray))
                            .frame(width: 4, height: 4)
                            .animation(.easeInOut(duration: 0.3), value: audioEngine.isRecording)
                        Spacer()
                        recordButton
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .accessibilityIdentifier("watchSpectrogramView")
            .focusable()
            .focused($isFocused)
            .digitalCrownRotation($zoomLevel, from: 0.1, through: 1.0, by: 0.05, sensitivity: .medium, isContinuous: false)
            .onAppear { isFocused = true }
        }
        // Single source: WatchAudioEngine.liveData reflects whichever mode is
        // active (companion vs. wearableMic). No branching.
        .onReceive(audioEngine.$liveData.compactMap { $0 }) { data in
            processSpectrogramData(data)
        }
    }

    // MARK: - Redesign chrome strips

    private var topStatusStrip: some View {
        HStack(spacing: 6) {
            PulsingDot(active: audioEngine.isRecording || connectivityManager.isReachable)
            TimelineView(.everyMinute) { context in
                Text(timeString(from: context.date))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 4)
            Text("DCT")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.black.opacity(0.55))
        )
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var bottomStftPill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(red: 0.45, green: 0.93, blue: 0.55))
                .frame(width: 4, height: 4)
            Text("STFT · \(stftBlockSize)")
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .padding(.bottom, 2)
    }

    private var stftBlockSize: Int {
        max(64, latestMagnitudesCount * 2)
    }

    private func timeString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private var recordButton: some View {
        Button(action: {
            if audioEngine.isRecording {
                audioEngine.stopRecording()
                connectivityManager.requestWearableRecordingStop()
            } else {
                connectivityManager.requestWearableRecordingStart()
                audioEngine.startRecording()
            }
            WKInterfaceDevice.current().play(.success)
        }) {
            Image(systemName: audioEngine.isRecording ? "stop.fill" : "record.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(
                        audioEngine.isRecording
                            ? Color.red.opacity(0.80)
                            : WatchStylePalette.accentBlue.opacity(0.80)
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private func processSpectrogramData(_ data: SpectrogramData) {
        let visualMagnitudes = data.visualMagnitudes ?? data.magnitudes
        #if DEBUG
        // Periodic range probe — kept under DEBUG so neither the counter nor
        // the `reduce(0, +)` over a 1024-element array runs on every frame in
        // release builds. The watch's main thread is already constrained;
        // gratuitous per-frame work shows up as battery drain.
        debugCounter += 1
        if debugCounter % 60 == 0 {
            let minVal = visualMagnitudes.min() ?? 0
            let maxVal = visualMagnitudes.max() ?? 0
            let avgVal = visualMagnitudes.reduce(0, +) / Float(max(visualMagnitudes.count, 1))
            print("[WatchView] Input Range: [\(String(format: "%.1f", minVal)), \(String(format: "%.1f", maxVal))] dB, Avg: \(String(format: "%.1f", avgVal)) dB")
        }
        #endif
        // `frames` is a fixed-capacity ring buffer (capacity = maxFrames) —
        // `append` is O(1) and drops the oldest slot in place when full,
        // replacing the previous O(n) `removeFirst()` per frame.
        frames.append(visualMagnitudes)
        latestFrequencies = data.visualFrequencies ?? data.frequencies
        latestSampleRate = data.sampleRate
        latestMagnitudesCount = visualMagnitudes.count
    }

    /// Tatsächlich angezeigte Max-Frequenz unter Berücksichtigung des Zoom-Levels
    private var displayedMaxFreq: Float {
        // effectiveCount = magnitudes.count * zoomLevel
        // Max-Frequenz = zoomLevel * Nyquist (= sampleRate / 2)
        let nyquist = Float(latestSampleRate) / 2.0
        return nyquist * Float(zoomLevel)
    }

    // Höhe der X-Achsen-Zeile (Record-Button-Inset 22 + Schriftgröße ~9)
    private let xAxisHeight: CGFloat = 31

    private var axisLabels: some View {
        let maxFreq = displayedMaxFreq

        return ZStack {
            // Y-Achse: Frequenz-Ticks, LINEAR positioniert.
            // Unterer Bereich (xAxisHeight) bleibt frei für X-Achse.
            GeometryReader { geometry in
                let plotHeight = geometry.size.height - xAxisHeight
                let ticks = linearFreqTicks(max: maxFreq)

                ForEach(ticks, id: \.self) { tick in
                    let normalized = CGFloat(tick / maxFreq)
                    let y = plotHeight - normalized * plotHeight
                    Text(tickLabel(for: tick))
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .position(x: 14, y: y)
                }
            }

            // X-Achse: Zeit-Ticks entlang der Unterkante
            VStack {
                Spacer()

                HStack {
                    let totalSeconds = timeWindowSeconds(frameCount: frames.count, maxCount: maxFrames)
                    let tickLabels = timeTickLabels(totalSeconds: totalSeconds)
                    Text(tickLabels[0])
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text(tickLabels[1])
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text(tickLabels[2])
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 22)
            }
        }
    }

    /// Erzeugt sinnvolle Frequenz-Ticks für lineare Darstellung
    private func linearFreqTicks(max: Float) -> [Float] {
        let candidates: [Float] = [500, 1000, 2000, 3000, 4000, 5000,
                                   6000, 8000, 10000, 12000, 15000, 18000, 20000]
        // Nur Ticks im sichtbaren Bereich, nicht zu dicht (mind. 15% Abstand)
        var ticks: [Float] = []
        for c in candidates {
            guard c > 0 && c < max * 0.95 else { continue }
            let normalized = c / max
            // Vermeide Ticks zu nah am Rand oder aneinander
            if normalized > 0.08, ticks.last.map({ (c - $0) / max > 0.12 }) ?? true {
                ticks.append(c)
            }
        }
        // Maximal 5 Ticks auf dem kleinen Watch-Display
        if ticks.count > 5 {
            let step = ticks.count / 5
            ticks = stride(from: 0, to: ticks.count, by: step).map { ticks[$0] }
        }
        return ticks
    }

    private func tickLabel(for frequency: Float) -> String {
        if frequency >= 1000 {
            return String(format: "%.0fk", frequency / 1000)
        }
        return String(format: "%.0f", frequency)
    }

    private func timeWindowSeconds(frameCount: Int, maxCount: Int) -> Double {
        let count = max(frameCount, 2)
        let fftSize = max(latestMagnitudesCount * 2, 2)
        let frameDuration = Double(fftSize) / max(latestSampleRate, 1.0)
        let windowCount = min(count, maxCount)
        return Double(windowCount - 1) * frameDuration
    }

    private func timeTickLabels(totalSeconds: Double) -> [String] {
        let clamped = max(totalSeconds, 0.0)
        let mid = clamped * 0.5
        return [timeLabel(clamped), timeLabel(mid), timeLabel(0)]
    }

    private func timeLabel(_ seconds: Double) -> String {
        if seconds <= 0 { return "0s" }
        if seconds >= 10 { return String(format: "%.0fs", seconds) }
        if seconds >= 1 { return String(format: "%.1fs", seconds) }
        return String(format: "%.2fs", seconds)
    }

    private struct PulsingDot: View {
        let active: Bool
        private let phosphor = Color(red: 0.45, green: 0.93, blue: 0.55)

        var body: some View {
            TimelineView(.animation(minimumInterval: 0.08, paused: !active)) { context in
                let phase = active
                    ? 0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * .pi * 1.2)
                    : 0.0
                Circle()
                    .fill(phosphor)
                    .frame(width: 5, height: 5)
                    .opacity(active ? (0.40 + 0.60 * phase) : 0.35)
                    .shadow(color: phosphor.opacity(active ? 0.7 : 0), radius: active ? (1 + 3 * phase) : 0)
            }
        }
    }

    private func spectrogramColor(_ value: Double) -> Color {
        if value <= 0.0 { return .black }
        if value < 0.2 {
            return Color(red: 0, green: 0, blue: value * 2.5)
        } else if value < 0.5 {
            let t = (value - 0.2) / 0.3
            return Color(red: 0, green: t, blue: 1.0)
        } else {
            let t = (value - 0.5) / 0.5
            return Color(red: t, green: 1.0 - t * 0.5, blue: 1.0 - t)
        }
    }
}
