import SwiftUI
import AVFoundation
import Combine
import CoreMotion

private enum PhysicalScopeScale {
    // Fixed physical viewport size so the oscilloscope appears equally large on all iPhones.
    static let scopeWidthMM: CGFloat = 42.0
    static let scopeHeightMM: CGFloat = 14.0

    static func pointsPerMillimeter(for traitCollection: UITraitCollection) -> CGFloat {
        let ppi = estimatedPPI(for: traitCollection)
        let scale = traitCollection.displayScale
        return (ppi / 25.4) / scale
    }

    static func scopeSizePoints(for traitCollection: UITraitCollection) -> CGSize {
        let ppm = pointsPerMillimeter(for: traitCollection)
        return CGSize(
            width: scopeWidthMM * ppm,
            height: scopeHeightMM * ppm
        )
    }

    private static func estimatedPPI(for traitCollection: UITraitCollection) -> CGFloat {
        // Use trait collection's displayGamut as a proxy for device class
        // This is a best-effort approach for iOS 26+
        let scale = traitCollection.displayScale
        
        // Approximate PPI based on display scale
        switch scale {
        case 2.0:
            return 326.0  // Standard retina (iPhone 6/7/8, etc.)
        case 3.0:
            return 458.0  // Super retina (iPhone X and later)
        default:
            return 460.0  // Modern devices fallback
        }
    }
}

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
            // Configure audio session for playback only if it is not already set up
            // for a compatible category to avoid disrupting active microphone capture.
            let session = AVAudioSession.sharedInstance()
            let currentCategory = session.category
            if currentCategory != .playAndRecord && currentCategory != .playback {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
                try session.setActive(true)
            }

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

                // Snapshot @Published properties under the lock before render loop
                // to avoid data races with main-thread writes.
                self.phaseLock.lock()
                let freq = Double(self.frequency)
                let amp = Double(self.amplitude)
                let waveformType = self.waveform
                var currentPhase = self.phase
                self.phaseLock.unlock()

                let phaseIncrement = 2.0 * .pi * freq / self.sampleRate

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

                self.phaseLock.lock()
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

// MARK: - Movement Manager for Oscilloscope

/// Maps translational device movement to a normalized horizontal scroll offset.
/// Uses linear acceleration (`userAcceleration`) and an inertial integration model.
private final class OscilloscopeMovementManager: ObservableObject {
    enum MotionAxis {
        case deviceX
        case deviceY
    }

    @Published var scrollOffset: Float = 0.0  // -1.0 ... 1.0
    @Published var isActive = false

    private let motionManager = CMMotionManager()
    private var lastTimestamp: TimeInterval?
    private var velocity: Double = 0.0
    private var position: Double = 0.0
    private var axis: MotionAxis = .deviceX

    // Tuned for hand-held movement through room.
    private let accelerationGain: Double = 2.8
    private let deadZone: Double = 0.010
    private let maxVelocity: Double = 1.8
    private let dragPerSecond: Double = 2.2
    private let recenterPerSecond: Double = 0.55

    var isAvailable: Bool {
        motionManager.isDeviceMotionAvailable
    }

    func setAxis(_ axis: MotionAxis) {
        self.axis = axis
    }

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }

        calibrate()
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }

            let now = motion.timestamp
            let dt = self.clampedDeltaTime(now: now)

            let rawAcceleration: Double
            switch self.axis {
            case .deviceX:
                rawAcceleration = Double(motion.userAcceleration.x)
            case .deviceY:
                // Invert so rightward movement feels natural in forced-landscape presentation.
                rawAcceleration = -Double(motion.userAcceleration.y)
            }

            let filteredAcceleration = self.applyDeadZone(rawAcceleration)
            self.velocity += filteredAcceleration * self.accelerationGain * dt
            self.velocity = max(-self.maxVelocity, min(self.maxVelocity, self.velocity))

            // Friction-like drag.
            self.velocity *= exp(-self.dragPerSecond * dt)

            // Integrate to position and softly pull back toward center.
            self.position += self.velocity * dt
            self.position *= exp(-self.recenterPerSecond * dt)
            self.position = max(-1.0, min(1.0, self.position))

            self.scrollOffset = Float(self.position)
        }
        isActive = true
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        lastTimestamp = nil
        velocity = 0.0
        position = 0.0
        scrollOffset = 0.0
        isActive = false
    }

    func calibrate() {
        lastTimestamp = nil
        velocity = 0.0
        position = 0.0
        scrollOffset = 0.0
    }

    func toggle() {
        if isActive {
            stop()
        } else {
            start()
        }
    }

    private func clampedDeltaTime(now: TimeInterval) -> Double {
        defer { lastTimestamp = now }
        guard let lastTimestamp else { return 1.0 / 60.0 }
        return min(max(now - lastTimestamp, 1.0 / 120.0), 1.0 / 20.0)
    }

    private func applyDeadZone(_ value: Double) -> Double {
        if abs(value) <= deadZone { return 0.0 }
        return value - (value.sign == .minus ? -deadZone : deadZone)
    }
}

