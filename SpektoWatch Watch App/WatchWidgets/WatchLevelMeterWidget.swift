import SwiftUI
import Combine

struct WatchLevelMeterWidget: View {
    var orientation: LevelMeterOrientation = .default

    @EnvironmentObject var audioEngine: WatchAudioEngine
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager

    @State private var currentLevel: Float = -60.0
    @State private var unitLabel: String = "dB(Z)"

    private let minDB: Float = 30.0
    private let maxDB: Float = 110.0

    var body: some View {
        GeometryReader { geometry in
            Group {
                if orientation == .vertical {
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
        let barWidth = size.width * 0.55

        HStack(spacing: 2) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.14))
                RoundedRectangle(cornerRadius: 2)
                    .fill(levelGradient)
                    .frame(height: max(2, size.height * normalized))
            }
            .frame(width: barWidth)

            Text(String(format: "%.0f", currentLevel))
                .font(.system(size: min(size.width * 0.28, 11), weight: .bold, design: .monospaced))
                .foregroundColor(levelColor(normalized))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func horizontalMeter(size: CGSize) -> some View {
        let normalized = CGFloat((currentLevel - minDB) / (maxDB - minDB)).clamped(to: 0...1)
        let barHeight = min(size.height * 0.55, 14)

        HStack(spacing: 3) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.14))
                RoundedRectangle(cornerRadius: 2)
                    .fill(levelGradient)
                    .frame(width: max(2, size.width * 0.72 * normalized), height: barHeight)
            }
            .frame(height: barHeight)

            Text(String(format: "%.0f %@", currentLevel, unitLabel))
                .font(.system(size: min(size.height * 0.38, 10), weight: .bold, design: .monospaced))
                .foregroundColor(levelColor(normalized))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 2)
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
