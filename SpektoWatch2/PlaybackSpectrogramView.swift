import SwiftUI
import MetalKit
import Accelerate

/// Ein scrollbares Spektrogramm für die Wiedergabe von Aufnahmen
/// Zeigt die gesamte Aufnahme als "Filmrolle" an, die mit einem Zeitschieber synchronisiert ist
class PlaybackSpectrogramRenderer: MTKView {
    // MARK: - Metal Resources
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer!
    private var paramsBuffer: MTLBuffer!

    // MARK: - Spectrogram Texture
    private var spectrogramTexture: MTLTexture!
    private var textureWidth: Int = 0
    private var textureHeight: Int = 512  // Frequency bins

    // MARK: - Data
    private var magnitudeHistory: [[Float]] = []
    private var isTextureReady = false

    // MARK: - Display Parameters
    var colormapType: Int = 0
    private let minDB: Float = -90.0
    private let maxDB: Float = -10.0
    private let noiseFloor: Float = -90.0
    private let splToDbfsOffset: Float = 120.0

    // MARK: - Scroll/Zoom
    var viewportStart: Float = 0.0   // 0.0 = Anfang, 1.0 = Ende
    var viewportWidth: Float = 1.0   // 1.0 = gesamte Aufnahme sichtbar

    // MARK: - Playhead
    var playheadPosition: Float = 0.0  // 0.0 bis 1.0

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
        guard let device = device else {
            fatalError("Metal is not supported")
        }