// MARK: - Oscilloscope View

struct OscilloscopeView: View {
    enum LayoutMode {
        case physicalFixed
        case fill
    }

    let frequency: Float
    let amplitude: Float
    let waveform: ToneGenerator.Waveform
    let isPlaying: Bool
    var layoutMode: LayoutMode = .fill
    var tiltOffsetNormalized: Float = 0.0

    @State private var phase: Double = 0.0
    @State private var accumulatedScrollPoints: Double = 0.0
    @State private var dragTranslationPoints: Double = 0.0
    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    private let speedOfSoundMetersPerSecond: Double = 344.0

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let traitCollection = UITraitCollection(traitsFrom: [
            UITraitCollection(displayScale: displayScale)
        ])
        let pointsPerMillimeter = Double(PhysicalScopeScale.pointsPerMillimeter(for: traitCollection))
        let cornerRadius: CGFloat = 10

        return Group {
            switch layoutMode {
            case .physicalFixed:
                let scopeSize = PhysicalScopeScale.scopeSizePoints(for: traitCollection)
                scopeContent(viewportSize: scopeSize, pointsPerMillimeter: pointsPerMillimeter)
                    .frame(width: scopeSize.width, height: scopeSize.height)
                    .frame(maxWidth: .infinity)
            case .fill:
                GeometryReader { geometry in
                    scopeContent(viewportSize: geometry.size, pointsPerMillimeter: pointsPerMillimeter)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .background(scopeGlassBackground)
        .overlay(scopeScanlines)
        .overlay(scopeVignette)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.black.opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    dragTranslationPoints = Double(value.translation.width)
                }
                .onEnded { value in
                    accumulatedScrollPoints -= Double(value.translation.width)
                    dragTranslationPoints = 0
                }
        )
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

    private var scopeGlassBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.015, green: 0.03, blue: 0.015),
                Color(red: 0.0, green: 0.01, blue: 0.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var scopeScanlines: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y <= size.height {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(Color.black.opacity(0.18)), lineWidth: 0.6)
                y += 2.0
            }
        }
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }

    private var scopeVignette: some View {
        RadialGradient(
            colors: [
                .clear,
                Color.black.opacity(0.38)
            ],
            center: .center,
            startRadius: 8,
            endRadius: 260
        )
        .allowsHitTesting(false)
    }

    private func scopeContent(viewportSize: CGSize, pointsPerMillimeter: Double) -> some View {
        let totalDistanceMm = Double(viewportSize.width) / pointsPerMillimeter
        let tiltScrollPoints = Double(tiltOffsetNormalized) * Double(viewportSize.width) * 1.5
        let scrollPoints = accumulatedScrollPoints - dragTranslationPoints + tiltScrollPoints
        let startDistanceMm = scrollPoints / pointsPerMillimeter

        return ZStack(alignment: .topLeading) {
            Canvas { context, size in
                let midY = size.height / 2
                drawDistanceGrid(
                    context: context,
                    size: size,
                    pointsPerMillimeter: CGFloat(pointsPerMillimeter),
                    totalDistanceMm: totalDistanceMm,
                    startDistanceMm: startDistanceMm
                )
                let wavelengthMeters = speedOfSoundMetersPerSecond / max(Double(frequency), 1)
                let wavelengthPoints = wavelengthMeters * 1000.0 * pointsPerMillimeter

                var path = Path()

                for x in stride(from: 0, to: Double(size.width), by: 1) {
                    let sampleX = x + scrollPoints
                    let cyclePosition = sampleX / wavelengthPoints
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

                    let y = midY - CGFloat(sample * Double(amplitude)) * (size.height * 0.4)

                    if x == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: CGFloat(x), y: y))
                    }
                }

                let traceColor = isPlaying
                    ? Color(red: 0.45, green: 1.0, blue: 0.55)
                    : Color(red: 0.35, green: 0.65, blue: 0.40)

                // Multi-pass stroke for analog phosphor glow.
                context.stroke(path, with: .color(traceColor.opacity(0.16)), lineWidth: 7.0)
                context.stroke(path, with: .color(traceColor.opacity(0.45)), lineWidth: 3.2)
                context.stroke(path, with: .color(traceColor.opacity(0.95)), lineWidth: 1.3)
                drawWavelengthIndicator(context: context, size: size, wavelengthPoints: CGFloat(wavelengthPoints))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(wavelengthText)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.green.opacity(0.9))
            }
            .padding(4)
        }
    }

    private var wavelengthText: String {
        let wavelengthMeters = speedOfSoundMetersPerSecond / max(Double(frequency), 1)
        if wavelengthMeters >= 1.0 {
            return String(format: "λ = %.2f m", wavelengthMeters)
        }
        let wavelengthCm = wavelengthMeters * 100
        if wavelengthCm >= 1.0 {
            return String(format: "λ = %.1f cm", wavelengthCm)
        }
        return String(format: "λ = %.1f mm", wavelengthMeters * 1000)
    }

    private func drawDistanceGrid(
        context: GraphicsContext,
        size: CGSize,
        pointsPerMillimeter: CGFloat,
        totalDistanceMm: Double,
        startDistanceMm: Double
    ) {
        let gridMinor = Color.green.opacity(0.10)
        let gridMajor = Color.green.opacity(0.24)
        let centerLineColor = Color.green.opacity(0.34)
        let midY = size.height / 2

        // Horizontal center line.
        var hPath = Path()
        hPath.move(to: CGPoint(x: 0, y: midY))
        hPath.addLine(to: CGPoint(x: size.width, y: midY))
        context.stroke(hPath, with: .color(centerLineColor), lineWidth: 1.1)

        // Distance-based vertical grid (major + minor divisions).
        let majorIntervalMm: Double
        if totalDistanceMm <= 20 {
            majorIntervalMm = 2.0
        } else if totalDistanceMm <= 60 {
            majorIntervalMm = 5.0
        } else if totalDistanceMm <= 120 {
            majorIntervalMm = 10.0
        } else {
            majorIntervalMm = 20.0
        }
        let minorIntervalMm = majorIntervalMm / 5.0

        let firstIndex = floor(startDistanceMm / minorIntervalMm)
        var gridDistanceMm = firstIndex * minorIntervalMm
        while gridDistanceMm <= startDistanceMm + totalDistanceMm {
            let xMm = gridDistanceMm - startDistanceMm
            let x = CGFloat(xMm) * pointsPerMillimeter
            guard x >= 0 && x <= size.width else {
                gridDistanceMm += minorIntervalMm
                continue
            }
            let majorRatio = gridDistanceMm / majorIntervalMm
            let isMajor = abs(majorRatio.rounded() - majorRatio) < 0.001
            var vPath = Path()
            vPath.move(to: CGPoint(x: x, y: 0))
            vPath.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(vPath, with: .color(isMajor ? gridMajor : gridMinor), lineWidth: isMajor ? 0.75 : 0.4)
            gridDistanceMm += minorIntervalMm
        }

        // Horizontal divisions (8 major rows, each split into 5 minor rows).
        let majorRows = 8
        let majorStep = size.height / CGFloat(majorRows)
        let minorStep = majorStep / 5.0
        var y = minorStep
        while y < size.height {
            let rowRatio = y / majorStep
            let isMajor = abs(rowRatio.rounded() - rowRatio) < 0.001
            var hLinePath = Path()
            hLinePath.move(to: CGPoint(x: 0, y: y))
            hLinePath.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(hLinePath, with: .color(isMajor ? gridMajor : gridMinor), lineWidth: isMajor ? 0.7 : 0.35)
            y += minorStep
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

        context.stroke(arrowPath, with: .color(.green.opacity(0.75)), lineWidth: 1)
    }
}

