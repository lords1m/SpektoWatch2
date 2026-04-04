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
                VStack(spacing: 1) {
                    // Value
                    Text(displayValue)
                        .font(.system(size: fontSize(for: geometry.size), weight: .bold, design: .monospaced))
                        .foregroundColor(isActive ? valueColor : .secondary.opacity(0.75))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .padding(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(audioEngine.$currentSpectrogramData) { data in
            guard audioEngine.isRecording, let data = data else { return }
            updateValue(from: data)
            isActive = true
        }
        .onReceive(connectivityManager.$spectrogramData) { data in
            guard !audioEngine.isRecording else { return }
            guard let data = data else { isActive = false; return }
            updateValue(from: data)
            isActive = true
        }
    }

    private var displayValue: String {
        guard isActive else { return "--" }
        return String(format: "%.1f %@", currentValue, unitLabel)
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

    private var unitLabel: String {
        switch valueType {
        case .laeq, .lafMax, .lafMin:
            return "dB(A)"
        case .lceq, .lcfMax, .lcfMin:
            return "dB(C)"
        case .lzeq:
            return "dB(Z)"
        }
    }

    private func updateValue(from data: SpectrogramData) {
        currentValue = WatchValueMapping.value(for: valueType, data: data)
    }
}
