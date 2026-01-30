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

            DispatchQueue.main.async {
                self.isPlaying = true
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
        DispatchQueue.main.async {
            self.isPlaying = false
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
        stop()
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

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let width = size.width
                let height = size.height
                let midY = height / 2

                // Draw grid
                drawGrid(context: context, size: size)

                // Draw waveform
                var path = Path()
                let cyclesToShow = min(max(2, frequency / 200), 8) // 2-8 cycles depending on frequency
                let samplesPerCycle = width / CGFloat(cyclesToShow)

                for x in stride(from: 0, to: width, by: 1) {
                    let normalizedX = Double(x) / Double(samplesPerCycle)
                    let currentPhase = (normalizedX * 2.0 * .pi) + (isPlaying ? phase : 0)

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
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                context.stroke(path, with: .color(isPlaying ? .green : .green.opacity(0.5)), lineWidth: 2)
            }
        }
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
        .onReceive(timer) { _ in
            if isPlaying {
                // Animate phase based on frequency
                let phaseIncrement = Double(frequency) / 60.0 * 0.1
                phase += phaseIncrement
                if phase > 2.0 * .pi * 100 {
                    phase = 0
                }
            }
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let gridColor = Color.green.opacity(0.2)
        let midY = size.height / 2

        // Horizontal center line
        var hPath = Path()
        hPath.move(to: CGPoint(x: 0, y: midY))
        hPath.addLine(to: CGPoint(x: size.width, y: midY))
        context.stroke(hPath, with: .color(gridColor), lineWidth: 1)

        // Vertical grid lines
        let vDivisions = 8
        for i in 1..<vDivisions {
            let x = size.width * CGFloat(i) / CGFloat(vDivisions)
            var vPath = Path()
            vPath.move(to: CGPoint(x: x, y: 0))
            vPath.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(vPath, with: .color(gridColor), lineWidth: 0.5)
        }

        // Horizontal grid lines (amplitude markers)
        for i in [0.25, 0.75] {
            let y = size.height * CGFloat(i)
            var hLinePath = Path()
            hLinePath.move(to: CGPoint(x: 0, y: y))
            hLinePath.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(hLinePath, with: .color(gridColor), lineWidth: 0.5)
        }
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
