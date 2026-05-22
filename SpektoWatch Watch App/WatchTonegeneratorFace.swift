import SwiftUI

/// Tongenerator watch face from `design_handoff_spektowatch_redesign/
/// README.md § 6c`: "FREQUENZ" eyebrow + big frequency readout + mini
/// glowing sine wave + PAUSE button + λ wavelength readout.
///
/// **Design preview only.** The watch target does not currently host
/// the tone generator's audio engine (the iOS-side `ToneGeneratorWidget`
/// owns the AVAudioEngine and the WatchConnectivity protocol does not
/// yet relay tone state). This view ships the visual face from the
/// redesign mock with a local @State so users can browse the design.
/// Wiring to the actual generator is tracked under follow-up work once
/// the iOS↔watch tone protocol exists.
struct WatchTonegeneratorFace: View {
    @State private var isPlaying: Bool = true
    @State private var frequencyHz: Double = 1000
    @State private var phaseOffset: Double = 0  // unused; TimelineView drives

    private let phosphor = Color(red: 0.45, green: 0.93, blue: 0.55)
    private let pauseRed = Color(red: 0.93, green: 0.38, blue: 0.30)
    private let speedOfSoundMS: Double = 343
    private let presets: [Double] = [440, 1000, 2000, 4000]

    var body: some View {
        ZStack {
            WatchAppBackground().ignoresSafeArea()

            VStack(spacing: 6) {
                Text("FREQUENZ")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.55))

                Button {
                    cyclePreset()
                } label: {
                    Text(frequencyLabel)
                        .font(.system(size: 32, weight: .ultraLight, design: .default))
                        .monospacedDigit()
                        .kerning(-1.0)
                        .foregroundStyle(phosphor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .buttonStyle(.plain)

                sineStrip
                    .frame(height: 34)

                pauseButton

                wavelengthReadout
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .accessibilityIdentifier("watchTonegeneratorFace")
    }

    // MARK: - Slots

    private var sineStrip: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
            Canvas { canvasCtx, size in
                let t = context.date.timeIntervalSinceReferenceDate
                drawSine(in: size, time: t, context: &canvasCtx)
            }
        }
    }

    private func drawSine(in size: CGSize, time: TimeInterval, context: inout GraphicsContext) {
        guard size.width > 1, size.height > 1 else { return }
        let amplitude = size.height * 0.35
        let midY = size.height * 0.5
        // Visual frequency on screen is decoupled from real Hz —
        // higher Hz → more cycles visible. Cap so it never aliases.
        let cyclesAcross = max(1.5, min(6.0, log10(frequencyHz / 100.0) * 2.5 + 1.0))
        let omega = (.pi * 2.0 * cyclesAcross) / size.width
        let phase = isPlaying ? time * 4.0 : 0.0  // 4 rad/s scroll speed

        var path = Path()
        let step: CGFloat = 1.5
        var x: CGFloat = 0
        while x <= size.width {
            let y = midY + CGFloat(sin(Double(x) * omega + phase)) * amplitude
            if x == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
            x += step
        }

        // Glow layer + line
        context.stroke(path, with: .color(phosphor.opacity(0.35)), lineWidth: 5)
        context.stroke(path, with: .color(phosphor), lineWidth: 1.8)
    }

    private var pauseButton: some View {
        Button {
            isPlaying.toggle()
            WKInterfaceDevice.current().play(.click)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(isPlaying ? "PAUSE" : "PLAY")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
            }
            .foregroundStyle(isPlaying ? pauseRed : phosphor)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                Capsule().fill((isPlaying ? pauseRed : phosphor).opacity(0.18))
            )
            .overlay(
                Capsule().strokeBorder(
                    (isPlaying ? pauseRed : phosphor).opacity(0.45),
                    lineWidth: 0.5
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var wavelengthReadout: some View {
        HStack(spacing: 4) {
            Text("λ")
                .font(.system(size: 11, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(.white.opacity(0.55))
            Text(wavelengthLabel)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    // MARK: - Formatting

    private var frequencyLabel: String {
        if frequencyHz >= 1000 {
            return String(format: "%.2f kHz", frequencyHz / 1000)
        }
        return String(format: "%.0f Hz", frequencyHz)
    }

    private var wavelengthLabel: String {
        let lambda = speedOfSoundMS / frequencyHz
        if lambda >= 1.0 {
            return String(format: "%.2f m", lambda)
        }
        return String(format: "%.1f cm", lambda * 100)
    }

    private func cyclePreset() {
        let idx = (presets.firstIndex(of: frequencyHz) ?? -1) + 1
        frequencyHz = presets[idx % presets.count]
        WKInterfaceDevice.current().play(.click)
    }
}
