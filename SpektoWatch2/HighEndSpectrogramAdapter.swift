import MetalKit
import Accelerate
import SwiftUI
import Combine
import OSLog

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
    
    // Buffer Pool für Performance
    private var paramsBuffers: [MTLBuffer] = []
    private let maxInFlightBuffers = 3
    private var currentBufferIndex = 0
    private var inFlightSemaphore = DispatchSemaphore(value: 3)
    
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
    private var dynamicRange: Float = 50.0  // Dynamikbereich in dB (einstellbar)
    private var minDB: Float { -dynamicRange - 10.0 }  // z.B. -60 dBFS bei 50 dB Range
    private var maxDB: Float { -10.0 }                  // Obere Grenze fest bei -10 dBFS
    
    // MARK: - Display Parameters (KORRIGIERT)
    var colormapType: Int = 0
    var noiseFloor: Float = -90.0  // dBFS Skala (Shader erwartet dBFS)

    // MARK: - Calibration
    // AudioEngine liefert dB SPL, Shader erwartet dBFS
    // Offset zum Zurückrechnen: dBFS = dB SPL - 120
    private let splToDbfsOffset: Float = 120.0
    var kneeWidth: Float = 10.0    // KORRIGIERT: Moderate Knee Width
    var gamma: Float = 0.8         // KORRIGIERT: Etwas höherer Gamma für mehr Details in den Mitten
    var useInterpolation: Bool = true
    var horizontalBlur: Float = 0.0 // Horizontaler Weichzeichner (0.0 = aus, 1.0 = leicht, 2.0+ = stark)
    var isUpdatesPaused: Bool = false
    var manualScrollOffset: Float = 0.0
    private var debugPrintCounter = 0
    private var drawPrintCounter = 0
    private var lastDataTimestamp: TimeInterval = 0
    private let enableVerboseLogs = false
    
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
    private var reusableColumnData: [Float] = []

    deinit {
        // Stop rendering callbacks before teardown.
        isPaused = true
    }

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
        // Render on demand instead of continuous 120 FPS redraw.
        self.enableSetNeedsDisplay = true
        self.isPaused = true
        self.preferredFramesPerSecond = 60
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        self.sampleCount = 1 // MSAA deaktiviert für Performance, wir nutzen Texture-Filterung
        
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
        pipelineDescriptor.rasterSampleCount = 1 // Pipeline muss zum View passen (1x MSAA)
        
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
        
        // Pre-allocate Buffer Pool
        paramsBuffers.removeAll()
        for _ in 0..<maxInFlightBuffers {
            if let buffer = device.makeBuffer(
                length: MemoryLayout<HighEndSpectrogramShaderParams>.stride,
                options: .storageModeShared
            ) {
                paramsBuffers.append(buffer)
            }
        }
    }
    
    // MARK: - Public API (KORRIGIERT)
    
    /// KORREKTUR: Akzeptiere FFT Magnituden direkt als lineare Werte
    /// AudioEngine sollte lineare Magnituden liefern, nicht dB
    /// Akzeptiere FFT Magnituden und mappe sie logarithmisch auf die Textur
