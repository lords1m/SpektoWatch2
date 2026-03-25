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

                    // Label
                    Text(valueType.displayName)
                        .font(.system(size: max(8, geometry.size.height * 0.18)))
                        .foregroundColor(.secondary.opacity(0.9))
                        .lineLimit(1)
                }
                .padding(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .watchGlassCard(cornerRadius: 10)
        }
        .onReceive(connectivityManager.$spectrogramData) { data in
            guard let data = data else {
                isActive = false
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
        currentValue = WatchValueMapping.value(for: valueType, data: data)
    }
}
