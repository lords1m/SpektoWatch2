import SwiftUI
import Combine

/// Modular 4-slot watch face from `design_handoff_spektowatch_redesign/
/// README.md § 8`: hero LAF readout · mini spectrogram strip · PEAK
/// tile · Leq tile.
///
/// Reads from the existing `WatchAudioEngine.liveData` — same source as
/// `WatchPegelmesserFace` and `WatchSpectrogramView`.
struct WatchModularFace: View {
    @EnvironmentObject private var audioEngine: WatchAudioEngine
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager

    @State private var laf: Float = -120
    @State private var leq: Float = -120
    @State private var peak: Float = -120
    @State private var spectroFrames: RingBuffer<[Float]> = RingBuffer(capacity: 60)

    private let phosphor = Color(red: 0.45, green: 0.93, blue: 0.55)
    private let amber    = Color(red: 0.99, green: 0.84, blue: 0.27)
    private let stripHeight: CGFloat = 32

    var body: some View {
        ZStack {
            WatchAppBackground().ignoresSafeArea()

            VStack(spacing: 4) {
                heroSlot
                spectrogramStrip
                HStack(spacing: 4) {
                    metricTile(label: "PEAK", value: peak, color: amber)
                    metricTile(label: "LEQ",  value: leq,  color: phosphor)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .accessibilityIdentifier("watchModularFace")
        .onReceive(audioEngine.$liveData.compactMap { $0 }) { data in
            ingest(data)
        }
    }

    // MARK: - Slots

    private var heroSlot: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(format1(laf))
                .font(.system(size: 36, weight: .ultraLight, design: .default))
                .monospacedDigit()
                .foregroundStyle(isLive ? phosphor : .white.opacity(0.4))
                .kerning(-1.2)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("dB(A)")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 0)
        }
    }

    private var spectrogramStrip: some View {
        Canvas { context, size in
            guard spectroFrames.count > 0 else { return }
            let frames = spectroFrames.inOrder()
            let colW = size.width / CGFloat(spectroFrames.capacity)
            let displayBins = 16
            for (i, mags) in frames.enumerated() {
                guard !mags.isEmpty else { continue }
                let chunk = max(1, mags.count / displayBins)
                let rowH = size.height / CGFloat(displayBins)
                for b in 0..<displayBins {
                    let start = b * chunk
                    let end = min(start + chunk, mags.count)
                    guard start < end else { continue }
                    let mag = mags[start..<end].max() ?? -180
                    let normalized = max(0, min(1, (mag + 100) / 60))
                    guard normalized > 0.05 else { continue }
                    let x = CGFloat(i) * colW
                    let y = size.height - CGFloat(b + 1) * rowH
                    let color = stripColor(Double(normalized))
                    context.fill(
                        Path(CGRect(x: x, y: y, width: colW + 0.5, height: rowH + 0.5)),
                        with: .color(color)
                    )
                }
            }
        }
        .frame(height: stripHeight)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func metricTile(label: String, value: Float, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.55))
            Text(format0(value))
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(value > -120 && value.isFinite ? color : .white.opacity(0.35))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Data ingestion

    private var isLive: Bool { laf > -120 }

    private func ingest(_ data: SpectrogramData) {
        let level = data.levels["LAF"]
            ?? data.levels["LAeq"]
            ?? data.broadbandLevel
        guard level.isFinite, level > -200 else { return }

        laf = level
        leq = data.levels["LAeq"] ?? data.levels["LAFeq"] ?? level
        peak = data.levels["LCpeak"] ?? data.levels["LAFmax"] ?? max(peak, level)

        if !data.magnitudes.isEmpty {
            spectroFrames.append(data.magnitudes)
        }
    }

    private func format0(_ v: Float) -> String {
        guard v.isFinite, v > -120, v < 200 else { return "—" }
        return String(format: "%.0f", v)
    }

    private func format1(_ v: Float) -> String {
        guard v.isFinite, v > -120 else { return "—" }
        return String(format: "%.1f", v)
    }

    private func stripColor(_ t: Double) -> Color {
        if t < 0.33 {
            return Color(red: 0.12, green: 0.30, blue: 0.55)   // deep blue
        } else if t < 0.66 {
            let k = (t - 0.33) / 0.33
            return Color(red: 0.12 + k * 0.30, green: 0.30 + k * 0.55, blue: 0.55 - k * 0.20)
        } else {
            let k = (t - 0.66) / 0.34
            return Color(red: 0.42 + k * 0.55, green: 0.85, blue: 0.35 - k * 0.10)
        }
    }
}
