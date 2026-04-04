import SwiftUI

struct WatchLevelMeterView: View {
    @EnvironmentObject private var audioEngine: WatchAudioEngine
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager

    private var isRecording: Bool { audioEngine.isRecording }
    @State private var levelHistory: [Float] = []
    @State private var unitLabel: String = "dB(Z)"

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
        .onReceive(audioEngine.$currentSpectrogramData) { data in
            guard audioEngine.isRecording, let data = data else { return }
            appendLevel(from: data)
        }
        .onReceive(connectivityManager.$spectrogramData) { data in
            guard !audioEngine.isRecording, let data = data else { return }
            appendLevel(from: data)
        }
    }

    private var recordButton: some View {
        Button(action: {
            if isRecording {
                audioEngine.stopRecording()
                connectivityManager.requestRecordingStop()
            } else {
                audioEngine.startRecording()
                connectivityManager.requestRecordingStart()
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

    private var axisLabels: some View {
        ZStack {
            VStack {
                HStack {
                    Text(unitLabel)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                }
                .padding(.leading, 4)
                .padding(.top, 4)

                Spacer()

                HStack {
                    Text("Past")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text("Now")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 6)
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
}
