import SwiftUI
import AVFoundation
import Combine

// MARK: - Tone Generator Engine

class ToneGenerator: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var srcNode: AVAudioSourceNode?

    @Published var isPlaying = false
    @Published var frequency: Float = 1000.0
    @Published var amplitude: Float = 0.5
    @Published var waveform: Waveform = .sine

    enum Waveform: String, CaseIterable {
        case sine = "Sinus"
        case square = "Rechteck"
        case sawtooth = "Sägezahn"
        case triangle = "Dreieck"
    }

    private let sampleRate: Double = 44100.0
    private var phase: Double = 0.0
    private let phaseLock = NSLock()

    init() {}

    func start() {
        guard !isPlaying else { return }

        do {
            // Configure audio session for playback
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)

            audioEngine = AVAudioEngine()
            guard let engine = audioEngine else { return }

            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

            // Use AVAudioSourceNode for real-time synthesis (no buffer scheduling needed)
            srcNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
                guard let self = self else { return noErr }

                let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
                guard let buffer = ablPointer.first?.mData?.assumingMemoryBound(to: Float.self) else {
                    return noErr
                }

                let freq = Double(self.frequency)
                let amp = Double(self.amplitude)
                let waveformType = self.waveform
                let phaseIncrement = 2.0 * .pi * freq / self.sampleRate

                self.phaseLock.lock()
                var currentPhase = self.phase

                for frame in 0..<Int(frameCount) {
                    let sample: Double

                    switch waveformType {
                    case .sine:
                        sample = sin(currentPhase)
                    case .square:
                        sample = currentPhase < .pi ? 1.0 : -1.0
                    case .sawtooth:
                        sample = 2.0 * (currentPhase / (2.0 * .pi)) - 1.0
                    case .triangle:
                        let normalized = currentPhase / (2.0 * .pi)
                        sample = 4.0 * abs(normalized - 0.5) - 1.0
                    }

                    buffer[frame] = Float(sample * amp)

                    currentPhase += phaseIncrement
                    if currentPhase >= 2.0 * .pi {
                        currentPhase -= 2.0 * .pi
                    }
                }

                self.phase = currentPhase
                self.phaseLock.unlock()

                return noErr
            }

            guard let sourceNode = srcNode else { return }

            engine.attach(sourceNode)
            engine.connect(sourceNode, to: engine.mainMixerNode, format: format)

            try engine.start()

            DispatchQueue.main.async { [weak self] in
                self?.isPlaying = true
            }

        } catch {
            print("[ToneGenerator] Error starting: \(error)")
        }
    }

    func stop() {
        srcNode = nil
        audioEngine?.stop()
        audioEngine = nil
        phase = 0.0
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = false
        }
    }

    func toggle() {
        if isPlaying {
            stop()
        } else {
            start()
        }
    }

    deinit {
        // Direkt stoppen ohne async dispatch (vermeidet Retain-Cycle im deinit)
        srcNode = nil
        audioEngine?.stop()
        audioEngine = nil
    }
}

// MARK: - Oscilloscope View

struct OscilloscopeView: View {
    let frequency: Float
    let amplitude: Float
    let waveform: ToneGenerator.Waveform
    let isPlaying: Bool

    @State private var phase: Double = 0.0
    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    // 1:1 scale based on physical time
    // We define how many milliseconds the full view width should show
    // This makes the display consistent across all device sizes
    private let totalTimeMs: Double = 10.0 // Show 10ms across the full width (adjustable)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            // Calculate points per ms based on view width - consistent across devices
            let pointsPerMs = Double(width) / totalTimeMs

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let midY = size.height / 2

                    // Draw grid with time markers
                    drawTimeGrid(context: context, size: size, pointsPerMs: CGFloat(pointsPerMs))

                    // Calculate wavelength in points (1:1 real scale)
                    // Period T = 1/f seconds = 1000/f milliseconds
                    // Wavelength in points = (1000/f) * pointsPerMs
                    let periodMs = 1000.0 / Double(frequency)
                    let wavelengthPoints = periodMs * pointsPerMs

                    // Draw waveform at real 1:1 scale
                    var path = Path()

