import SwiftUI

struct WatchSpectrogramView: View {
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager
    @EnvironmentObject var audioEngine: WatchAudioEngine
    @State private var frames: [[Float]] = []
    @State private var zoomLevel: Double = 1.0
    @State private var debugCounter: Int = 0
    @State private var latestFrequencies: [Float] = []
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
            .focusable()
            .focused($isFocused)
            .digitalCrownRotation($zoomLevel, from: 0.1, through: 1.0, by: 0.05, sensitivity: .medium, isContinuous: false)
            .onAppear { isFocused = true }
        }
        .onReceive(audioEngine.$currentSpectrogramData) { data in
            guard audioEngine.isRecording, let data = data else { return }
            processSpectrogramData(data)
        }
        .onReceive(connectivityManager.$spectrogramData) { data in
            guard !audioEngine.isRecording, let data = data else { return }
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
        if frames.count > maxFrames { frames.removeFirst() }
    }

    private var axisLabels: some View {
        let minFreq = latestFrequencies.min() ?? 0
        let maxFreq = latestFrequencies.max() ?? 0

        return ZStack {
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.0f Hz", maxFreq))
                        Text(String(format: "%.0f Hz", minFreq))
                    }
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
