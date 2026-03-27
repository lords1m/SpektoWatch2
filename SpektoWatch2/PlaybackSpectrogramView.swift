import SwiftUI
import MetalKit
import Accelerate
import Combine
import CoreMotion

// MARK: - Gyroscope Scroll Manager

class GyroscopeScrollManager: ObservableObject {
    @Published var scrollOffset: Float = 0.0
    @Published var isActive = false

    private let motionManager = CMMotionManager()
    private var referenceRoll: Double = 0.0
    private var isCalibrated = false
    private let sensitivity: Double = .pi / 3

    var isAvailable: Bool { motionManager.isDeviceMotionAvailable }

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        isCalibrated = false
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let roll = motion.attitude.roll
            if !self.isCalibrated {
                self.referenceRoll = roll
                self.isCalibrated = true
            }
            let delta = roll - self.referenceRoll
            self.scrollOffset = Float(max(-1.0, min(1.0, delta / self.sensitivity)))
        }
        isActive = true
    }

    func calibrate() { isCalibrated = false }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        isCalibrated = false
        scrollOffset = 0.0
        isActive = false
    }

    func toggle() { if isActive { stop() } else { start() } }
}

// MARK: - Playback Spectrogram Renderer (uses new minimal shaders)

class PlaybackSpectrogramRenderer: MTKView {
    // MARK: - Metal Resources
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var viewportBuffer: MTLBuffer!

    // MARK: - Textures
    private var spectrogramTexture: MTLTexture!
    private var colormapTexture: MTLTexture?
    private var textureWidth: Int = 0
    private var textureHeight: Int = 512

    // MARK: - Data
    private var magnitudeHistory: [[Float]] = []
    private var isTextureReady = false
    private let splToDbfsOffset: Float = 120.0

    // MARK: - Display Parameters
    var colormapType: Int = 0 {
        didSet { rebuildColormapTexture() }
    }
    private let minDB: Float = -90.0
    private let maxDB: Float = -10.0
    private let noiseFloor: Float = -90.0
    private let gamma: Float = 0.8

    // MARK: - Scroll/Zoom
    var viewportStart: Float = 0.0
    var viewportWidth: Float = 1.0
    var playheadPosition: Float = 0.0

