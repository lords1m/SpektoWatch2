import SwiftUI

struct WatchLevelMeterWidget: View {
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager
    @EnvironmentObject var audioEngine: WatchAudioEngine

    @State private var currentLevel: Float = -60.0

    private let minDB: Float = -60.0
    private let maxDB: Float = 0.0

    var body: some View {
        GeometryReader { geometry in
            let isVertical = geometry.size.height > geometry.size.width

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.8))

                if isVertical {
                    verticalMeter(size: geometry.size)
                } else {
                    horizontalMeter(size: geometry.size)
                }
            }
        }
        .onReceive(audioEngine.$currentSpectrogramData) { data in
            guard audioEngine.isRecording, let data = data else { return }
            currentLevel = data.broadbandLevel
        }
        .onReceive(connectivityManager.$spectrogramData) { data in
            guard !audioEngine.isRecording, let data = data else { return }
            currentLevel = data.broadbandLevel
        }
    }

    @ViewBuilder
    private func verticalMeter(size: CGSize) -> some View {
        let normalized = CGFloat((currentLevel - minDB) / (maxDB - minDB)).clamped(to: 0...1)
        let barHeight = size.height * 0.85
        let barWidth = size.width * 0.6

        VStack(spacing: 2) {
            // dB Label
            Text(String(format: "%.0f", currentLevel))
                .font(.system(size: min(size.width * 0.3, 14), weight: .bold, design: .monospaced))
                .foregroundColor(levelColor(normalized))

            // Vertical bar
            ZStack(alignment: .bottom) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: barWidth, height: barHeight)

                // Level fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(levelGradient)
                    .frame(width: barWidth, height: barHeight * normalized)
            }
        }
        .padding(2)
    }

    @ViewBuilder
    private func horizontalMeter(size: CGSize) -> some View {
        let normalized = CGFloat((currentLevel - minDB) / (maxDB - minDB)).clamped(to: 0...1)
        let barWidth = size.width * 0.7
        let barHeight = size.height * 0.4

        HStack(spacing: 4) {
            // Horizontal bar
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: barWidth, height: barHeight)

                // Level fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(levelGradient)
                    .frame(width: barWidth * normalized, height: barHeight)
            }

            // dB Label
            Text(String(format: "%.0f", currentLevel))
                .font(.system(size: min(size.height * 0.4, 14), weight: .bold, design: .monospaced))
                .foregroundColor(levelColor(normalized))
                .frame(width: size.width * 0.25)
        }
        .padding(2)
    }

    private var levelGradient: LinearGradient {
        LinearGradient(
            colors: [.green, .yellow, .orange, .red],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private func levelColor(_ normalized: CGFloat) -> Color {
        if normalized > 0.9 { return .red }
        if normalized > 0.7 { return .orange }
        if normalized > 0.5 { return .yellow }
        return .green
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
