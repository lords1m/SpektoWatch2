import MetalKit
import Accelerate
import SwiftUI
import Combine

// ============================================================================
// MARK: - Shader Parameters Structure
// ============================================================================

struct HighEndSpectrogramShaderParams {
    var minDB: Float
    var maxDB: Float
    var minFreq: Float
    var maxFreq: Float
    var nyquist: Float
    var fftSize: Int32
    var scrollOffset: Float
    var colormapType: Int32
    var horizontalBlur: Float
    var noiseFloor: Float
    var kneeWidth: Float
    var gamma: Float
    var useInterpolation: Int32
    var debugMode: Int32
}

// ============================================================================
// MARK: - Adapter View (uses existing FFT from AudioEngine)
// ============================================================================

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
    private let frequencyBins: Int = 1024
    private let timeColumns: Int = 600
    private let sampleRate: Float = 44100.0
    private let minFrequency: Float = 20.0
    private let maxFrequency: Float = 16000.0
    private let minDB: Float = -120.0  // KORRIGIERT: Größerer dynamischer Bereich
    private let maxDB: Float = -20.0
    
    // MARK: - Display Parameters (KORRIGIERT)
    var colormapType: Int = 0
    var noiseFloor: Float = -90.0  // KORRIGIERT: Angepasst an realistischen Noise Floor
    var kneeWidth: Float = 10.0    // KORRIGIERT: Moderate Knee Width
    var gamma: Float = 0.5         // KORRIGIERT: Ausgewogene Gamma-Korrektur
    var useInterpolation: Bool = true
    
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
        
        // Full-screen quad with correct texture coordinates
        let vertices: [Float] = [
            -1.0, -1.0, 0.0, 1.0,  // Bottom-left
             1.0, -1.0, 1.0, 1.0,  // Bottom-right
            -1.0,  1.0, 0.0, 0.0,  // Top-left
             1.0,  1.0, 1.0, 0.0   // Top-right
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
        var data = [Float](repeating: 1e-10, count: texture.width * texture.height)
        
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
        
        var params = HighEndSpectrogramShaderParams(
            minDB: minDB,
            maxDB: maxDB,
            minFreq: minFrequency,
            maxFreq: maxFrequency,
            nyquist: sampleRate / 2.0,
            fftSize: Int32(4096),
            scrollOffset: 0.0,
            colormapType: Int32(colormapType),
            horizontalBlur: 0.0,
            noiseFloor: noiseFloor,
            kneeWidth: kneeWidth,
            gamma: gamma,
            useInterpolation: useInterpolation ? 1 : 0,
            debugMode: 0
        )
        
        paramsBuffer = device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<HighEndSpectrogramShaderParams>.stride,
            options: .storageModeShared
        )
    }
    
    // MARK: - Public API (KORRIGIERT)
    
    /// KORREKTUR: Akzeptiere FFT Magnituden direkt als lineare Werte
    /// AudioEngine sollte lineare Magnituden liefern, nicht dB
    /// Akzeptiere FFT Magnituden und mappe sie logarithmisch auf die Textur
func updateWithFFTMagnitudes(_ magnitudes: [Float]) {
    guard let texture = spectrogramTexture else { return }
    
    // KORREKTUR: Logarithmisches Mapping beim SCHREIBEN in die Textur
    var columnData = [Float](repeating: 1e-10, count: frequencyBins)
    
    let nyquist = sampleRate / 2.0
    let logMinFreq = log2(minFrequency)
    let logMaxFreq = log2(maxFrequency)
    
    for i in 0..<frequencyBins {
        // Berechne welche Frequenz diese Texturzeile repräsentiert
        // i=0 (unten) = minFrequency, i=frequencyBins-1 (oben) = maxFrequency
        let t = Float(i) / Float(frequencyBins - 1)
        let frequency = exp2(logMinFreq + t * (logMaxFreq - logMinFreq))
        
        // Konvertiere Frequenz zu FFT-Bin
        let binIndex = (frequency / nyquist) * Float(magnitudes.count)
        let clampedIndex = Int(binIndex.rounded())
        
        if clampedIndex >= 0 && clampedIndex < magnitudes.count {
            columnData[i] = magnitudes[clampedIndex]
        }
    }
    
    // Schreibe Spalte in Textur
    let region = MTLRegion(
        origin: MTLOrigin(x: currentColumn, y: 0, z: 0),
        size: MTLSize(width: 1, height: frequencyBins, depth: 1)
    )
    
    let bytesPerRow = MemoryLayout<Float>.stride
    texture.replace(
        region: region,
        mipmapLevel: 0,
        withBytes: columnData,
        bytesPerRow: bytesPerRow
    )
    
    currentColumn = (currentColumn + 1) % timeColumns
    setNeedsDisplay()
}
    
    // MARK: - Rendering
    override func draw(_ rect: CGRect) {
        guard let drawable = currentDrawable,
              let renderPassDescriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else { return }
        
        var params = HighEndSpectrogramShaderParams(
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
            length: MemoryLayout<HighEndSpectrogramShaderParams>.stride,
            options: .storageModeShared
        )
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(spectrogramTexture, index: 0)
        renderEncoder.setFragmentBuffer(paramsBuffer, offset: 0, index: 0)
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
            
            cancellable = audioEngine.$currentSpectrogramData
                .compactMap { $0 }
                .sink { [weak self] data in
                    // WICHTIG: Stelle sicher, dass AudioEngine lineare Magnituden liefert
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
                
                // Spectrogram View
                HighEndSpectrogramAdapterView(audioEngine: audioEngine)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func frequencyLabel(index: Int) -> String {
        let minFreq = 20.0
        let maxFreq = 16000.0
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let t = Double(7 - index) / 7.0
        let freq = pow(10, logMin + t * (logMax - logMin))
        
        if freq >= 1000 {
            return String(format: "%.1f kHz", freq / 1000)
        } else {
            return String(format: "%.0f Hz", freq)
        }
    }
}
