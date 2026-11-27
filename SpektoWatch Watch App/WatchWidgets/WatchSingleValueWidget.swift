import SwiftUI

struct WatchSingleValueWidget: View {
    @Environment(WatchAudioEngine.self) private var audioEngine

    let valueType: WatchSingleValueType
    var refreshRate: SingleValueRefreshRate = .default

    @State private var currentValue: Float = 0.0
    @State private var isActive: Bool = false
    @ScaledMetric(relativeTo: .title3) private var dynamicTypeScale: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 1) {
                    Text(displayValue)
                        .font(.system(size: fontSize(for: geometry.size) * dynamicTypeScale, weight: .bold, design: .monospaced))
                        .foregroundStyle(isActive ? valueColor : .secondary.opacity(0.75))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    if isActive {
                        Text(unitLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Bind to the unified data stream — `WatchAudioEngine.liveData` already
        // reflects whichever mode is active (companion vs. wearableMic).
        .task(id: "\(valueType.rawValue)-\(refreshRate.rawValue)") {
            await ObservationTrackingLoop.observeThrottled(minimumInterval: refreshRate.minimumInterval) {
                audioEngine.liveData
            } onUpdate: { data in
                guard let data else {
                    isActive = false
                    return
                }
                updateValue(from: data)
                isActive = true
            }
        }
    }

    private var displayValue: String {
        guard isActive else { return "--" }
        return currentValue.formatted(.number.precision(.fractionLength(1)))
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
