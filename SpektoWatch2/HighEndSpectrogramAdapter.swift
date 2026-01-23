import MetalKit
import Accelerate
import SwiftUI
import Combine

// ============================================================================
// MARK: - Adapter View (uses existing FFT from AudioEngine)
// ============================================================================

/// Adapter that uses HighEndSpectrogramShaders.metal (with all bugfixes)
/// but accepts pre-computed FFT magnitudes from AudioEngine
/// This avoids duplicate FFT computation while still getting the visual improvements
class HighEndSpectrogramAdapter: MTKView {

    // MARK: - Metal Resources
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer!
    private var paramsBuffer: MTLBuffer!

    // MARK: - Texture (Ring Buffer)
    private var spectrogramTexture: MTLTexture!
    private var currentColumn: Int = 0

    // MARK: - Configuration
    private let frequencyBins: Int = 1024  // Higher resolution than AudioEngine's default
    private let timeColumns: Int = 1200    // ~2 minutes at 10 FPS

    private let sampleRate: Float = 44100.0
    private let minFrequency: Float = 20.0
    private let maxFrequency: Float = 20000.0
    private let minDB: Float = -120.0   // BUGFIX: Extended range
    private let maxDB: Float = -20.0     // BUGFIX: Realistic peak level

    // MARK: - Display Parameters (with Bugfixes!)
    var colormapType: Int = 0           // 0 = Turbo
    var noiseFloor: Float = -100.0      // BUGFIX: Adjusted for new range
    var kneeWidth: Float = 15.0         // BUGFIX: Wider knee
    var gamma: Float = 0.5              // BUGFIX: Lower gamma for better color distribution
    var useInterpolation: Bool = true   // BUGFIX: Bilinear interpolation enabled

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

    // MARK: - Metal Setup

    private func setupMetal() {
        guard let device = device else {
            fatalError("Metal is not supported on this device")
        }

        self.framebufferOnly = false
        self.enableSetNeedsDisplay = false
        self.isPaused = false
        self.preferredFramesPerSecond = 60
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        commandQueue = device.makeCommandQueue()

        setupPipeline()
        setupGeometry()
        setupTexture()
        setupParametersBuffer()
    }

    private func setupPipeline() {
        guard let device = device else { return }

        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not load Metal library")
        }

        // Use the OPTIMIZED shaders from HighEndSpectrogramShaders.metal!
        let vertexFunction = library.makeFunction(name: "highEndSpectrogramVertexShader")
        let fragmentFunction = library.makeFunction(name: "highEndSpectrogramFragmentShader")

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.stride * 2
        vertexDescriptor.attributes[1].bufferIndex = 0

        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 4
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create render pipeline state: \(error)")
        }
    }

    private func setupGeometry() {
        guard let device = device else { return }

        // Full-screen quad
        let vertices: [Float] = [
            -1.0, -1.0,  0.0, 1.0,  // Bottom-left
             1.0, -1.0,  1.0, 1.0,  // Bottom-right
            -1.0,  1.0,  0.0, 0.0,  // Top-left
             1.0,  1.0,  1.0, 0.0   // Top-right
        ]

        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
    }

    private func setupTexture() {
        guard let device = device else { return }

        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = .r32Float
        descriptor.width = timeColumns
        descriptor.height = frequencyBins
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared

        spectrogramTexture = device.makeTexture(descriptor: descriptor)
        clearTexture()
    }

    private func clearTexture() {
        guard let texture = spectrogramTexture else { return }

        let bytesPerRow = texture.width * MemoryLayout<Float>.stride
        var data = [Float](repeating: 0.0, count: texture.width * texture.height)

        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: texture.width, height: texture.height, depth: 1)
        )

        texture.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: &data,
            bytesPerRow: bytesPerRow
        )
    }

    private func setupParametersBuffer() {
        guard let device = device else { return }

        var params = ShaderParams(
            minDB: minDB,
            maxDB: maxDB,
            minFreq: minFrequency,
            maxFreq: maxFrequency,
            nyquist: sampleRate / 2.0,
            fftSize: Int32(4096),  // AudioEngine's FFT size
            scrollOffset: 0.0,
            colormapType: Int32(colormapType),
            horizontalBlur: 0.0,  // Deprecated
            noiseFloor: noiseFloor,
            kneeWidth: kneeWidth,
            gamma: gamma,
            useInterpolation: useInterpolation ? 1 : 0,
            debugMode: 0
        )

        paramsBuffer = device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<ShaderParams>.stride,
            options: .storageModeShared
        )
    }

    // MARK: - Public API

    /// Accept pre-computed FFT magnitudes from AudioEngine
    /// This is called by the SwiftUI wrapper when new spectrogram data arrives
    func updateWithFFTMagnitudes(_ magnitudes: [Float]) {
        guard let texture = spectrogramTexture else { return }

        // Resample FFT data to texture resolution
        var columnData = [Float](repeating: 0.0, count: frequencyBins)

        for i in 0..<frequencyBins {
            let fftIndex = Int(Float(i) / Float(frequencyBins) * Float(magnitudes.count))
            columnData[i] = magnitudes[min(fftIndex, magnitudes.count - 1)]
        }

        // Reverse for proper orientation (high freq at top)
        columnData.reverse()

        // Write column to texture
        let region = MTLRegion(
            origin: MTLOrigin(x: currentColumn, y: 0, z: 0),
            size: MTLSize(width: 1, height: frequencyBins, depth: 1)
        )

        texture.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: columnData,
            bytesPerRow: MemoryLayout<Float>.stride
        )

        // Advance column (ring buffer)
        currentColumn = (currentColumn + 1) % timeColumns

        // Trigger redraw
        setNeedsDisplay()
    }

    // MARK: - Rendering

    override func draw(_ rect: CGRect) {
        guard let drawable = currentDrawable,
              let renderPassDescriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else { return }

        // Update shader parameters
        var params = ShaderParams(
            minDB: minDB,
            maxDB: maxDB,
            minFreq: minFrequency,
            maxFreq: maxFrequency,
            nyquist: sampleRate / 2.0,
            fftSize: Int32(4096),
            scrollOffset: Float(currentColumn) / Float(timeColumns),
            colormapType: Int32(colormapType),
            horizontalBlur: 0.0,
            noiseFloor: noiseFloor,
            kneeWidth: kneeWidth,
            gamma: gamma,
            useInterpolation: useInterpolation ? 1 : 0,
            debugMode: 0
        )

        guard let device = device else { return }
        paramsBuffer = device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<ShaderParams>.stride,
            options: .storageModeShared
        )

        // Set pipeline and resources
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(spectrogramTexture, index: 0)
        renderEncoder.setFragmentBuffer(paramsBuffer, offset: 0, index: 0)

        // Draw
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func reset() {
        currentColumn = 0
        clearTexture()
    }

    // MARK: - Parameter Setters

    func setColormap(_ type: Int) {
        colormapType = max(0, min(2, type))
    }

    func setNoiseFloor(_ db: Float) {
        noiseFloor = db
    }

    func setKneeWidth(_ width: Float) {
        kneeWidth = max(0.0, width)
    }

    func setGamma(_ value: Float) {
        gamma = max(0.1, min(2.0, value))
    }

    func setInterpolation(_ enabled: Bool) {
        useInterpolation = enabled
    }
}