                    for x in stride(from: 0, to: Double(width), by: 1) {
                        // Convert point position to phase
                        // x points / wavelengthPoints = number of cycles
                        // phase = (x / wavelengthPoints) * 2π
                        let cyclePosition = x / wavelengthPoints
                        let currentPhase = (cyclePosition * 2.0 * .pi) + (isPlaying ? phase : 0)

                        let sample: Double
                        switch waveform {
                        case .sine:
                            sample = sin(currentPhase)
                        case .square:
                            let normalizedPhase = currentPhase.truncatingRemainder(dividingBy: 2.0 * .pi)
                            sample = normalizedPhase < .pi ? 1.0 : -1.0
                        case .sawtooth:
                            let normalizedPhase = currentPhase.truncatingRemainder(dividingBy: 2.0 * .pi)
                            sample = 2.0 * (normalizedPhase / (2.0 * .pi)) - 1.0
                        case .triangle:
                            let normalizedPhase = currentPhase.truncatingRemainder(dividingBy: 2.0 * .pi)
                            let normalized = normalizedPhase / (2.0 * .pi)
                            sample = 4.0 * abs(normalized - 0.5) - 1.0
                        }

                        let y = midY - CGFloat(sample * Double(amplitude)) * (height * 0.4)

                        if x == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: CGFloat(x), y: y))
                        }
                    }

                    context.stroke(path, with: .color(isPlaying ? .green : .green.opacity(0.5)), lineWidth: 2)

                    // Draw wavelength indicator
                    drawWavelengthIndicator(context: context, size: size, wavelengthPoints: CGFloat(wavelengthPoints))
                }

                // Time scale label
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeScaleText)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.green.opacity(0.7))
                    Text(wavelengthText)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.7))
                }
                .padding(4)
            }
        }
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
        .onReceive(timer) { _ in
            if isPlaying {
                // Animate phase - move waveform to simulate real-time playback
                // Phase increment per frame at 60fps
                let phaseIncrement = 2.0 * .pi * Double(frequency) / 60.0
                phase += phaseIncrement
                if phase > 2.0 * .pi * 1000 {
                    phase = phase.truncatingRemainder(dividingBy: 2.0 * .pi)
                }
            }
        }
    }

    private var timeScaleText: String {
        // totalTimeMs is constant - same time span on all devices
        if totalTimeMs >= 1.0 {
            return String(format: "%.1f ms", totalTimeMs)
        } else {
            return String(format: "%.0f µs", totalTimeMs * 1000)
        }
    }

    private var wavelengthText: String {
        let periodMs = 1000.0 / Double(frequency)
        if periodMs >= 1.0 {
            return String(format: "λ = %.2f ms", periodMs)
        } else {
            return String(format: "λ = %.0f µs", periodMs * 1000)
        }
    }

    private func drawTimeGrid(context: GraphicsContext, size: CGSize, pointsPerMs: CGFloat) {
        let gridColor = Color.green.opacity(0.2)
        let midY = size.height / 2

        // Horizontal center line (0V reference)
        var hPath = Path()
        hPath.move(to: CGPoint(x: 0, y: midY))
        hPath.addLine(to: CGPoint(x: size.width, y: midY))
        context.stroke(hPath, with: .color(gridColor), lineWidth: 1)

        // Time-based vertical grid lines (every 0.5ms or appropriate interval)
        let timeInterval: Double
        if totalTimeMs <= 2 {
            timeInterval = 0.1 // 0.1ms intervals
        } else if totalTimeMs <= 5 {
            timeInterval = 0.5 // 0.5ms intervals
        } else if totalTimeMs <= 10 {
            timeInterval = 1.0 // 1ms intervals
        } else {
            timeInterval = 2.0 // 2ms intervals
        }

        var t = timeInterval
        while t < totalTimeMs {
            let x = CGFloat(t) * pointsPerMs
            var vPath = Path()
            vPath.move(to: CGPoint(x: x, y: 0))
            vPath.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(vPath, with: .color(gridColor), lineWidth: 0.5)
            t += timeInterval
        }

        // Horizontal grid lines (amplitude markers at ±50%)
        for i in [0.25, 0.75] {
            let y = size.height * CGFloat(i)
            var hLinePath = Path()
            hLinePath.move(to: CGPoint(x: 0, y: y))
            hLinePath.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(hLinePath, with: .color(gridColor), lineWidth: 0.5)
        }
    }

    private func drawWavelengthIndicator(context: GraphicsContext, size: CGSize, wavelengthPoints: CGFloat) {
        // Draw a wavelength indicator at the bottom if wavelength fits in view
        guard wavelengthPoints > 20 && wavelengthPoints < size.width else { return }

        let indicatorY = size.height - 8
        let startX: CGFloat = 10

        // Arrow line for one wavelength
        var arrowPath = Path()
        arrowPath.move(to: CGPoint(x: startX, y: indicatorY))
        arrowPath.addLine(to: CGPoint(x: startX + wavelengthPoints, y: indicatorY))

        // Left arrow head
        arrowPath.move(to: CGPoint(x: startX + 4, y: indicatorY - 3))
        arrowPath.addLine(to: CGPoint(x: startX, y: indicatorY))
        arrowPath.addLine(to: CGPoint(x: startX + 4, y: indicatorY + 3))

        // Right arrow head
        arrowPath.move(to: CGPoint(x: startX + wavelengthPoints - 4, y: indicatorY - 3))
        arrowPath.addLine(to: CGPoint(x: startX + wavelengthPoints, y: indicatorY))
        arrowPath.addLine(to: CGPoint(x: startX + wavelengthPoints - 4, y: indicatorY + 3))

        context.stroke(arrowPath, with: .color(.cyan.opacity(0.6)), lineWidth: 1)
    }
}