    // MARK: - Initialization

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        setupMetal()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        device = MTLCreateSystemDefaultDevice()
        setupMetal()
    }

    private func setupMetal() {
        guard let device = device else { fatalError("Metal is not supported") }

        self.framebufferOnly = true
        self.enableSetNeedsDisplay = true
        self.isPaused = true
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        self.colorPixelFormat = .bgra8Unorm

        commandQueue = device.makeCommandQueue()
        setupPipeline()

        viewportBuffer = device.makeBuffer(
            length: MemoryLayout<SIMD2<Float>>.stride,
            options: .storageModeShared
        )

        rebuildColormapTexture()
    }

    private func setupPipeline() {
        guard let device = device,
              let library = device.makeDefaultLibrary() else { return }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "spectrogramVertex")
        desc.fragmentFunction = library.makeFunction(name: "playbackSpectrogramFragment")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to create pipeline: \(error)")
        }
    }

    private func rebuildColormapTexture() {
        guard let device = device else { return }
        let cmType = ColormapType(rawValue: colormapType) ?? .turbo
        colormapTexture = ColormapTexture.makeTexture(device: device, type: cmType)
    }

    // MARK: - Data Loading

    func loadSpectrogramData(_ history: [[Float]]) {
        guard !history.isEmpty else { return }

        magnitudeHistory = history
        textureWidth = history.count
        textureHeight = history.first?.count ?? 512

        createTexture()
        fillTexture()
        isTextureReady = spectrogramTexture != nil
        setNeedsDisplay()
    }

    func computeFromAudioSamples(_ samples: [Float], sampleRate: Double, fftSize: Int = 4096, hopSize: Int = 512) {
        guard samples.count > fftSize else { return }

        var history: [[Float]] = []

        guard let fftSetup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD) else { return }
        defer { vDSP_DFT_DestroySetup(fftSetup) }

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        var offset = 0
        while offset + fftSize <= samples.count {
            let windowSamples = Array(samples[offset..<(offset + fftSize)])
            var windowed = [Float](repeating: 0, count: fftSize)
            vDSP_vmul(windowSamples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

            var realIn = [Float](repeating: 0, count: fftSize / 2)
            var imagIn = [Float](repeating: 0, count: fftSize / 2)
            for i in 0..<(fftSize / 2) {
                realIn[i] = windowed[2 * i]
                imagIn[i] = windowed[2 * i + 1]
            }

            var realOut = [Float](repeating: 0, count: fftSize / 2)
            var imagOut = [Float](repeating: 0, count: fftSize / 2)
            vDSP_DFT_Execute(fftSetup, realIn, imagIn, &realOut, &imagOut)

            var magnitudes = [Float](repeating: 0, count: fftSize / 2)
            realOut.withUnsafeMutableBufferPointer { realPtr in
                imagOut.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
                }
            }

            var dbMagnitudes = [Float](repeating: -120.0, count: magnitudes.count)
            for i in 0..<magnitudes.count {
                let db = 20.0 * log10(magnitudes[i] + 1e-10)
                dbMagnitudes[i] = db + splToDbfsOffset
            }

            var column = [Float](repeating: -120.0, count: textureHeight)
            for i in 0..<textureHeight {
                let srcIndex = Int(Float(i) / Float(textureHeight) * Float(dbMagnitudes.count))
                column[i] = dbMagnitudes[min(srcIndex, dbMagnitudes.count - 1)]
            }

            history.append(column)
            offset += hopSize
        }

        loadSpectrogramData(history)
    }

    private func createTexture() {
        guard let device = device else { return }

        let desc = MTLTextureDescriptor()
        desc.textureType = .type2D
        desc.pixelFormat = .r32Float
        desc.width = textureWidth
        desc.height = textureHeight
        desc.usage = .shaderRead
        desc.storageMode = .shared

        spectrogramTexture = device.makeTexture(descriptor: desc)
    }

    /// Normalize and write data to texture (same pipeline as live spectrogram)
    private func fillTexture() {
        guard let texture = spectrogramTexture else { return }

        let minSPL: Float = 110.0 - 50.0  // 60 dB SPL floor
        let maxSPL: Float = 110.0
        let range = maxSPL - minSPL
        let nfSPL: Float = noiseFloor + 120.0
        let kw: Float = 10.0
        let gam = gamma

        for (columnIndex, column) in magnitudeHistory.enumerated() {
            var columnData = [Float](repeating: 0, count: textureHeight)
            for i in 0..<min(column.count, textureHeight) {
                var dbValue = column[i]

                // Noise gate with soft knee
                if dbValue < nfSPL {
                    dbValue = minSPL
                } else if dbValue < nfSPL + kw {
                    let t = (dbValue - nfSPL) / kw
                    let factor = t * t * (3.0 - 2.0 * t)
                    dbValue = minSPL * (1.0 - factor) + dbValue * factor
                }

                var normalized = (dbValue - minSPL) / range
                normalized = max(0, min(1, normalized))
                normalized = log10(1.0 + 99.0 * normalized) / log10(100.0)
                normalized = powf(normalized, gam)

                columnData[i] = normalized
            }

            let region = MTLRegion(
                origin: MTLOrigin(x: columnIndex, y: 0, z: 0),
                size: MTLSize(width: 1, height: textureHeight, depth: 1)
            )
            texture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: columnData,
                bytesPerRow: MemoryLayout<Float>.stride
            )
        }
    }

    // MARK: - Rendering

    override func draw(_ rect: CGRect) {
        guard isTextureReady,
              let drawable = currentDrawable,
              let rpd = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd),
              colormapTexture != nil
        else { return }

        let clampedWidth = max(0.0001, min(1.0, viewportWidth))
        let clampedStart = max(0.0, min(1.0 - clampedWidth, viewportStart))
        var viewport = SIMD2<Float>(clampedStart, clampedWidth)
        memcpy(viewportBuffer.contents(), &viewport, MemoryLayout<SIMD2<Float>>.stride)

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(spectrogramTexture, index: 0)
        encoder.setFragmentTexture(colormapTexture, index: 1)
        encoder.setFragmentBuffer(viewportBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Public API

    func setPlayheadPosition(_ position: Float) {
        playheadPosition = max(0, min(1, position))
        setNeedsDisplay()
    }

    func setColormap(_ type: Int) {
        let clamped = max(0, min(ColormapType.allCases.count - 1, type))
        guard colormapType != clamped else { return }
        colormapType = clamped
        setNeedsDisplay()
    }

    func setViewport(start: Float, width: Float) {
        let clampedWidth = max(0.0001, min(1.0, width))
        viewportWidth = clampedWidth
        viewportStart = max(0.0, min(1.0 - clampedWidth, start))
        setNeedsDisplay()
    }

    func getFrameCount() -> Int { magnitudeHistory.count }
}

// MARK: - SwiftUI Wrapper