// MARK: - Tone Generator Widget View

struct ToneGeneratorWidget: View {
    @StateObject private var toneGenerator = ToneGenerator()
    @State private var showFullscreenOscilloscope = false
    var settings: [String: String]
    private let outerPadding: CGFloat = 10
    private let minOscilloscopeHeight: CGFloat = 100

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
            ZStack(alignment: .topTrailing) {
                OscilloscopeView(
                    frequency: toneGenerator.frequency,
                    amplitude: toneGenerator.amplitude,
                    waveform: toneGenerator.waveform,
                    isPlaying: toneGenerator.isPlaying
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: minOscilloscopeHeight, maxHeight: .infinity)
                .gesture(
                    MagnificationGesture()
                        .onEnded { scale in
                            if scale > 1.15 {
                                showFullscreenOscilloscope = true
                            }
                        }
                )

                Button(action: { showFullscreenOscilloscope = true }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .padding(8)
                .accessibilityLabel("Wellenansicht vergrößern")
            }

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
        }
        .padding(.horizontal, outerPadding)
        .padding(.vertical, outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDisappear {
            toneGenerator.stop()
        }
        .fullScreenCover(isPresented: $showFullscreenOscilloscope) {
            WaveformFullscreenView(
                frequency: toneGenerator.frequency,
                amplitude: toneGenerator.amplitude,
                waveform: toneGenerator.waveform,
                isPlaying: toneGenerator.isPlaying
            )
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

private struct WaveformFullscreenView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var movementManager = OscilloscopeMovementManager()

    let frequency: Float
    let amplitude: Float
    let waveform: ToneGenerator.Waveform
    let isPlaying: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                let isPortrait = geometry.size.height > geometry.size.width
                let landscapeWidth = isPortrait ? geometry.size.height : geometry.size.width
                let landscapeHeight = isPortrait ? geometry.size.width : geometry.size.height
                let axis: OscilloscopeMovementManager.MotionAxis = isPortrait ? .deviceY : .deviceX

                OscilloscopeView(
                    frequency: frequency,
                    amplitude: amplitude,
                    waveform: waveform,
                    isPlaying: isPlaying,
                    layoutMode: .fill,
                    tiltOffsetNormalized: movementManager.isActive ? movementManager.scrollOffset : 0
                )
                .frame(width: landscapeWidth, height: landscapeHeight)
                .rotationEffect(.degrees(isPortrait ? 90 : 0))
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .onAppear {
                    movementManager.setAxis(axis)
                }
                .onChange(of: isPortrait) { _, newValue in
                    movementManager.setAxis(newValue ? .deviceY : .deviceX)
                }
            }
            .ignoresSafeArea()

            HStack(spacing: 8) {
                if movementManager.isAvailable {
                    if movementManager.isActive {
                        Button(action: { movementManager.calibrate() }) {
                            Image(systemName: "scope")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.85))
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.black.opacity(0.55)))
                        }

                        ZStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 30, height: 4)

                            Circle()
                                .fill(Color.orange)
                                .frame(width: 5, height: 5)
                                .offset(x: CGFloat(movementManager.scrollOffset) * 12)
                        }
                        .frame(width: 30, height: 10)
                    }

                    Button(action: { movementManager.toggle() }) {
                        Image(systemName: "figure.walk.motion")
                            .font(.caption2)
                            .foregroundColor(movementManager.isActive ? .orange : .white.opacity(0.55))
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(movementManager.isActive
                                          ? Color.orange.opacity(0.22)
                                          : Color.black.opacity(0.55))
                            )
                            .overlay(
                                Circle()
                                    .stroke(movementManager.isActive ? Color.orange.opacity(0.6) : Color.clear, lineWidth: 1)
                            )
                    }
                    .accessibilityLabel("Bewegungssteuerung")
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
        .statusBarHidden(true)
        .onDisappear {
            movementManager.stop()
        }
    }
}
