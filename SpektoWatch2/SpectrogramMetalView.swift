import MetalKit
import Accelerate
import os.signpost
import Foundation

class SpectrogramMetalView: MTKView {
    private static let performanceLog = OSLog(subsystem: "com.spektowatch", category: "performance.render")
    
    // Metal resources
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer!
    private var textureSizeBuffer: MTLBuffer!
    private var stretchFactorBuffer: MTLBuffer!
    private var displayParamsBuffer: MTLBuffer!
    
    // Spectrogram texture (ring buffer for time axis)
    private var spectrogramTexture: MTLTexture!
    private var currentColumn: Int = 0
    private var totalColumnsWritten: Int = 0  // Track total columns for dynamic scaling

    // Configuration
    private let frequencyBins: Int = 256  // Display bins (after log scaling) - reduced for coarser resolution
    private let timeColumns: Int = 600    // Fixed buffer size (60 seconds at ~10 updates/sec)
    private let minFrequency: Float = 31.5
    private let maxFrequency: Float = 16000.0
    private var recordingStartTime: Date?
    private let maxDisplayTime: TimeInterval = 60.0  // After 60s, switch to scrolling mode
    private var columnAdvanceStep: Int = 2
    private var lastQualityEvaluationTime: TimeInterval = 0

    // Decay/fade effect for motion blur (0.0 = no persistence, 1.0 = infinite persistence)
    // Recommended range: 0.85 - 0.98
    // Higher values = stronger persistence/trailing effect
    // Lower values = faster fade/less smearing
    public var decayFactor: Float = 0.98  // Increased for stronger horizontal blur

    // Horizontal stretch factor for wider appearance (1.0 = no stretch, higher = wider)
    // This is handled in the shader for better performance
    public var horizontalStretch: Float = 10.0  // Increased for more horizontal blur/smearing
    
    // Logarithmic frequency mapping
    private var frequencyBinMapping: [Int] = []
    
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
        
        // Setup spectrogram texture
        setupSpectrogramTexture()
        
