import SwiftUI
import Combine

struct WatchLevelMeterView: View {
    @EnvironmentObject private var audioEngine: WatchAudioEngine
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager

    private var isRecording: Bool { audioEngine.isRecording }
    @State private var levelHistory: [Float] = []
    @State private var unitLabel: String = "dB(Z)"
    @State private var latestSampleRate: Double = 44100.0
    @State private var latestMagnitudesCount: Int = 1024

    private let historyLength = 120
    private let minDB: Float = -120.0
    private let maxDB: Float = 0.0

    var body: some View {
        ZStack {
            WatchAppBackground().ignoresSafeArea()

            Canvas { context, size in
                guard levelHistory.count > 1 else { return }
                let width = size.width
                let height = size.height
                let step = width / CGFloat(max(historyLength - 1, 1))

                var path = Path()
                for (index, value) in levelHistory.enumerated() {
                    let normalized = clamp((value - minDB) / (maxDB - minDB), 0, 1)
                    let x = CGFloat(index) * step
                    let y = height - CGFloat(normalized) * height
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(path, with: .color(.white.opacity(0.8)), lineWidth: 1.2)
            }
            .ignoresSafeArea()

            axisLabels

            VStack {
                Spacer()

                HStack {
                    Circle()
                        .fill(isRecording ? Color.red : (connectivityManager.isReachable ? Color.green : Color.gray))
                        .frame(width: 4, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: isRecording)
                    Spacer()
                    recordButton
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 2)
            }
        }
        .accessibilityIdentifier("watchLevelMeterView")
        .onReceive(audioEngine.$liveData.compactMap { $0 }) { data in
            appendLevel(from: data)
        }
    }

    private var recordButton: some View {
        Button(action: {
            if isRecording {
                audioEngine.stopRecording()
                connectivityManager.requestWearableRecordingStop()
            } else {
                connectivityManager.requestWearableRecordingStart()
                audioEngine.startRecording()
            }
            WKInterfaceDevice.current().play(.success)
        }) {
            Image(systemName: isRecording ? "stop.fill" : "record.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(
                        isRecording
                            ? Color.red.opacity(0.80)
                            : WatchStylePalette.accentBlue.opacity(0.80)
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // Höhe der X-Achsen-Zeile (Record-Button-Inset 22 + Schriftgröße ~9)
    private let xAxisHeight: CGFloat = 31

    private var axisLabels: some View {
        ZStack {
            // Y-Achse: dB-Labels entlang der linken Kante.
            // Unterer Bereich (xAxisHeight) bleibt frei für X-Achse.
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("0")
                    Spacer()
                    Text("[\(unitLabel)]")
                    Spacer()
                    Text("\(Int(minDB))")
                }
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.leading, 2)
                .padding(.top, 6)
                .padding(.bottom, xAxisHeight)

                Spacer()
            }

            // X-Achse: Zeit-Ticks entlang der Unterkante
            VStack {
                Spacer()

                HStack {
                    let totalSeconds = timeWindowSeconds(sampleCount: levelHistory.count, maxCount: historyLength)
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

    private func appendLevel(from data: SpectrogramData) {
        levelHistory.append(data.broadbandLevel)
        if levelHistory.count > historyLength {
            levelHistory.removeFirst(levelHistory.count - historyLength)
        }
        unitLabel = unitLabel(for: data)
        latestSampleRate = data.sampleRate
        latestMagnitudesCount = data.magnitudes.count
    }

    private func clamp(_ value: Float, _ minValue: Float, _ maxValue: Float) -> Float {
        Swift.min(Swift.max(value, minValue), maxValue)
    }

    private func unitLabel(for data: SpectrogramData) -> String {
        let keys = data.levels.keys
        if keys.contains(where: { $0.hasPrefix("LA") }) { return "dB(A)" }
        if keys.contains(where: { $0.hasPrefix("LC") }) { return "dB(C)" }
        if keys.contains(where: { $0.hasPrefix("LZ") }) { return "dB(Z)" }
        return unitLabel(for: connectivityManager.frequencyWeighting)
    }

    private func unitLabel(for weighting: String) -> String {
        switch weighting.uppercased() {
        case "A": return "dB(A)"
        case "C": return "dB(C)"
        case "Z": return "dB(Z)"
        default: return "dB(A)"
        }
    }

    private func timeWindowSeconds(sampleCount: Int, maxCount: Int) -> Double {
        let count = max(sampleCount, 2)
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
}