        self.framebufferOnly = false
        self.enableSetNeedsDisplay = true
        self.isPaused = true  // Nur bei Bedarf rendern
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        commandQueue = device.makeCommandQueue()
        setupPipeline()
        setupGeometry()
    }

    private func setupPipeline() {
        guard let device = device,
              let library = device.makeDefaultLibrary() else { return }

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
            fatalError("Failed to create pipeline: \(error)")
        }
    }

    private func setupGeometry() {
        guard let device = device else { return }

        let vertices: [Float] = [
            -1.0, -1.0, 0.0, 1.0,
             1.0, -1.0, 1.0, 1.0,
            -1.0,  1.0, 0.0, 0.0,
             1.0,  1.0, 1.0, 0.0
        ]

        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )

        paramsBuffer = device.makeBuffer(
            length: MemoryLayout<HighEndSpectrogramShaderParams>.stride,
            options: .storageModeShared
        )
    }

    // MARK: - Data Loading

    /// Lädt Spektrogramm-Daten aus einer Magnitude-Historie
    func loadSpectrogramData(_ history: [[Float]]) {
        guard !history.isEmpty else { return }

        magnitudeHistory = history
        textureWidth = history.count
        textureHeight = history.first?.count ?? 512

        createTexture()
        fillTexture()
        isTextureReady = true
        setNeedsDisplay()
    }

    /// Berechnet Spektrogramm-Daten aus Audio-Samples
    func computeFromAudioSamples(_ samples: [Float], sampleRate: Double, fftSize: Int = 4096, hopSize: Int = 512) {
        guard samples.count > fftSize else { return }

        var history: [[Float]] = []

        // FFT Setup
        guard let fftSetup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD) else { return }
        defer { vDSP_DFT_DestroySetup(fftSetup) }

        // Hann Window
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        var offset = 0
        while offset + fftSize <= samples.count {
            // Extract window
            let windowSamples = Array(samples[offset..<(offset + fftSize)])

            // Apply window
            var windowed = [Float](repeating: 0, count: fftSize)
            vDSP_vmul(windowSamples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

            // Prepare for zrop (interleaved input)
            var realIn = [Float](repeating: 0, count: fftSize / 2)
            var imagIn = [Float](repeating: 0, count: fftSize / 2)
            for i in 0..<(fftSize / 2) {
                realIn[i] = windowed[2 * i]
                imagIn[i] = windowed[2 * i + 1]
            }

            var realOut = [Float](repeating: 0, count: fftSize / 2)
            var imagOut = [Float](repeating: 0, count: fftSize / 2)

            vDSP_DFT_Execute(fftSetup, realIn, imagIn, &realOut, &imagOut)

            // Compute magnitude
            var magnitudes = [Float](repeating: 0, count: fftSize / 2)
            realOut.withUnsafeMutableBufferPointer { realPtr in
                imagOut.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
                }
            }

            // Convert to dB
            var dbMagnitudes = [Float](repeating: -120.0, count: magnitudes.count)
            for i in 0..<magnitudes.count {
                let db = 20.0 * log10(magnitudes[i] + 1e-10)
                dbMagnitudes[i] = db + splToDbfsOffset  // Convert to dB SPL
            }

            // Resample to textureHeight bins
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

        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = .r32Float
        descriptor.width = textureWidth
        descriptor.height = textureHeight
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared

        spectrogramTexture = device.makeTexture(descriptor: descriptor)
    }

    private func fillTexture() {
        guard let texture = spectrogramTexture else { return }

        for (columnIndex, column) in magnitudeHistory.enumerated() {
            // Convert dB SPL back to dBFS for shader
            var columnData = [Float](repeating: 0, count: textureHeight)
            for i in 0..<min(column.count, textureHeight) {
                let dbFS = column[i] - splToDbfsOffset
                columnData[i] = pow(10.0, dbFS / 20.0)
            }

            // Reverse for orientation
            columnData.reverse()

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
              let renderPassDescriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else { return }

        // Calculate scroll offset based on viewport
        // viewportStart = 0 means we see from the beginning
        // We want the playhead to be visible, so adjust texture coordinates
        let scrollOffset = viewportStart

        var params = HighEndSpectrogramShaderParams(
            minDB: minDB,
            maxDB: maxDB,
            minFreq: 20.0,
            maxFreq: 16000.0,
            nyquist: 22050.0,
            fftSize: Int32(textureHeight * 2),
            scrollOffset: scrollOffset,
            colormapType: Int32(colormapType),
            horizontalBlur: 0.0,
            noiseFloor: noiseFloor,
            kneeWidth: 10.0,
            gamma: 0.8,
            useInterpolation: 1,
            debugMode: 0
        )

        memcpy(paramsBuffer.contents(), &params, MemoryLayout<HighEndSpectrogramShaderParams>.stride)

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(spectrogramTexture, index: 0)
        renderEncoder.setFragmentBuffer(paramsBuffer, offset: 0, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Public API

    func setPlayheadPosition(_ position: Float) {
        playheadPosition = max(0, min(1, position))
        setNeedsDisplay()
    }

    func setColormap(_ type: Int) {
        colormapType = type
        setNeedsDisplay()
    }

    func getFrameCount() -> Int {
        return magnitudeHistory.count
    }
}

// MARK: - SwiftUI Wrapper

struct PlaybackSpectrogramView: UIViewRepresentable {
    var magnitudeHistory: [[Float]]
    var playheadPosition: Float
    var colormapType: Int

    func makeUIView(context: Context) -> PlaybackSpectrogramRenderer {
        let view = PlaybackSpectrogramRenderer(
            frame: .zero,
            device: MTLCreateSystemDefaultDevice()
        )
        view.setColormap(colormapType)
        if !magnitudeHistory.isEmpty {
            view.loadSpectrogramData(magnitudeHistory)
        }
        return view
    }

    func updateUIView(_ uiView: PlaybackSpectrogramRenderer, context: Context) {
        uiView.setColormap(colormapType)
        uiView.setPlayheadPosition(playheadPosition)

        // Update data if changed
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
    var onSeek: (TimeInterval) -> Void

    @State private var dragOffset: CGFloat = 0
    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let playheadX = totalWidth * CGFloat(currentTime / max(duration, 0.001))

            ZStack(alignment: .leading) {
                // Spectrogram Background
                PlaybackSpectrogramView(
                    magnitudeHistory: magnitudeHistory,
                    playheadPosition: Float(currentTime / max(duration, 0.001)),
                    colormapType: colormapType
                )
                .cornerRadius(12)

                // Playhead Line
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2)
                    .offset(x: playheadX)
                    .shadow(color: .black.opacity(0.5), radius: 2)

                // Current Time Indicator
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
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = value.location.x / totalWidth
                        let newTime = Double(fraction) * duration
                        onSeek(max(0, min(newTime, duration)))
                    }
            )
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