        // Setup frequency mapping
        setupFrequencyMapping()
    }
    
    private func setupPipeline() {
        guard let device = device else { return }
        
        // Load shaders
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not load Metal library")
        }
        
        let vertexFunction = library.makeFunction(name: "spectrogramVertexShader")
        let fragmentFunction = library.makeFunction(name: "spectrogramFragmentShaderSimple")
        
        // Create vertex descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        
        // Position attribute (attribute 0)
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        // Texture coordinate attribute (attribute 1)
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.stride * 2
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        // Buffer layout (4 floats per vertex: 2 for position, 2 for texCoord)
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 4
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Create pipeline descriptor
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        // Create pipeline state
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
    }
    
    private func setupGeometry() {
        guard let device = device else { return }
        
        // Full-screen quad with texture coordinates
        let vertices: [Float] = [
            // Position (x, y)    TexCoord (u, v)
            -1.0, -1.0,          0.0, 1.0,  // Bottom-left
             1.0, -1.0,          1.0, 1.0,  // Bottom-right
            -1.0,  1.0,          0.0, 0.0,  // Top-left
             1.0,  1.0,          1.0, 0.0   // Top-right
        ]
        
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
        
        // Texture size buffer
        var textureSize = SIMD2<Float>(Float(timeColumns), Float(frequencyBins))
        textureSizeBuffer = device.makeBuffer(
            bytes: &textureSize,
            length: MemoryLayout<SIMD2<Float>>.stride,
            options: .storageModeShared
        )

        // Stretch factor buffer
        var stretch = horizontalStretch
        stretchFactorBuffer = device.makeBuffer(
            bytes: &stretch,
            length: MemoryLayout<Float>.stride,
            options: .storageModeShared
        )

        // Display params buffer (fillRatio, currentColumn, isScrolling, padding)
        var displayParams = SIMD4<Float>(0.0, 0.0, 0.0, 0.0)
        displayParamsBuffer = device.makeBuffer(
            bytes: &displayParams,
            length: MemoryLayout<SIMD4<Float>>.stride,
            options: .storageModeShared
        )
    }
    
    private func setupSpectrogramTexture() {
        guard let device = device else { return }
        
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.textureType = .type2D
        textureDescriptor.pixelFormat = .r32Float  // Single channel float
        textureDescriptor.width = timeColumns
        textureDescriptor.height = frequencyBins
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        textureDescriptor.storageMode = .shared
        
        spectrogramTexture = device.makeTexture(descriptor: textureDescriptor)
        
        // Clear texture to black
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
    
    private func setupFrequencyMapping() {
        // Create logarithmic frequency mapping
        // Maps FFT bins to display bins with logarithmic spacing
        
        let sampleRate: Float = 44100.0
        let fftSize: Int = 8192  // Assuming 8192 FFT size from AudioEngine
        let nyquist = sampleRate / 2.0
        
        frequencyBinMapping = []
        
        for displayBin in 0..<frequencyBins {
            // Calculate logarithmic frequency for this display bin
            let t = Float(displayBin) / Float(frequencyBins - 1)
            let logMin = log2(minFrequency)
            let logMax = log2(maxFrequency)
            let frequency = pow(2.0, logMin + t * (logMax - logMin))
            
            // Convert frequency to FFT bin index
            let fftBin = Int((frequency / nyquist) * Float(fftSize / 2))
            frequencyBinMapping.append(min(fftBin, fftSize / 2 - 1))
        }
    }
    
    // MARK: - Public API
    
    /// Update spectrogram with new FFT data
    /// - Parameter magnitudes: Array of magnitude values from FFT (normalized 0-1)
    func updateWithFFTData(_ magnitudes: [Float]) {
        let signpostID = OSSignpostID(log: Self.performanceLog)
        os_signpost(.begin, log: Self.performanceLog, name: "TextureUpload", signpostID: signpostID)
        defer { os_signpost(.end, log: Self.performanceLog, name: "TextureUpload", signpostID: signpostID) }

        guard let texture = spectrogramTexture else { return }

        // Start recording timer if not started
        if recordingStartTime == nil {
            recordingStartTime = Date()
            totalColumnsWritten = 0
        }

        // Apply logarithmic frequency mapping
        var displayData = [Float](repeating: 0.0, count: frequencyBins)

        for (displayIndex, fftBinIndex) in frequencyBinMapping.enumerated() {
            if fftBinIndex < magnitudes.count {
                displayData[displayIndex] = magnitudes[fftBinIndex]
            }
        }

        // Reverse the array so high frequencies are at the top
        displayData.reverse()

        // PERFORMANCE OPTIMIZATION: Removed texture.getBytes() call that was blocking the main thread
        // The decay/persistence effect is now achieved through:
        // 1. Higher decay factor (0.98 instead of 0.92)
        // 2. Horizontal stretching in shader (creates visual smearing)
        // 3. Bilinear interpolation in shader (smooths transitions)

        let region = MTLRegion(
            origin: MTLOrigin(x: currentColumn, y: 0, z: 0),
            size: MTLSize(width: 1, height: frequencyBins, depth: 1)
        )

        // Write new column directly to texture (no read-modify-write)
        texture.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: displayData,
            bytesPerRow: MemoryLayout<Float>.stride
        )

        // Increment total columns written
        totalColumnsWritten += 1

        // Advance to next column
        // Before 60s: fill buffer sequentially, after 60s: use ring buffer
        if totalColumnsWritten < timeColumns {
            // Dynamic scaling phase: just advance
            currentColumn = totalColumnsWritten % timeColumns
        } else {
            // Scrolling phase: ring buffer with faster scrolling
            currentColumn = (currentColumn + columnAdvanceStep) % timeColumns
        }

        // PERFORMANCE OPTIMIZATION: Removed decayColumn() call
        // This was causing double texture reads/writes and severely impacting performance
        // The visual decay effect is now handled by shader interpolation

        // Trigger redraw
        setNeedsDisplay()
    }

    /// Reset recording state
    func resetRecording() {
        recordingStartTime = nil
        currentColumn = 0
        totalColumnsWritten = 0
        clearTexture()
    }

    /// Get the current display mode and parameters for shader
    func getDisplayInfo() -> (isScrolling: Bool, fillRatio: Float, currentColumn: Int) {
        let isScrolling = totalColumnsWritten >= timeColumns
        let fillRatio = isScrolling ? 1.0 : Float(totalColumnsWritten) / Float(timeColumns)
        return (isScrolling, fillRatio, currentColumn)
    }

    // REMOVED: decayColumn() method - was causing performance issues
    // The decay effect is now achieved through shader interpolation and higher decay factor

    // MARK: - Rendering
    
    override func draw(_ rect: CGRect) {
        let signpostID = OSSignpostID(log: Self.performanceLog)
        os_signpost(.begin, log: Self.performanceLog, name: "MetalDraw", signpostID: signpostID)
        defer { os_signpost(.end, log: Self.performanceLog, name: "MetalDraw", signpostID: signpostID) }
        updateRuntimeQualityIfNeeded()

        guard let drawable = currentDrawable,
              let renderPassDescriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else { return }

        renderEncoder.setRenderPipelineState(pipelineState)

        // Set vertex buffer
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        // Set texture
        renderEncoder.setFragmentTexture(spectrogramTexture, index: 0)

        // Update display params
        let (isScrolling, fillRatio, currentCol) = getDisplayInfo()
        var displayParams = SIMD4<Float>(
            fillRatio,
            Float(currentCol),
            isScrolling ? 1.0 : 0.0,
            0.0  // padding
        )

        guard let device = device else { return }
        displayParamsBuffer = device.makeBuffer(
            bytes: &displayParams,
            length: MemoryLayout<SIMD4<Float>>.stride,
            options: .storageModeShared
        )

        // Set buffers
        renderEncoder.setFragmentBuffer(stretchFactorBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentBuffer(displayParamsBuffer, offset: 0, index: 1)

        // Draw full-screen quad (triangle strip)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    // MARK: - Utility

    /// Update the horizontal stretch factor
    /// - Parameter factor: Stretch factor (1.0 = no stretch, higher = wider)
    func updateStretchFactor(_ factor: Float) {
        self.horizontalStretch = max(1.0, factor)

        guard let device = device else { return }

        // Update buffer
        var stretch = horizontalStretch
        stretchFactorBuffer = device.makeBuffer(
            bytes: &stretch,
            length: MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
    }

    /// Update the decay/persistence factor
    /// - Parameter factor: Decay factor (0.0 = no persistence, 1.0 = infinite)
    func updateDecayFactor(_ factor: Float) {
        self.decayFactor = max(0.0, min(1.0, factor))
    }

    /// Get frequency for a given Y position (for axis labels)
    func frequencyForYPosition(_ normalizedY: Float) -> Float {
        let logMin = log2(minFrequency)
        let logMax = log2(maxFrequency)
        // Y goes from 0 (top/high freq) to 1 (bottom/low freq), so we need to invert
        let t = 1.0 - normalizedY
        return pow(2.0, logMin + t * (logMax - logMin))
    }

    private func updateRuntimeQualityIfNeeded() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastQualityEvaluationTime >= 1.0 else { return }
        lastQualityEvaluationTime = now

        let processInfo = ProcessInfo.processInfo
        let lowPower = processInfo.isLowPowerModeEnabled
        let thermal = processInfo.thermalState

        let targetFPS: Int
        let targetStep: Int

        if thermal == .critical {
            targetFPS = 30
            targetStep = 4
        } else if thermal == .serious || lowPower {
            targetFPS = 40
            targetStep = 3
        } else if thermal == .fair {
            targetFPS = 50
            targetStep = 2
        } else {
            targetFPS = 60
            targetStep = 2
        }

        if preferredFramesPerSecond != targetFPS {
            preferredFramesPerSecond = targetFPS
        }
        if columnAdvanceStep != targetStep {
            columnAdvanceStep = targetStep
        }
    }
}
