import SwiftUI
import Combine

/// Compact Pegelmesser block for the customizable meter grid.
struct WatchPegelmeterWidget: View {
    @EnvironmentObject private var audioEngine: WatchAudioEngine
    @Environment(\.watchTabLiveUpdatesActive) private var tabLiveUpdatesActive

    @State private var laf: Float = -120
    @State private var peakDB: Float = -120
    @State private var minDB: Float = .infinity
    @State private var maxDB: Float = -.infinity
    @State private var unitLabel: String = "dB(A)"

    private let phosphor = Color(red: 0.45, green: 0.93, blue: 0.55)
    private let peakBarRange: ClosedRange<Float> = 30...110

    var body: some View {
        VStack(spacing: 3) {
            Text(displayValue)
                .font(.system(size: 32, weight: .ultraLight, design: .default))
                .monospacedDigit()
                .foregroundStyle(isLive ? phosphor : .white.opacity(0.4))
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(unitLabel)
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.55))

            peakBar

            HStack {
                minMaxLabel("MIN", value: minDB)
                Spacer()
                minMaxLabel("MAX", value: maxDB)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .watchGlassCard(cornerRadius: 8)
        .onReceive(
            audioEngine.$liveData
                .compactMap { $0 }
                .throttledForWatchLiveDisplay()
        ) { data in
            guard tabLiveUpdatesActive else { return }
            ingest(data)
        }
        .onChange(of: audioEngine.isRecording) { _, isRecording in
            if isRecording { resetExtremes() }
        }
    }

    private var isLive: Bool { laf > -120 }

    private var displayValue: String {
        guard isLive else { return "—" }
        return String(format: "%.1f", laf)
    }

    private var peakBar: some View {
        GeometryReader { geo in
            let fraction = barFraction(for: max(peakDB, laf))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.45, green: 0.93, blue: 0.55),
                                Color(red: 0.99, green: 0.84, blue: 0.27),
                                Color(red: 0.93, green: 0.38, blue: 0.30)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(2, geo.size.width * CGFloat(fraction)))
            }
        }
        .frame(height: 4)
    }

    private func minMaxLabel(_ caption: String, value: Float) -> some View {
        HStack(spacing: 3) {
            Text(caption)
                .font(.system(size: 7, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            Text(value.isFinite && value > -120 && value < 200
                 ? String(format: "%.0f", value)
                 : "—")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func barFraction(for db: Float) -> Float {
        let clamped = min(max(db, peakBarRange.lowerBound), peakBarRange.upperBound)
        return (clamped - peakBarRange.lowerBound) /
            (peakBarRange.upperBound - peakBarRange.lowerBound)
    }

    private func resetExtremes() {
        minDB = .infinity
        maxDB = -.infinity
    }

    private func ingest(_ data: SpectrogramData) {
        let level = data.levels["LAF"]
            ?? data.levels["LAeq"]
            ?? data.broadbandLevel
        guard level.isFinite, level > -200 else { return }

        laf = level
        peakDB = data.levels["LCpeak"]
            ?? data.levels["LAFmax"]
            ?? level
        if level < minDB { minDB = level }
        if level > maxDB { maxDB = level }
        unitLabel = resolveUnit(from: data)
    }

    private func resolveUnit(from data: SpectrogramData) -> String {
        let keys = data.levels.keys
        if keys.contains(where: { $0.hasPrefix("LA") }) { return "dB(A)" }
        if keys.contains(where: { $0.hasPrefix("LC") }) { return "dB(C)" }
        if keys.contains(where: { $0.hasPrefix("LZ") }) { return "dB(Z)" }
        return unitLabel
    }
}
