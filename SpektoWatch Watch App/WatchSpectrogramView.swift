import SwiftUI
import Combine

struct WatchSpectrogramView: View {
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager
    @EnvironmentObject var audioEngine: WatchAudioEngine
    @State private var frames: [[Float]] = []
    @State private var zoomLevel: Double = 1.0
    @State private var debugCounter: Int = 0
    @State private var latestFrequencies: [Float] = []
    @State private var latestSampleRate: Double = 44100.0
    @State private var latestMagnitudesCount: Int = 1024
    @FocusState private var isFocused: Bool

    private let maxFrames = 60
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

                    for (i, magnitudes) in frames.enumerated() {
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

                VStack {
                    Spacer()

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

    private var recordButton: some View {
        Button(action: {
            if audioEngine.isRecording {
                audioEngine.stopRecording()
                connectivityManager.requestRecordingStop()
            } else {
                audioEngine.startRecording()
                connectivityManager.requestRecordingStart()
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
        debugCounter += 1
        if debugCounter % 60 == 0 {
            let minVal = data.magnitudes.min() ?? 0
            let maxVal = data.magnitudes.max() ?? 0
            let avgVal = data.magnitudes.reduce(0, +) / Float(data.magnitudes.count)
            print("[WatchView] Input Range: [\(String(format: "%.1f", minVal)), \(String(format: "%.1f", maxVal))] dB, Avg: \(String(format: "%.1f", avgVal)) dB")
        }
        frames.append(data.magnitudes)
        latestFrequencies = data.frequencies
        latestSampleRate = data.sampleRate
        latestMagnitudesCount = data.magnitudes.count
        if frames.count > maxFrames { frames.removeFirst() }
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
