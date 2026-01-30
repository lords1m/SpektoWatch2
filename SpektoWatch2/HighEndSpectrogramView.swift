import MetalKit
import Accelerate
import OSLog

// ============================================================================
// MARK: - Shader Parameters Structure
// ============================================================================

struct ShaderParams {
    var minDB: Float           // e.g., -120.0
    var maxDB: Float           // e.g., -20.0
    var minFreq: Float         // e.g., 20.0 Hz
    var maxFreq: Float         // e.g., 20000.0 Hz
    var nyquist: Float         // e.g., 22050.0 Hz
    var fftSize: Int32         // e.g., 8192 (with zero-padding)
    var scrollOffset: Float    // Ring buffer offset (0 to 1)
    var colormapType: Int32    // 0 = Turbo, 1 = Jet, 2 = Viridis
    var horizontalBlur: Float  // Horizontal blur factor (deprecated)
    var noiseFloor: Float      // Noise gate threshold in dB (e.g., -100.0)
    var kneeWidth: Float       // Soft-knee width in dB (e.g., 15.0)
    var gamma: Float           // Gamma correction factor (e.g., 0.5)
    var useInterpolation: Int32 // 1 = bilinear, 0 = nearest
    var debugMode: Int32       // 0=normal, 1=grayscale, 2=colormap test, 3=raw magnitude
}

// ============================================================================
// MARK: - High-End Spectrogram Metal View
// ============================================================================

class HighEndSpectrogramView: MTKView {

    // MARK: - Metal Resources
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var computePipelineState: MTLComputePipelineState!
    private var vertexBuffer: MTLBuffer!
    private var paramsBuffer: MTLBuffer!

    // MARK: - Texture (Ring Buffer)
    private var spectrogramTexture: MTLTexture!
    private var currentColumn: Int = 0

    // MARK: - Configuration (Optimized)
    private let audioFFTSize: Int = 4096         // Audio window size (actual samples)
    private let fftSize: Int = 8192              // FFT size with zero-padding (2x resolution!)
    private let frequencyBins: Int = 1024        // Vertical texture resolution (increased from 512)
    private let timeColumns: Int = 1200          // Horizontal resolution (2 minutes at ~10 FPS)

    private let sampleRate: Float = 44100.0
    private let minFrequency: Float = 20.0       // 20 Hz
    private let maxFrequency: Float = 20000.0    // 20 kHz

    // MARK: - Calibration (dBFS → dB SPL)
    // Typische iPhone-Mikrofone: ~-26 dBFS bei 94 dB SPL
    // calibrationOffset = 94 - (-26) = 120 dB
    var calibrationOffset: Float = 120.0

    // Display range in dB SPL (nach Kalibrierung)
    private var minDB: Float { 0.0 }             // 0 dB SPL (sehr leise)
    private var maxDB: Float { 100.0 }           // 100 dB SPL (sehr laut)

    // MARK: - FFT Setup (Sliding Window with Zero-Padding)
    private var fftSetup: vDSP_DFT_Setup!
    private var hannWindow: [Float] = []         // Renamed to avoid UIView.window conflict
    private var audioBuffer: [Float] = []        // Accumulation buffer for sliding window
    private var audioBufferOffset: Int = 0       // Index-basierter Ansatz für O(1) statt O(n) removeFirst
    private let hopSize: Int = 512               // 87.5% overlap for smoother animation (was 1024)

    // MARK: - Display Parameters (Enhanced)
    var colormapType: Int = 0                    // 0 = Turbo, 1 = Jet, 2 = Viridis
    var noiseFloor: Float = 20.0                 // Noise gate threshold (dB SPL) - 20 dB SPL = sehr leise
    var kneeWidth: Float = 15.0                  // Soft-knee width (dB) - wider for smoother transition
    var gamma: Float = 0.75                       // Gamma correction (adjusted to balance colors)
    var useInterpolation: Bool = true            // Bilinear interpolation on/off
    var debugMode: Int = 0                       // 0=normal, 1=grayscale, 2=colormap test, 3=raw

