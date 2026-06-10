import SwiftUI
import WatchKit

/// Tongenerator watch face: frequency readout, log-scaled frequency control,
/// animated sine preview, play/stop, and λ wavelength readout.
struct WatchTonegeneratorFace: View {
    @StateObject private var toneGenerator = WatchToneGenerator()
    @AppStorage(PersistenceKeys.ToneGenerator.frequency) private var storedFrequency: Double = 1000
    @AppStorage(PersistenceKeys.ToneGenerator.amplitude) private var storedAmplitude: Double = 0.5

    @State private var logFrequencyHz: Double = log10(1000)
    @FocusState private var crownFocused: Bool

    private let phosphor = Color(red: 0.45, green: 0.93, blue: 0.55)
    private let pauseRed = Color(red: 0.93, green: 0.38, blue: 0.30)
    private let speedOfSoundMS: Double = 343

    private let presetFrequencies: [(String, Float)] = [
        ("125", 125),
        ("250", 250),
        ("500", 500),
        ("1k", 1000),
        ("2k", 2000),
        ("4k", 4000),
        ("8k", 8000),
    ]

    var body: some View {
        ScrollView {
            ZStack {
                WatchAppBackground().ignoresSafeArea()

                VStack(spacing: 6) {
                    Text("FREQUENZ")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.55))

                    Text(frequencyLabel)
                        .font(.system(size: 28, weight: .ultraLight, design: .default))
                        .monospacedDigit()
                        .kerning(-1.0)
                        .foregroundStyle(phosphor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    frequencySlider

                    presetChips

                    sineStrip
                        .frame(height: 30)

                    pauseButton

                    wavelengthReadout
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
        .digitalCrownRotation(
            $logFrequencyHz,
            from: log10(20),
            through: log10(20_000),
            by: 0.02,
            sensitivity: .medium,
            isContinuous: true,
            isHapticFeedbackEnabled: true
        )
        .focused($crownFocused)
        .onAppear {
            toneGenerator.frequency = Float(storedFrequency)
            toneGenerator.amplitude = Float(storedAmplitude)
            logFrequencyHz = log10(Double(toneGenerator.frequency))
            crownFocused = true
        }
        .onChange(of: logFrequencyHz) { _, newLog in
            let hz = Float(pow(10, newLog))
            toneGenerator.frequency = hz
            storedFrequency = Double(hz)
        }
        .onChange(of: toneGenerator.frequency) { _, hz in
            let log = log10(Double(hz))
            if abs(log - logFrequencyHz) > 0.001 {
                logFrequencyHz = log
            }
            storedFrequency = Double(hz)
        }
        .onDisappear {
            toneGenerator.stop()
        }
        .accessibilityIdentifier("watchTonegeneratorFace")
    }

    // MARK: - Frequency controls

    private var frequencySlider: some View {
        VStack(spacing: 2) {
            Slider(value: $logFrequencyHz, in: log10(20)...log10(20_000))
                .tint(toneGenerator.isPlaying ? phosphor : .blue)
            HStack {
                Text("20")
                Spacer()
                Text("20k")
            }
            .font(.system(size: 8, weight: .regular, design: .monospaced))
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var presetChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(presetFrequencies, id: \.1) { preset in
                    Button {
                        applyFrequency(preset.1)
                        WKInterfaceDevice.current().play(.click)
                    } label: {
                        Text(preset.0)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                abs(toneGenerator.frequency - preset.1) / preset.1 < 0.05
                                    ? phosphor.opacity(0.35)
                                    : Color.white.opacity(0.08)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func applyFrequency(_ hz: Float) {
        toneGenerator.frequency = hz
        logFrequencyHz = log10(Double(hz))
        storedFrequency = Double(hz)
    }

    // MARK: - Wave preview

    private var sineStrip: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !toneGenerator.isPlaying)) { context in
            Canvas { canvasCtx, size in
                let t = context.date.timeIntervalSinceReferenceDate
                drawSine(in: size, time: t, context: &canvasCtx)
            }
        }
    }

    private func drawSine(in size: CGSize, time: TimeInterval, context: inout GraphicsContext) {
        guard size.width > 1, size.height > 1 else { return }
        let frequencyHz = Double(toneGenerator.frequency)
        let amplitude = size.height * 0.35
        let midY = size.height * 0.5
        let cyclesAcross = max(1.5, min(6.0, log10(frequencyHz / 100.0) * 2.5 + 1.0))
        let omega = (.pi * 2.0 * cyclesAcross) / size.width
        let phase = toneGenerator.isPlaying ? time * 4.0 : 0.0

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

        context.stroke(path, with: .color(phosphor.opacity(0.35)), lineWidth: 5)
        context.stroke(path, with: .color(phosphor), lineWidth: 1.8)
    }

    private var pauseButton: some View {
        Button {
            toneGenerator.toggle()
            WKInterfaceDevice.current().play(.click)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: toneGenerator.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(toneGenerator.isPlaying ? "PAUSE" : "PLAY")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
            }
            .foregroundStyle(toneGenerator.isPlaying ? pauseRed : phosphor)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                Capsule().fill((toneGenerator.isPlaying ? pauseRed : phosphor).opacity(0.18))
            )
            .overlay(
                Capsule().strokeBorder(
                    (toneGenerator.isPlaying ? pauseRed : phosphor).opacity(0.45),
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
        let frequencyHz = Double(toneGenerator.frequency)
        if frequencyHz >= 1000 {
            return String(format: "%.2f kHz", frequencyHz / 1000)
        }
        return String(format: "%.0f Hz", frequencyHz)
    }

    private var wavelengthLabel: String {
        let frequencyHz = Double(toneGenerator.frequency)
        let lambda = speedOfSoundMS / frequencyHz
        if lambda >= 1.0 {
            return String(format: "%.2f m", lambda)
        }
        return String(format: "%.1f cm", lambda * 100)
    }
}