struct PlaybackSpectrogramView: UIViewRepresentable {
    var magnitudeHistory: [[Float]]
    var playheadPosition: Float
    var colormapType: Int
    var viewportStart: Float
    var viewportWidth: Float
    var totalDuration: TimeInterval = 0
    var sampleRate: Float = 44_100
    var viewWidth: CGFloat = 1
    var viewHeight: CGFloat = 1

    func valueAt(viewX: CGFloat, viewY: CGFloat) -> (time: TimeInterval, frequency: Float, magnitude: Float)? {
        guard !magnitudeHistory.isEmpty, viewWidth > 0, viewHeight > 0 else { return nil }
        let xNorm = Float(max(0, min(1, viewX / viewWidth)))
        let yNorm = Float(max(0, min(1, 1.0 - (viewY / viewHeight))))
        let timelineNorm = viewportStart + xNorm * viewportWidth
        let clampedTimeline = max(0, min(1, timelineNorm))
        let time = TimeInterval(clampedTimeline) * totalDuration

        let columnIndex = min(magnitudeHistory.count - 1, max(0, Int(clampedTimeline * Float(magnitudeHistory.count - 1))))
        let column = magnitudeHistory[columnIndex]
        guard !column.isEmpty else { return nil }

        let minFrequency: Float = 20
        let maxFrequency = min(sampleRate / 2, 20_000)
        let frequency = minFrequency * powf(maxFrequency / minFrequency, yNorm)
        let binIndex = min(column.count - 1, max(0, Int((frequency / maxFrequency) * Float(column.count - 1))))
        let magnitude = column[binIndex]

        return (time: time, frequency: frequency, magnitude: magnitude)
    }

    func makeUIView(context: Context) -> PlaybackSpectrogramRenderer {
        let view = PlaybackSpectrogramRenderer(
            frame: .zero,
            device: MTLCreateSystemDefaultDevice()
        )
        view.setColormap(colormapType)
        view.setViewport(start: viewportStart, width: viewportWidth)
        if !magnitudeHistory.isEmpty {
            view.loadSpectrogramData(magnitudeHistory)
        }
        return view
    }

    func updateUIView(_ uiView: PlaybackSpectrogramRenderer, context: Context) {
        uiView.setColormap(colormapType)
        uiView.setPlayheadPosition(playheadPosition)
        uiView.setViewport(start: viewportStart, width: viewportWidth)

        if uiView.getFrameCount() != magnitudeHistory.count && !magnitudeHistory.isEmpty {
            uiView.loadSpectrogramData(magnitudeHistory)
        }

        uiView.setNeedsDisplay()
    }
}

// MARK: - Scrollable Spectrogram with Playhead

struct ScrollableSpectrogramView: View {
    @Binding var currentTime: TimeInterval
    let duration: TimeInterval
    var magnitudeHistory: [[Float]]
    var colormapType: Int
    var sampleRate: Float = 44_100
    var markers: [MeasurementMarker] = []
    var onSeek: (TimeInterval) -> Void

    @StateObject private var gyroManager = GyroscopeScrollManager()
    @State private var dragStartTime: TimeInterval?
    private let visibleWindowDuration: TimeInterval = 5.0
    private let preferredPlayheadFraction: CGFloat = 0.82

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let safeDuration = max(duration, 0.001)
            let windowDuration = min(visibleWindowDuration, safeDuration)
            let viewportWidth = Float(windowDuration / safeDuration)
            let normalizedTime = Float(currentTime / safeDuration)

            let gyroOffset = gyroManager.isActive
                ? gyroManager.scrollOffset * viewportWidth * 1.5
                : Float(0.0)

            let desiredStart = normalizedTime - viewportWidth * Float(preferredPlayheadFraction) + gyroOffset
            let clampedStart = max(0.0, min(1.0 - viewportWidth, desiredStart))
            let localPlayhead = max(0.0, min(1.0, (normalizedTime - clampedStart) / max(viewportWidth, 0.0001)))
            let playheadX = totalWidth * CGFloat(localPlayhead)
            let viewportStartTime = TimeInterval(clampedStart) * safeDuration
            let viewportEndTime = min(safeDuration, viewportStartTime + windowDuration)
            let inspectable = PlaybackSpectrogramView(
                magnitudeHistory: magnitudeHistory,
                playheadPosition: localPlayhead,
                colormapType: colormapType,
                viewportStart: clampedStart,
                viewportWidth: viewportWidth,
                totalDuration: safeDuration,
                sampleRate: sampleRate,
                viewWidth: totalWidth,
                viewHeight: geometry.size.height
            )