    // MARK: - Initialization

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        setupMetal()
        setupFFT()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        device = MTLCreateSystemDefaultDevice()
        setupMetal()
        setupFFT()
    }

    deinit {
        if fftSetup != nil {
            vDSP_DFT_DestroySetup(fftSetup)
        }
    }

    // MARK: - Metal Setup

    private func setupMetal() {
        guard let device = device else {
            fatalError("Metal is not supported on this device")
        }

        // Configure MTKView
        self.framebufferOnly = false
        self.enableSetNeedsDisplay = false
        self.isPaused = false
        self.preferredFramesPerSecond = 60
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        // Create command queue
        commandQueue = device.makeCommandQueue()

        // Setup pipeline
        setupPipeline()

        // Setup geometry
        setupGeometry()

        // Setup texture
        setupTexture()

        // Setup parameters buffer
        setupParametersBuffer()
    }

    private func setupPipeline() {
        guard let device = device else { return }

        // Load shaders
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not load Metal library")
        }

        // Render pipeline
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

        // Compute pipeline (optional - for GPU-based FFT column writing)
        if let computeFunction = library.makeFunction(name: "writeFFTColumn") {
            do {
                computePipelineState = try device.makeComputePipelineState(function: computeFunction)
            } catch {
                Logger.metal.warning("Could not create compute pipeline: \(error.localizedDescription)")
            }
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
            fftSize: Int32(fftSize),
            scrollOffset: 0.0,
            colormapType: Int32(colormapType),
            horizontalBlur: 0.0,  // Deprecated
            noiseFloor: noiseFloor,
            kneeWidth: kneeWidth,
            gamma: gamma,
            useInterpolation: useInterpolation ? 1 : 0,
            debugMode: Int32(debugMode)
        )

        paramsBuffer = device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<ShaderParams>.stride,
            options: .storageModeShared
        )
    }

    // MARK: - FFT Setup (Sliding Window with Zero-Padding)

    private func setupFFT() {
        // Create FFT setup for PADDED size (8192) using zrop (Real-Only, more efficient)
        // This gives us 4096 frequency bins from only 4096 audio samples
        guard let setup = vDSP_DFT_zrop_CreateSetup(
            nil,
            vDSP_Length(fftSize),  // 8192 with zero-padding
            vDSP_DFT_Direction.FORWARD
        ) else {
            fatalError("Failed to create FFT setup")
        }
        fftSetup = setup

        // Create Hann window for AUDIO size (4096)
        hannWindow = [Float](repeating: 0, count: audioFFTSize)
        vDSP_hann_window(&hannWindow, vDSP_Length(audioFFTSize), Int32(vDSP_HANN_NORM))

        // Initialize audio buffer (empty)
        audioBuffer = []
    }

    // MARK: - Audio Processing (Sliding Window)

    /// Process incoming audio samples with sliding window (87.5% overlap)
    /// hopSize=512 gives ~86 updates/second for ultra-smooth animation
    func processAudioSamples(_ samples: [Float]) {
        // Accumulate samples
        audioBuffer.append(contentsOf: samples)

        // Process all complete windows with hop size (using offset for O(1) instead of O(n) removeFirst)
        while audioBuffer.count - audioBufferOffset >= audioFFTSize {
            // Extract window (4096 samples) using offset
            let windowSamples = Array(audioBuffer[audioBufferOffset..<(audioBufferOffset + audioFFTSize)])

            // Perform FFT with zero-padding (4096 → 8192)
            let magnitudes = performFFT(on: windowSamples)

            // Update texture with new column
            writeFFTColumn(magnitudes: magnitudes)

            // Advance offset by hop size (512 = 87.5% overlap)
            audioBufferOffset += hopSize

            // Periodisch aufräumen wenn Offset zu groß wird
            if audioBufferOffset > audioFFTSize * 2 {
                audioBuffer.removeFirst(audioBufferOffset)
                audioBufferOffset = 0
            }
        }
    }

    private func performFFT(on samples: [Float]) -> [Float] {
        // ZERO-PADDING: Take 4096 audio samples, pad to 8192 for 2x frequency resolution
        // Using zrop (Real-Only DFT) which is more efficient for real input

        // Allocate FFT buffers for zrop (interleaved input, split complex output)
        var windowed = [Float](repeating: 0, count: fftSize)   // 8192 elements (windowed + zero-padded)

        // Apply window and copy to input buffer (first 4096 samples)
        for i in 0..<audioFFTSize {
            windowed[i] = samples[i] * hannWindow[i]
        }
        // windowed[4096...8191] remains 0 (zero-padding)

        // zrop expects interleaved input: split into even/odd indices
        var realIn = [Float](repeating: 0, count: fftSize / 2)
        var imagIn = [Float](repeating: 0, count: fftSize / 2)
        for i in 0..<(fftSize / 2) {
            realIn[i] = windowed[2 * i]
            imagIn[i] = windowed[2 * i + 1]
        }

        var realOut = [Float](repeating: 0, count: fftSize / 2)
        var imagOut = [Float](repeating: 0, count: fftSize / 2)

        // Execute FFT (zrop is more efficient for real-only input)
        vDSP_DFT_Execute(fftSetup, realIn, imagIn, &realOut, &imagOut)

        // Compute magnitude spectrum using DSPSplitComplex
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)  // 4096 bins
        realOut.withUnsafeMutableBufferPointer { realPtr in
            imagOut.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        // DEBUG: Log magnitude range in dB SPL (with calibration)
        #if DEBUG
        if currentColumn % 60 == 0 {  // Log every 60 frames (~1 second)
            let maxMagnitude = magnitudes.max() ?? 0
            let nonZeroMags = magnitudes.filter { $0 > 1e-10 }
            let minMagnitude = nonZeroMags.min() ?? 1e-10
            let avgMagnitude = nonZeroMags.reduce(0, +) / Float(max(1, nonZeroMags.count))

            // dB SPL = dBFS + calibrationOffset
            let maxDBSPL = 20.0 * log10(maxMagnitude + 1e-10) + calibrationOffset
            let minDBSPL = 20.0 * log10(minMagnitude + 1e-10) + calibrationOffset
            let avgDBSPL = 20.0 * log10(avgMagnitude + 1e-10) + calibrationOffset

            Logger.metal.debug("FFT dB SPL Range: min=\(minDBSPL, format: .fixed(precision: 1)) avg=\(avgDBSPL, format: .fixed(precision: 1)) max=\(maxDBSPL, format: .fixed(precision: 1))")
        }
        #endif

        return magnitudes  // 4096 frequency bins (doubled from 2048!)
    }

    private func writeFFTColumn(magnitudes: [Float]) {
        guard let texture = spectrogramTexture else { return }

        // Kalibrierungsfaktor: skaliert Magnitudes so, dass nach dB-Konvertierung
        // im Shader die Werte in dB SPL sind statt dBFS
        // dB SPL = 20*log10(mag) + offset = 20*log10(mag * 10^(offset/20))
        let calibrationScale = pow(10.0, calibrationOffset / 20.0)

        // Resample FFT data to texture resolution (frequencyBins)
        var columnData = [Float](repeating: 0.0, count: frequencyBins)

        for i in 0..<frequencyBins {
            // Linear mapping from texture row to FFT bin
            let fftIndex = Int(Float(i) / Float(frequencyBins) * Float(magnitudes.count))
            // Wende Kalibrierung an
            columnData[i] = magnitudes[min(fftIndex, magnitudes.count - 1)] * calibrationScale
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
            fftSize: Int32(fftSize),
            scrollOffset: Float(currentColumn) / Float(timeColumns),
            colormapType: Int32(colormapType),
            horizontalBlur: 0.0,  // Deprecated
            noiseFloor: noiseFloor,
            kneeWidth: kneeWidth,
            gamma: gamma,
            useInterpolation: useInterpolation ? 1 : 0,
            debugMode: Int32(debugMode)
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

    // MARK: - Public API

    func reset() {
        currentColumn = 0
        audioBuffer = []
        audioBufferOffset = 0
        clearTexture()
    }

    func setColormap(_ type: Int) {
        colormapType = max(0, min(2, type))  // 0-2
    }

    /// Set noise gate threshold (dB SPL). Recommended: 15 to 30 dB SPL
    func setNoiseFloor(_ db: Float) {
        noiseFloor = db
    }

    /// Set calibration offset (dBFS → dB SPL). Default: 120 dB
    /// Typical iPhone microphones: -26 dBFS at 94 dB SPL → offset = 120
    func setCalibrationOffset(_ offset: Float) {
        calibrationOffset = offset
    }

    /// Set soft-knee width (dB). Recommended: 5 to 15
    func setKneeWidth(_ width: Float) {
        kneeWidth = max(0.0, width)
    }

    /// Set gamma correction. < 1.0 = more detail in quiet, > 1.0 = emphasize loud
    /// Recommended: 0.6 to 0.8 for most content
    func setGamma(_ value: Float) {
        gamma = max(0.1, min(2.0, value))
    }

    /// Enable/disable bilinear interpolation for smoother appearance
    func setInterpolation(_ enabled: Bool) {
        useInterpolation = enabled
    }

    /// Set debug mode: 0=normal, 1=grayscale, 2=colormap test, 3=raw magnitude
    func setDebugMode(_ mode: Int) {
        debugMode = max(0, min(3, mode))
    }
}