// MARK: - Tone Generator Widget View

struct ToneGeneratorWidget: View {
    @StateObject private var toneGenerator = ToneGenerator()
    var settings: [String: String]

    // Preset frequencies
    private let presetFrequencies: [(String, Float)] = [
        ("31.5", 31.5),
        ("63", 63),
        ("125", 125),
        ("250", 250),
        ("500", 500),
        ("1k", 1000),
        ("2k", 2000),
        ("4k", 4000),
        ("8k", 8000),
        ("16k", 16000)
    ]

    var body: some View {
        VStack(spacing: 6) {
            // Oscilloscope
            OscilloscopeView(
                frequency: toneGenerator.frequency,
                amplitude: toneGenerator.amplitude,
                waveform: toneGenerator.waveform,
                isPlaying: toneGenerator.isPlaying
            )
            .frame(height: 80)
            .padding(.horizontal, 8)
            .padding(.top, 8)

            // Frequency Display
            HStack {
                Text(frequencyDisplayText)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(toneGenerator.isPlaying ? .green : .primary)
                Text("Hz")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            // Frequency Slider
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { log10(toneGenerator.frequency) },
                        set: { toneGenerator.frequency = pow(10, $0) }
                    ),
                    in: log10(20)...log10(20000)
                )
                .tint(toneGenerator.isPlaying ? .green : .blue)

                HStack {
                    Text("20")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                    Text("20k")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 8)

            // Preset Buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(presetFrequencies, id: \.1) { preset in
                        Button(action: {
                            toneGenerator.frequency = preset.1
                        }) {
                            Text(preset.0)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    abs(toneGenerator.frequency - preset.1) < 1 ?
                                    Color.blue : Color.gray.opacity(0.3)
                                )
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            // Waveform and Volume
            HStack(spacing: 12) {
                // Waveform Picker
                Picker("", selection: $toneGenerator.waveform) {
                    ForEach(ToneGenerator.Waveform.allCases, id: \.self) { waveform in
                        Text(waveform.rawValue).tag(waveform)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)

                // Volume Slider
                HStack(spacing: 4) {
                    Image(systemName: "speaker.fill")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Slider(value: $toneGenerator.amplitude, in: 0...1)
                        .frame(width: 80)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 8)

            // Play/Stop Button
            Button(action: {
                toneGenerator.toggle()
            }) {
                HStack {
                    Image(systemName: toneGenerator.isPlaying ? "stop.fill" : "play.fill")
                    Text(toneGenerator.isPlaying ? "Stop" : "Play")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(toneGenerator.isPlaying ? Color.red : Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .onDisappear {
            toneGenerator.stop()
        }
    }

    private var frequencyDisplayText: String {
        if toneGenerator.frequency >= 1000 {
            return String(format: "%.2f k", toneGenerator.frequency / 1000)
        } else if toneGenerator.frequency >= 100 {
            return String(format: "%.1f", toneGenerator.frequency)
        } else {
            return String(format: "%.2f", toneGenerator.frequency)
        }
    }
}
