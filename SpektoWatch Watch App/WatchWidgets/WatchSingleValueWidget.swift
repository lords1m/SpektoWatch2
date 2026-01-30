import SwiftUI

struct WatchSingleValueWidget: View {
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager
    @EnvironmentObject var audioEngine: WatchAudioEngine

    let valueType: WatchSingleValueType

    @State private var currentValue: Float = 0.0
    @State private var isActive: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.6))

                VStack(spacing: 1) {
                    // Value
                    Text(displayValue)
                        .font(.system(size: fontSize(for: geometry.size), weight: .bold, design: .monospaced))
                        .foregroundColor(isActive ? valueColor : .gray)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    // Label
                    Text(valueType.displayName)
                        .font(.system(size: max(8, geometry.size.height * 0.18)))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                .padding(2)
            }
        }
        .onReceive(audioEngine.$currentSpectrogramData) { data in
            guard audioEngine.isRecording, let data = data else {
                if !connectivityManager.isReachable || connectivityManager.spectrogramData == nil {
                    isActive = false
                }
                return
            }
            updateValue(from: data)
            isActive = true
        }
        .onReceive(connectivityManager.$spectrogramData) { data in
            guard !audioEngine.isRecording, let data = data else {
                if !audioEngine.isRecording {
                    isActive = false
                }
                return
            }
            updateValue(from: data)
            isActive = true
        }
    }

    private var displayValue: String {
        guard isActive else { return "--" }
        return String(format: "%.1f", currentValue)
    }

    private func fontSize(for size: CGSize) -> CGFloat {
        let minDimension = min(size.width, size.height)
        return max(12, minDimension * 0.45)
    }

    private var valueColor: Color {
        if currentValue > 85 { return .red }
        if currentValue > 70 { return .orange }
        if currentValue > 55 { return .yellow }
        return .green
    }

    private func updateValue(from data: SpectrogramData) {
        switch valueType {
        case .laeq:
            currentValue = data.levels["LAeq"] ?? data.broadbandLevel
        case .lceq:
            currentValue = data.levels["LCeq"] ?? data.broadbandLevel
        case .lzeq:
            currentValue = data.levels["LZeq"] ?? data.broadbandLevel
        case .lafMax:
            currentValue = data.levels["LAFmax"] ?? data.levels["LAF"] ?? data.broadbandLevel
        case .lafMin:
            currentValue = data.levels["LAFmin"] ?? data.levels["LAF"] ?? data.broadbandLevel
        case .lcfMax:
            currentValue = data.levels["LCFmax"] ?? data.levels["LCF"] ?? data.broadbandLevel
        case .lcfMin:
            currentValue = data.levels["LCFmin"] ?? data.levels["LCF"] ?? data.broadbandLevel
        }
    }
}