// ============================================================================
// MARK: - SwiftUI Wrapper
// ============================================================================

struct HighEndSpectrogramAdapterView: UIViewRepresentable {
    @ObservedObject var audioEngine: AudioEngine

    func makeUIView(context: Context) -> HighEndSpectrogramAdapter {
        let view = HighEndSpectrogramAdapter(
            frame: .zero,
            device: MTLCreateSystemDefaultDevice()
        )
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: HighEndSpectrogramAdapter, context: Context) {
        // Updates handled through Coordinator's subscription
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(audioEngine: audioEngine)
    }

    class Coordinator: NSObject {
        var audioEngine: AudioEngine
        weak var view: HighEndSpectrogramAdapter?
        var cancellable: AnyCancellable?

        init(audioEngine: AudioEngine) {
            self.audioEngine = audioEngine
            super.init()

            // Subscribe to FFT data from AudioEngine
            cancellable = audioEngine.$currentSpectrogramData
                .compactMap { $0 }
                .sink { [weak self] data in
                    self?.view?.updateWithFFTMagnitudes(data.magnitudes)
                }
        }
    }
}

// ============================================================================
// MARK: - Container with Axis Labels
// ============================================================================

struct HighEndSpectrogramAdapterWithAxes: View {
    @ObservedObject var audioEngine: AudioEngine

    let axisWidth: CGFloat = 60
    let axisHeight: CGFloat = 30

    var showTimeAxis: Bool = true

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Y-Axis (Frequency)
                VStack(spacing: 0) {
                    ForEach(0..<8) { i in
                        Spacer()
                        Text(frequencyLabel(index: i))
                            .font(.caption2)
                            .foregroundColor(.white)
                            .frame(width: axisWidth, alignment: .trailing)
                            .padding(.trailing, 4)
                    }
                    Spacer()
                }

                VStack(spacing: 0) {
                    // Optimized Spectrogram View
                    HighEndSpectrogramAdapterView(audioEngine: audioEngine)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // X-Axis (Time)
                    if showTimeAxis {
                        GeometryReader { geo in
                            Canvas { context, size in
                                let duration = audioEngine.recordingDuration
                                guard duration > 0 else { return }

                                let displayDuration = min(duration, 60.0)
                                let (interval, labelCount) = calculateTimeInterval(
                                    duration: displayDuration,
                                    width: size.width
                                )

                                for i in 0...labelCount {
                                    let timeValue = -displayDuration + Double(i) * interval
                                    let xPos = (Double(i) / Double(labelCount)) * size.width

                                    let label = i == labelCount ? "Now" : formatTimeLabel(timeValue)

                                    context.draw(
                                        Text(label)
                                            .font(.caption2)
                                            .foregroundColor(.white),
                                        at: CGPoint(x: xPos, y: size.height / 2)
                                    )
                                }
                            }
                        }
                        .frame(height: axisHeight)
                    }
                }
            }
        }
    }

    private func frequencyLabel(index: Int) -> String {
        let minFreq = 20.0
        let maxFreq = 20000.0

        // Logarithmic scale
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let t = Double(7 - index) / 7.0  // Invert for top-to-bottom
        let freq = pow(10, logMin + t * (logMax - logMin))

        if freq >= 1000 {
            return String(format: "%.1f kHz", freq / 1000)
        } else {
            return String(format: "%.0f Hz", freq)
        }
    }

    private func calculateTimeInterval(duration: TimeInterval, width: CGFloat) -> (TimeInterval, Int) {
        let targetLabels = Int(width / 80)
        let labelCount = min(max(targetLabels, 2), 6)
        let interval = duration / Double(labelCount)
        return (interval, labelCount)
    }

    private func formatTimeLabel(_ time: TimeInterval) -> String {
        let absTime = abs(time)
        if absTime < 10 {
            return String(format: "-%.1fs", absTime)
        } else {
            return String(format: "-%.0fs", absTime)
        }
    }
}