            ZStack(alignment: .leading) {
                inspectable
                .cornerRadius(12)

                ForEach(markers) { marker in
                    let t = marker.time
                    if t >= viewportStartTime && t <= viewportEndTime {
                        let x = totalWidth * CGFloat((t - viewportStartTime) / max(windowDuration, 0.001))
                        Rectangle()
                            .fill(Color.red.opacity(0.85))
                            .frame(width: 1.5)
                            .offset(x: x)
                    }
                }

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2)
                    .offset(x: playheadX)
                    .shadow(color: .black.opacity(0.5), radius: 2)

                VStack {
                    Text(formatTime(currentTime))
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    Spacer()
                }
                .offset(x: max(0, min(playheadX - 20, totalWidth - 50)))

                VStack {
                    HStack {
                        Spacer()
                        gyroControls
                    }
                    .padding(8)
                    Spacer()
                }

                VStack {
                    Spacer()
                    subtleXAxis(
                        width: totalWidth,
                        startTime: viewportStartTime,
                        endTime: viewportEndTime,
                        windowDuration: windowDuration
                    )
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                    .allowsHitTesting(false)
                }

                SpectrogramCrosshairOverlay { x, y in
                    inspectable.valueAt(viewX: x, viewY: y)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let clampedWidth = max(totalWidth, 1)
                        if dragStartTime == nil {
                            let tappedFraction = max(0.0, min(1.0, TimeInterval(value.startLocation.x / clampedWidth)))
                            let startTime = TimeInterval(clampedStart) * safeDuration
                            let tappedTime = startTime + tappedFraction * windowDuration
                            dragStartTime = max(0, min(tappedTime, safeDuration))
                            onSeek(dragStartTime ?? currentTime)
                            return
                        }

                        let secondsPerPoint = windowDuration / TimeInterval(clampedWidth)
                        let delta = -TimeInterval(value.translation.width) * secondsPerPoint
                        let base = dragStartTime ?? currentTime
                        onSeek(max(0, min(base + delta, safeDuration)))
                    }
                    .onEnded { _ in dragStartTime = nil }
            )
        }
        .onDisappear { gyroManager.stop() }
    }

    // MARK: - Gyro Controls

    @ViewBuilder
    private var gyroControls: some View {
        HStack(spacing: 6) {
            if gyroManager.isActive {
                Button(action: { gyroManager.calibrate() }) {
                    Image(systemName: "scope")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }

                gyroTiltIndicator
            }

            Button(action: { gyroManager.toggle() }) {
                Image(systemName: "gyroscope")
                    .font(.caption2)
                    .foregroundColor(gyroManager.isActive ? .orange : .white.opacity(0.5))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(gyroManager.isActive ? Color.orange.opacity(0.2) : Color.black.opacity(0.5))
                    )
                    .overlay(
                        Circle().stroke(gyroManager.isActive ? Color.orange.opacity(0.6) : Color.clear, lineWidth: 1)
                    )
            }
        }
    }

    private var gyroTiltIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.15))
                .frame(width: 30, height: 4)
            Circle()
                .fill(Color.orange)
                .frame(width: 5, height: 5)
                .offset(x: CGFloat(gyroManager.scrollOffset) * 12)
        }
        .frame(width: 30, height: 10)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func subtleXAxis(width: CGFloat, startTime: TimeInterval, endTime: TimeInterval, windowDuration: TimeInterval) -> some View {
        let step: TimeInterval
        if windowDuration <= 8 { step = 1 }
        else if windowDuration <= 20 { step = 2 }
        else { step = 5 }

        let firstTick = ceil(startTime / step) * step
        let span = max(endTime - startTime, 0.001)
        let tickValues = stride(from: firstTick, through: endTime, by: step).map { $0 }

        return VStack(spacing: 3) {
            ZStack(alignment: .leading) {
                ForEach(tickValues, id: \.self) { tick in
                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 1, height: 5)
                        .offset(x: max(0, min(width - 1, CGFloat((tick - startTime) / span) * width)))
                }
            }
            .frame(height: 5)

            ZStack(alignment: .leading) {
                ForEach(tickValues, id: \.self) { tick in
                    Text(formatAxisTime(tick))
                        .offset(x: max(0, min(width - 28, CGFloat((tick - startTime) / span) * width - 12)))
                }
            }
            .frame(height: 12)
            .font(.caption2.monospacedDigit())
            .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func formatAxisTime(_ time: TimeInterval) -> String {
        let rounded = Int(time.rounded())
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }
}