func updateWithFFTMagnitudes(_ magnitudes: [Float], timestamp: Date) {
    guard let texture = spectrogramTexture else { return }
    
    if isUpdatesPaused { return }
    lastDataTimestamp = timestamp.timeIntervalSinceReferenceDate
    
    // DEBUG: Log input data for display
    debugPrintCounter += 1
    if enableVerboseLogs && debugPrintCounter % 240 == 0 {
        let minVal = magnitudes.min() ?? 0
        let maxVal = magnitudes.max() ?? 0
        Logger.metal.debug("Frame \(self.debugPrintCounter): \(magnitudes.count) bins, Range: [\(minVal, format: .fixed(precision: 5))..\(maxVal, format: .fixed(precision: 5))]")
    }
    
    // Cache aktualisieren falls nötig
    if mappingCache == nil || cachedInputSize != magnitudes.count {
        precomputeMapping(inputSize: magnitudes.count)
    }
    
    // KORREKTUR: Logarithmisches Mapping beim SCHREIBEN in die Textur
    if reusableColumnData.count != frequencyBins {
        reusableColumnData = [Float](repeating: 1e-10, count: frequencyBins)
    } else {
        reusableColumnData.withUnsafeMutableBufferPointer { buffer in
            buffer.update(repeating: 1e-10)
        }
    }
    
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
        
        // AudioEngine liefert bereits kalibrierte dB SPL Werte (z.B. 60-100 dB SPL)
        // Der Shader erwartet lineare Magnituden und macht 20*log10(mag)
        // mit minDB=-90, maxDB=-10 (dBFS Skala)
        //
        // Wir müssen dB SPL zurück zu dBFS konvertieren:
        // dBFS = dB SPL - splToDbfsOffset (120 dB)
        let dbFS = dbValue - splToDbfsOffset  // z.B. 80 dB SPL -> -40 dBFS

        // Konvertiere dBFS zu linearer Magnitude für den Shader
        reusableColumnData[i] = pow(10.0, dbFS / 20.0)
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
        withBytes: reusableColumnData,
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
        // Never block UI thread waiting for GPU; skip frame if pipeline is full.
        guard inFlightSemaphore.wait(timeout: .now()) == .success else { return }
        
        guard let drawable = currentDrawable,
              let renderPassDescriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else {
            inFlightSemaphore.signal()
            return
        }
        
        // Signal Semaphore wenn GPU fertig ist
        // Capture semaphore strongly so signal() still happens even if self is deallocated.
        let semaphore = inFlightSemaphore
        commandBuffer.addCompletedHandler { _ in
            semaphore.signal()
        }
        
        let lastWrittenColumn = (currentColumn - 1 + timeColumns) % timeColumns
        let baseOffset = Float(lastWrittenColumn) / Float(timeColumns)
        let totalOffset = baseOffset + manualScrollOffset
        
        drawPrintCounter += 1
        if drawPrintCounter % 120 == 0 {
            let now = Date().timeIntervalSinceReferenceDate
            let latencyMs = lastDataTimestamp > 0 ? (now - lastDataTimestamp) * 1000.0 : -1
            Logger.metal.debug("Render Frame \(self.drawPrintCounter): Column \(self.currentColumn)/\(self.timeColumns), Scroll: \(totalOffset, format: .fixed(precision: 3)), Colormap: \(self.colormapType), Render Lag: \(latencyMs, format: .fixed(precision: 0)) ms")
        }
        
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
        
        // Update Buffer im Pool statt neu zu allokieren
        let currentBuffer = paramsBuffers[currentBufferIndex]
        memcpy(currentBuffer.contents(), &params, MemoryLayout<HighEndSpectrogramShaderParams>.stride)
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(spectrogramTexture, index: 0)
        renderEncoder.setFragmentBuffer(currentBuffer, offset: 0, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        // Nächster Buffer für nächsten Frame
        currentBufferIndex = (currentBufferIndex + 1) % maxInFlightBuffers
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

    func setSensitivity(_ value: Float) {
        // Dynamikbereich: 30-80 dB
        dynamicRange = max(30.0, min(80.0, value))
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
    var freqWeighting: String = "Z"
    var sensitivity: Float = 50.0

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
        view.setSensitivity(sensitivity)
        context.coordinator.view = view
        context.coordinator.freqWeighting = freqWeighting
        return view
    }

    func updateUIView(_ uiView: HighEndSpectrogramAdapter, context: Context) {
        uiView.setColormap(colormapType)
        uiView.setHopSize(scrollSpeed.rawValue)
        uiView.setTimeSpan(timeSpan.rawValue)
        uiView.setPaused(isPaused)
        uiView.setManualScrollOffset(scrollOffset)
        uiView.setSensitivity(sensitivity)
        context.coordinator.freqWeighting = freqWeighting
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(audioEngine: audioEngine, freqWeighting: freqWeighting)
    }

    class Coordinator: NSObject {
        var audioEngine: AudioEngine
        weak var view: HighEndSpectrogramAdapter?
        var cancellable: AnyCancellable?
        var freqWeighting: String

        init(audioEngine: AudioEngine, freqWeighting: String = "Z") {
            self.audioEngine = audioEngine
            self.freqWeighting = freqWeighting
            super.init()

            cancellable = audioEngine.$currentSpectrogramData
                .compactMap { $0 }
                .sink { [weak self] data in
                    guard let self = self else { return }
                    // Wähle Magnituden basierend auf der Bewertungskurve
                    let magnitudes = data.magnitudes(for: self.freqWeighting)
                    self.view?.updateWithFFTMagnitudes(magnitudes, timestamp: data.timestamp)
                }
        }
    }
}

// ============================================================================
// MARK: - Reusable Components (Widgets)
// ============================================================================

struct SpectrogramWidgetView: View {
    @ObservedObject var audioEngine: AudioEngine
    var colormapType: Int
    var timeSpan: SpectrogramTimeSpan
    var scrollSpeed: ScrollSpeed
    var isPaused: Bool
    var scrollOffset: Float
    var freqWeighting: String = "Z"
    var sensitivity: Float = 50.0

    let axisFrequencies: [Double] = [16000, 8000, 4000, 2000, 1000, 500, 250, 125, 63, 31.5]
    let axisWidth: CGFloat = 35

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 4) {
                // Y-Axis
                ZStack(alignment: .topTrailing) {
                    ForEach(axisFrequencies, id: \.self) { freq in
                        Text(frequencyLabel(freq))
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .frame(width: axisWidth, alignment: .trailing)
                            .position(x: axisWidth / 2, y: yPosition(for: freq, height: geometry.size.height))
                            .offset(y: freq == 16000 ? 6 : 0)
                    }
                }
                .frame(width: axisWidth, height: geometry.size.height)
                .clipped()

                HighEndSpectrogramAdapterView(audioEngine: audioEngine, colormapType: colormapType, timeSpan: timeSpan, scrollSpeed: scrollSpeed, isPaused: isPaused, scrollOffset: scrollOffset, freqWeighting: freqWeighting, sensitivity: sensitivity)
                    .cornerRadius(10)
            }
        }
    }
    
    private func yPosition(for freq: Double, height: CGFloat) -> CGFloat {
        let minFreq = 20.0
        let maxFreq = 16000.0
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let logFreq = log10(freq)
        let normalized = (logFreq - logMin) / (logMax - logMin)
        return height * (1.0 - CGFloat(normalized))
    }
    
    private func frequencyLabel(_ freq: Double) -> String {
        if freq >= 1000 {
            return String(format: "%.0f k", freq / 1000)
        } else {
            return String(format: "%.0f", freq)
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
    var freqWeighting: String = "Z"
    var sensitivity: Float = 50.0  // Dynamikbereich in dB
    let axisWidth: CGFloat = 35
    let axisHeight: CGFloat = 20
    let axisSpacing: CGFloat = 4

    // Spezifische Frequenzen für die Achsenbeschriftung
    let axisFrequencies: [Double] = [16000, 8000, 4000, 2000, 1000, 500, 250, 125, 63, 31.5]

    var body: some View {
        GeometryReader { geometry in
            let totalSpacing = axisSpacing
            let spectrogramHeight = geometry.size.height - axisHeight - totalSpacing

            HStack(spacing: axisSpacing) {
                // Y-Axis (Frequency)
                VStack(spacing: axisSpacing) {
                    ZStack(alignment: .topTrailing) {
                        ForEach(axisFrequencies, id: \.self) { freq in
                            Text(frequencyLabel(freq))
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .frame(width: axisWidth, alignment: .trailing)
                                // Position berechnen: 0 = oben (maxFreq), height = unten (minFreq)
                                .position(x: axisWidth / 2, y: yPosition(for: freq, height: spectrogramHeight))
                                .offset(y: freq == 16000 ? 6 : 0)
                        }
                    }
                    .frame(width: axisWidth, height: spectrogramHeight)
                    .clipped()

                    Spacer().frame(height: axisHeight)
                }

                // Spectrogram View & X-Axis
                VStack(spacing: axisSpacing) {
                    // Spectrogram
                    HighEndSpectrogramAdapterView(
                        audioEngine: audioEngine,
                        colormapType: colormapType,
                        timeSpan: timeSpan,
                        scrollSpeed: scrollSpeed,
                        isPaused: isPaused,
                        scrollOffset: scrollOffset,
                        freqWeighting: freqWeighting,
                        sensitivity: sensitivity
                    )
                    .frame(height: spectrogramHeight)
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
