import SwiftUI
import Combine

struct WatchLevelMeterWidget: View {
    @EnvironmentObject var audioEngine: WatchAudioEngine
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager

    @State private var currentLevel: Float = -60.0
    @State private var unitLabel: String = "dB(Z)"

    private let minDB: Float = -60.0
    private let maxDB: Float = 0.0

    var body: some View {
        GeometryReader { geometry in
            let isVertical = geometry.size.height > geometry.size.width

            ZStack {
                if isVertical {
                    verticalMeter(size: geometry.size)
                } else {
                    horizontalMeter(size: geometry.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(audioEngine.$liveData.compactMap { $0 }) { data in
            currentLevel = data.broadbandLevel
            unitLabel = unitLabel(for: data)
        }
    }

    @ViewBuilder
    private func verticalMeter(size: CGSize) -> some View {
        let normalized = CGFloat((currentLevel - minDB) / (maxDB - minDB)).clamped(to: 0...1)
        let barHeight = size.height * 0.85
        let barWidth = size.width * 0.6

        VStack(spacing: 2) {
            // dB Label
            Text(String(format: "%.0f %@", currentLevel, unitLabel))
                .font(.system(size: min(size.width * 0.3, 14), weight: .bold, design: .monospaced))
                .foregroundColor(levelColor(normalized))

            // Vertical bar
            ZStack(alignment: .bottom) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: barWidth, height: barHeight)

                // Level fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(levelGradient)
                    .frame(width: barWidth, height: barHeight * normalized)
            }
        }
        .padding(1)
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
                    .fill(Color.white.opacity(0.18))
                    .frame(width: barWidth, height: barHeight)

                // Level fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(levelGradient)
                    .frame(width: barWidth * normalized, height: barHeight)
            }

            // dB Label
            Text(String(format: "%.0f %@", currentLevel, unitLabel))
                .font(.system(size: min(size.height * 0.4, 14), weight: .bold, design: .monospaced))
                .foregroundColor(levelColor(normalized))
                .frame(width: size.width * 0.25)
        }
        .padding(1)
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

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
