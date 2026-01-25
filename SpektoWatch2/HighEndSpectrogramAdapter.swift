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
    private let frequencyBins: Int = 2048 // Doppelte vertikale Auflösung
    private var timeColumns: Int = 600
    private var hopSize: Int = 512 // Default (Fast)
    private var currentTimeSpanValue: Int = 5 // Default 5s
    private let sampleRate: Float = 44100.0
    private let minFrequency: Float = 20.0
    private let maxFrequency: Float = 16000.0
    private let minDB: Float = -90.0   // Angepasst für feinere Farbauflösung im relevanten Bereich
    private let maxDB: Float = -10.0   // Angepasst, damit Signale heller leuchten
    
    // MARK: - Display Parameters (KORRIGIERT)
    var colormapType: Int = 0
    var noiseFloor: Float = -90.0  // KORRIGIERT: Angepasst an realistischen Noise Floor
    var kneeWidth: Float = 10.0    // KORRIGIERT: Moderate Knee Width
    var gamma: Float = 0.8         // KORRIGIERT: Etwas höherer Gamma für mehr Details in den Mitten
    var useInterpolation: Bool = true
    var horizontalBlur: Float = 0.0 // Horizontaler Weichzeichner (0.0 = aus, 1.0 = leicht, 2.0+ = stark)
    var isUpdatesPaused: Bool = false
    var manualScrollOffset: Float = 0.0
    private var debugPrintCounter = 0
    
    // PERFORMANCE: Cache für Frequenz-Mapping
    private struct MappingCacheEntry {
        let isInterpolated: Bool
        // Für Interpolation
        let index0: Int
        let index1: Int
        let fraction: Float
        // Für Max-Pooling
        let startBin: Int
        let endBin: Int
    }
    private var mappingCache: [MappingCacheEntry]?
    private var cachedInputSize: Int = 0

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
        self.preferredFramesPerSecond = 120
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        self.sampleCount = 4 // MSAA (4x Multisampling) für Kantenglättung aktivieren
        
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
        pipelineDescriptor.sampleCount = 4 // Pipeline muss zum View passen (4x MSAA)
        
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
            fftSize: Int32(8192),
            scrollOffset: 0.0,
            colormapType: Int32(colormapType),
            horizontalBlur: horizontalBlur,
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
    
    if isUpdatesPaused { return }
    
    // Cache aktualisieren falls nötig
    if mappingCache == nil || cachedInputSize != magnitudes.count {
        precomputeMapping(inputSize: magnitudes.count)
    }
    
    // KORREKTUR: Logarithmisches Mapping beim SCHREIBEN in die Textur
    var columnData = [Float](repeating: 1e-10, count: frequencyBins)
    
    let nyquist = sampleRate / 2.0
    let logMinFreq = log2(minFrequency)
    let logMaxFreq = log2(maxFrequency)
    let magCount = Float(magnitudes.count)
    
    guard let cache = mappingCache else { return }
    
    for i in 0..<frequencyBins {
        let entry = cache[i]
        
        var dbValue: Float = -120.0
        
        if entry.isInterpolated {
            let v0 = (entry.index0 >= 0 && entry.index0 < magnitudes.count) ? magnitudes[entry.index0] : -120.0
            let v1 = (entry.index1 >= 0 && entry.index1 < magnitudes.count) ? magnitudes[entry.index1] : -120.0
            
            dbValue = v0 * (1.0 - entry.fraction) + v1 * entry.fraction
        } else {
            var maxVal: Float = -1000.0
            for b in entry.startBin...entry.endBin {
                if b >= 0 && b < magnitudes.count {
                    maxVal = max(maxVal, magnitudes[b])
                }
            }
            
            if maxVal > -1000.0 {
                dbValue = maxVal
            } else {
                // Fallback (sollte durch cache logic abgedeckt sein, aber sicherheitshalber)
                dbValue = -120.0
            }
        }
        
        // dB zurück zu Linear für Shader
        columnData[i] = pow(10.0, dbValue / 20.0)
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
    
    private func precomputeMapping(inputSize: Int) {
        var newCache = [MappingCacheEntry]()
        newCache.reserveCapacity(frequencyBins)
        
        let nyquist = sampleRate / 2.0
        let logMinFreq = log2(minFrequency)
        let logMaxFreq = log2(maxFrequency)
        let magCount = Float(inputSize)
        
        for i in 0..<frequencyBins {
            let t = Float(i) / Float(frequencyBins - 1)
            let frequency = exp2(logMinFreq + t * (logMaxFreq - logMinFreq))
            
            let tNext = Float(i + 1) / Float(frequencyBins - 1)
            let freqNext = exp2(logMinFreq + tNext * (logMaxFreq - logMinFreq))
            
            // Für i=0 nutzen wir die Distanz zum nächsten, da i-1 nicht existiert
            let pixelBandwidth = (i < frequencyBins - 1) ? (freqNext - frequency) : (frequency - exp2(logMinFreq + Float(i - 1) / Float(frequencyBins - 1) * (logMaxFreq - logMinFreq)))
            
            let centerBin = (frequency / nyquist) * magCount
            let binWidth = (pixelBandwidth / nyquist) * magCount
            
            if binWidth < 1.0 {
                let index0 = Int(floor(centerBin))
                let index1 = index0 + 1
                let fraction = centerBin - Float(index0)
                newCache.append(MappingCacheEntry(isInterpolated: true, index0: index0, index1: index1, fraction: fraction, startBin: 0, endBin: 0))
            } else {
                let halfWidth = binWidth / 2.0
                let startBin = Int(floor(centerBin - halfWidth))
                let endBin = Int(ceil(centerBin + halfWidth))
                newCache.append(MappingCacheEntry(isInterpolated: false, index0: 0, index1: 0, fraction: 0, startBin: startBin, endBin: endBin))
            }
        }
        
        mappingCache = newCache
        cachedInputSize = inputSize
    }
    
    // MARK: - Rendering
    override func draw(_ rect: CGRect) {
        guard let drawable = currentDrawable,
              let renderPassDescriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else { return }
        
        let baseOffset = Float(currentColumn) / Float(timeColumns)
        let totalOffset = baseOffset + manualScrollOffset
        
        var params = HighEndSpectrogramShaderParams(
            minDB: minDB,
            maxDB: maxDB,
            minFreq: minFrequency,
            maxFreq: maxFrequency,
            nyquist: sampleRate / 2.0,
            fftSize: Int32(8192),
            scrollOffset: totalOffset,
            colormapType: Int32(colormapType),
            horizontalBlur: horizontalBlur,
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
    
    func setHorizontalBlur(_ blur: Float) {
        horizontalBlur = blur
    }
    
    func setHopSize(_ size: Int) {
        if hopSize != size {
            hopSize = size
            updateTimeColumns()
        }
    }
    
    func setTimeSpan(_ span: Int) {
        currentTimeSpanValue = span
        updateTimeColumns()
    }
    
    func setPaused(_ paused: Bool) {
        self.isUpdatesPaused = paused
    }
    
    func setManualScrollOffset(_ offset: Float) {
        self.manualScrollOffset = offset
    }
    
    private func updateTimeColumns() {
        // Update rate = 44100 / hopSize
        // z.B. 44100 / 512 = 86 Hz
        // z.B. 44100 / 2048 = 21.5 Hz
        let updateRate = 44100.0 / Double(hopSize)
        let newColumns: Int
        
        if currentTimeSpanValue == 0 {
            newColumns = 8192 
        } else {
            newColumns = Int(Double(currentTimeSpanValue) * updateRate)
        }
        
        if newColumns != timeColumns {
            timeColumns = max(10, newColumns) // Mindestens 10 Spalten
            setupTexture()
            reset()
        }
    }
}

// ============================================================================
// MARK: - SwiftUI Wrapper
// ============================================================================

struct HighEndSpectrogramAdapterView: UIViewRepresentable {
    @ObservedObject var audioEngine: AudioEngine
    var colormapType: Int
    var timeSpan: SpectrogramTimeSpan
    var scrollSpeed: ScrollSpeed
    var isPaused: Bool
    var scrollOffset: Float
    
    func makeUIView(context: Context) -> HighEndSpectrogramAdapter {
        let view = HighEndSpectrogramAdapter(
            frame: .zero,
            device: MTLCreateSystemDefaultDevice()
        )
        view.setColormap(colormapType)
        view.setTimeSpan(timeSpan.rawValue)
        view.setHopSize(scrollSpeed.rawValue)
        view.setPaused(isPaused)
        view.setManualScrollOffset(scrollOffset)
        context.coordinator.view = view
        return view
    }
    
    func updateUIView(_ uiView: HighEndSpectrogramAdapter, context: Context) {
        uiView.setColormap(colormapType)
        uiView.setHopSize(scrollSpeed.rawValue)
        uiView.setTimeSpan(timeSpan.rawValue)
        uiView.setPaused(isPaused)
        uiView.setManualScrollOffset(scrollOffset)
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
    var colormapType: Int = 0
    var timeSpan: SpectrogramTimeSpan = .seconds5
    var scrollSpeed: ScrollSpeed = .fast
    var isPaused: Bool = false
    var scrollOffset: Float = 0.0
    let axisWidth: CGFloat = 35
    let axisHeight: CGFloat = 20
    let axisSpacing: CGFloat = 4
    
    // Spezifische Frequenzen für die Achsenbeschriftung
    let axisFrequencies: [Double] = [16000, 8000, 4000, 2000, 1000, 500, 250, 125, 63, 31.5]
    
    var body: some View {
        GeometryReader { geometry in
            let graphHeight = geometry.size.height - axisHeight - axisSpacing
            
            HStack(spacing: axisSpacing) {
                // Y-Axis (Frequency)
                VStack(spacing: 0) {
                    ZStack(alignment: .topTrailing) {
                        ForEach(axisFrequencies, id: \.self) { freq in
                            Text(frequencyLabel(freq))
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .frame(width: axisWidth, alignment: .trailing)
                                // Position berechnen: 0 = oben (maxFreq), height = unten (minFreq)
                                .position(x: axisWidth / 2, y: yPosition(for: freq, height: graphHeight))
                                .offset(y: freq == 16000 ? 6 : 0)
                        }
                    }
                    .frame(width: axisWidth, height: graphHeight)
                    .clipped()
                    
                    Spacer().frame(height: axisHeight + axisSpacing)
                }
                
                // Spectrogram View & X-Axis
                VStack(spacing: axisSpacing) {
                    HighEndSpectrogramAdapterView(audioEngine: audioEngine, colormapType: colormapType, timeSpan: timeSpan, scrollSpeed: scrollSpeed, isPaused: isPaused, scrollOffset: scrollOffset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .cornerRadius(20)
                    
                    // X-Axis (Time)
                    HStack {
                        Text("Now")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Spacer()
                        Text(startTimeLabel)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 4)
                    .frame(height: axisHeight)
                }
                
                // Symmetrie-Spacer, damit das Spektrogramm mittig sitzt
                Spacer().frame(width: axisWidth)
            }
        }
    }
    
    private func yPosition(for freq: Double, height: CGFloat) -> CGFloat {
        let minFreq = 20.0
        let maxFreq = 16000.0
        
        // Logarithmische Skalierung
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let logFreq = log10(freq)
        
        // Normalisiert 0..1 (0 = min, 1 = max)
        let normalized = (logFreq - logMin) / (logMax - logMin)
        
        // Screen Y (0 = oben, height = unten)
        return height * (1.0 - CGFloat(normalized))
    }
    
    private var startTimeLabel: String {
        switch timeSpan {
        case .seconds1: return "-1s"
        case .seconds5: return "-5s"
        }
    }
    
    private func frequencyLabel(_ freq: Double) -> String {
        if freq >= 1000 {
            return String(format: "%.0f k", freq / 1000)
        } else if freq.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", freq)
        } else {
            return String(format: "%.1f", freq)
        }
    }
}
