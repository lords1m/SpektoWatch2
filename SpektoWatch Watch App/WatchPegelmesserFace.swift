import SwiftUI
import Combine

/// Pegelmesser watch face from `design_handoff_spektowatch_redesign/README.md § 6a`:
/// big LAF number in phosphor green, dB(A) unit, peak bar with
/// green→yellow→red gradient, MIN/MAX line.
///
/// Reads from the existing `WatchAudioEngine.liveData` stream — no
/// new data plumbing.
struct WatchPegelmesserFace: View {
    @EnvironmentObject private var audioEngine: WatchAudioEngine
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager

    @State private var laf: Float = -120
    @State private var peakDB: Float = -120
    @State private var minDB: Float = .infinity
    @State private var maxDB: Float = -.infinity
    @State private var unitLabel: String = "dB(A)"

    /// Phosphor green from the iOS redesign accent palette.
    private let phosphor = Color(red: 0.45, green: 0.93, blue: 0.55)
    /// Peak-bar range in dB.
    private let barMinDB: Float = 30
    private let barMaxDB: Float = 110

    var body: some View {
        ZStack {
            WatchAppBackground().ignoresSafeArea()

            VStack(spacing: 4) {
                Spacer(minLength: 4)

                Text(displayValue)
                    .font(.system(size: 56, weight: .ultraLight, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(isLive ? phosphor : .white.opacity(0.4))
                    .kerning(-2)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text(unitLabel)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.55))

                Spacer(minLength: 4)

                peakBar

                HStack {
                    minMaxLabel("MIN", value: minDB)
                    Spacer()
                    minMaxLabel("MAX", value: maxDB)
                }
                .padding(.horizontal, 6)
                .padding(.top, 2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("watchPegelmesserFace")
        .onReceive(audioEngine.$liveData.compactMap { $0 }) { data in
            ingest(data)
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
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.45, green: 0.93, blue: 0.55), // green
                                Color(red: 0.99, green: 0.84, blue: 0.27), // amber
                                Color(red: 0.93, green: 0.38, blue: 0.30)  // red
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(2, geo.size.width * CGFloat(fraction)))
            }
        }
        .frame(height: 5)
        .padding(.horizontal, 2)
    }

    private func minMaxLabel(_ caption: String, value: Float) -> some View {
        HStack(spacing: 4) {
            Text(caption)
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.45))
            Text(value.isFinite && value > -120 && value < 200
                 ? String(format: "%.0f", value)
                 : "—")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func barFraction(for db: Float) -> Float {
        let clamped = min(max(db, barMinDB), barMaxDB)
        return (clamped - barMinDB) / (barMaxDB - barMinDB)
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
