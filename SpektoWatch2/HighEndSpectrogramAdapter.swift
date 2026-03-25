import MetalKit
import Accelerate
import SwiftUI
import Combine
import OSLog

// ============================================================================
// MARK: - Axis Metrics (unchanged public API)
// ============================================================================

struct SpectrogramAxisMetrics {
    var recordingTimeSeconds: Double = 0
    var scrollOffsetNormalized: Float = 0
    var fillRatio: Float = 0
}

// ============================================================================
// MARK: - High-Performance Spectrogram (Metal + vDSP)
// ============================================================================
//
// Key performance improvements over previous implementation:
// 1. No vertex buffer — hardcoded fullscreen quad via vertex_id
// 2. CPU-side dB→[0,1] normalization (vDSP vectorized, ~1024 values)
//    instead of per-pixel GPU computation (~2M pixels at 60fps)
// 3. 1D colormap LUT texture (single texture lookup) instead of
//    polynomial evaluation per pixel
// 4. Minimal fragment shader: just 2 texture samples
// ============================================================================

class HighEndSpectrogramAdapter: MTKView {

    // MARK: - Metal Resources
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!

    // Triple-buffered scroll offset
    private var scrollBuffers: [MTLBuffer] = []
    private let maxInFlightBuffers = 3
    private var currentBufferIndex = 0
    private var inFlightSemaphore = DispatchSemaphore(value: 3)

    // MARK: - Textures
    private var spectrogramTexture: MTLTexture!
    private var colormapTextures: [Int: MTLTexture] = [:]  // cached per colormap type

    // MARK: - Ring Buffer State
    private var currentColumn: Int = 0
    private var totalColumnsWritten: Int = 0
    private var firstDataTimestamp: TimeInterval?
    private var lastDataTimestamp: TimeInterval = 0
    private var lastAxisMetricsPushUptime: TimeInterval = 0
    private var columnAdvanceAccumulator: Double = 0

    // MARK: - Configuration
    private let frequencyBins: Int = 1024
    private var timeColumns: Int = 600
    private var hopSize: Int = 512
    private var currentTimeSpanValue: Int = 5
    private let sampleRate: Float = 44100.0
    private let minFrequency: Float = 20.0
    private let maxFrequency: Float = 16000.0

    // MARK: - Display Parameters
    private var dynamicRange: Float = 80.0
    /// Display floor in dB SPL
    private var displayMinSPL: Float { 110.0 - dynamicRange }
    /// Display ceiling in dB SPL
    private let displayMaxSPL: Float = 110.0
    var colormapType: Int = 0
    var noiseFloor: Float = -90.0   // dBFS
    var kneeWidth: Float = 10.0
    var gamma: Float = 0.8
    var isUpdatesPaused: Bool = false
    var manualScrollOffset: Float = 0.0
    var onAxisMetricsChanged: ((SpectrogramAxisMetrics) -> Void)?

    // MARK: - Noise Gate Parameters (converted to SPL domain)
    private var noiseFloorSPL: Float { noiseFloor + 120.0 }

    // MARK: - Frequency Mapping Cache
    private struct MappingCacheEntry {
        let isInterpolated: Bool
        let index0: Int
        let index1: Int
        let fraction: Float
        let startBin: Int
        let endBin: Int
    }
    private var mappingCache: [MappingCacheEntry]?
    private var cachedInputSize: Int = 0
    private var reusableColumnData: [Float] = []

    deinit {
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

        self.framebufferOnly = true   // We only render to it, no compute writes
        self.enableSetNeedsDisplay = false
        self.isPaused = false
        self.preferredFramesPerSecond = 60
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        self.colorPixelFormat = .bgra8Unorm
        self.sampleCount = 1

        commandQueue = device.makeCommandQueue()
        setupPipeline()
        setupTexture()
        setupScrollBuffers()
        buildColormapTexture(type: colormapType)
    }

    private func setupPipeline() {
        guard let device = device,
              let library = device.makeDefaultLibrary() else {
            fatalError("Could not load Metal library")
        }

        let vertexFunction = library.makeFunction(name: "spectrogramVertex")
        let fragmentFunction = library.makeFunction(name: "liveSpectrogramFragment")

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunction
        desc.fragmentFunction = fragmentFunction
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to create render pipeline state: \(error)")
        }
    }

    private func setupTexture() {
        guard let device = device else { return }

        let desc = MTLTextureDescriptor()
        desc.textureType = .type2D
        desc.pixelFormat = .r32Float
        desc.width = timeColumns
        desc.height = frequencyBins
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared

        spectrogramTexture = device.makeTexture(descriptor: desc)
        clearTexture()
    }

    private func clearTexture() {
        guard let texture = spectrogramTexture else { return }
        let count = texture.width * texture.height
        var data = [Float](repeating: 0, count: count)
        texture.replace(
            region: MTLRegion(origin: MTLOrigin(), size: MTLSize(width: texture.width, height: texture.height, depth: 1)),
            mipmapLevel: 0,
            withBytes: &data,
            bytesPerRow: texture.width * MemoryLayout<Float>.stride
        )
    }

    private func setupScrollBuffers() {
        guard let device = device else { return }
        scrollBuffers.removeAll()
        for _ in 0..<maxInFlightBuffers {
            if let buf = device.makeBuffer(length: MemoryLayout<Float>.stride, options: .storageModeShared) {
                scrollBuffers.append(buf)
            }
        }
    }

    private func buildColormapTexture(type: Int) {
        guard let device = device else { return }
        let cmType = ColormapType(rawValue: type) ?? .turbo
        if colormapTextures[type] == nil {
            colormapTextures[type] = ColormapTexture.makeTexture(device: device, type: cmType)
        }
    }

    // MARK: - Frequency Mapping (precomputed)

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
            let pixelBandwidth = (i < frequencyBins - 1)
                ? (freqNext - frequency)
                : (frequency - exp2(logMinFreq + Float(i - 1) / Float(frequencyBins - 1) * (logMaxFreq - logMinFreq)))

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

    // MARK: - Data Input (CPU-side normalization)

    /// Accepts FFT magnitudes (in dB SPL from AudioEngine) and writes a
    /// pre-normalized [0,1] column into the history texture.
    func updateWithFFTMagnitudes(_ magnitudes: [Float], timestamp: Date) {
        guard spectrogramTexture != nil, !isUpdatesPaused else { return }

        let currentTimestamp = timestamp.timeIntervalSinceReferenceDate
        let previousTimestamp = (lastDataTimestamp > 0) ? lastDataTimestamp : nil
        lastDataTimestamp = currentTimestamp
        if firstDataTimestamp == nil { firstDataTimestamp = currentTimestamp }

        // Rebuild mapping cache if input size changed
        if mappingCache == nil || cachedInputSize != magnitudes.count {
            precomputeMapping(inputSize: magnitudes.count)
        }

        // Ensure reusable buffer
        if reusableColumnData.count != frequencyBins {
            reusableColumnData = [Float](repeating: 0, count: frequencyBins)
        }

        guard let cache = mappingCache else { return }

        let minSPL = displayMinSPL
        let maxSPL = displayMaxSPL
        let range = maxSPL - minSPL
        let nfSPL = noiseFloorSPL
        let kw = kneeWidth
        let gam = gamma

        // Per-bin: map frequencies, get dB SPL, normalize to [0,1]
        for i in 0..<frequencyBins {
            let entry = cache[i]
            var dbValue: Float

            if entry.isInterpolated {
                let v0 = (entry.index0 >= 0 && entry.index0 < magnitudes.count) ? magnitudes[entry.index0] : -120.0
                let v1 = (entry.index1 >= 0 && entry.index1 < magnitudes.count) ? magnitudes[entry.index1] : -120.0
                dbValue = v0 * (1.0 - entry.fraction) + v1 * entry.fraction
            } else {
                var maxVal: Float = -1000.0
                let start = max(0, entry.startBin)
                let end = min(magnitudes.count - 1, entry.endBin)
                if start <= end {
                    for b in start...end {
                        maxVal = max(maxVal, magnitudes[b])
                    }
                }
                dbValue = maxVal > -999.0 ? maxVal : -120.0
            }

            // Noise gate with soft knee (in SPL domain)
            if dbValue < nfSPL {
                dbValue = minSPL
            } else if dbValue < nfSPL + kw {
                let t = (dbValue - nfSPL) / kw
                let factor = t * t * (3.0 - 2.0 * t) // smoothstep
                dbValue = minSPL * (1.0 - factor) + dbValue * factor
            }

            // Normalize to [0, 1]
            var normalized = (dbValue - minSPL) / range
            normalized = max(0, min(1, normalized))

            // Log compression + gamma
            normalized = log10(1.0 + 99.0 * normalized) / log10(100.0)
            normalized = powf(normalized, gam)

            reusableColumnData[i] = normalized
        }

        // Determine how many columns to write based on elapsed time
        let columnsToWrite: Int = {
            guard let prev = previousTimestamp else { return 1 }
            let dt = max(0, currentTimestamp - prev)
            let secondsPerColumn = Double(max(hopSize, 1)) / Double(sampleRate)
            guard secondsPerColumn > 0 else { return 1 }
            columnAdvanceAccumulator += dt / secondsPerColumn
            let advanced = Int(columnAdvanceAccumulator.rounded(.down))
            if advanced > 0 {
                let clamped = min(advanced, max(1, timeColumns))
                columnAdvanceAccumulator -= Double(clamped)
                return clamped
            }
            return 1
        }()

        // Write normalized data to texture columns
        let bytesPerRow = MemoryLayout<Float>.stride
        for _ in 0..<columnsToWrite {
            let region = MTLRegion(
                origin: MTLOrigin(x: currentColumn, y: 0, z: 0),
                size: MTLSize(width: 1, height: frequencyBins, depth: 1)
            )
            spectrogramTexture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: reusableColumnData,
                bytesPerRow: bytesPerRow
            )
            currentColumn = (currentColumn + 1) % timeColumns
        }
        totalColumnsWritten += columnsToWrite
    }

    // MARK: - Rendering

    override func draw(_ rect: CGRect) {
        guard inFlightSemaphore.wait(timeout: .now()) == .success else { return }

        guard let drawable = currentDrawable,
              let rpd = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd)
        else {
            inFlightSemaphore.signal()
            return
        }

        let semaphore = inFlightSemaphore
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }

        // Compute scroll offset
        let lastWrittenColumn = (currentColumn - 1 + timeColumns) % timeColumns
        let baseOffset = Float(lastWrittenColumn) / Float(timeColumns)
        let secondsPerColumn = Double(max(hopSize, 1)) / Double(sampleRate)
        let interpolationOffset: Float
        if secondsPerColumn > 0, lastDataTimestamp > 0 {
            let elapsed = max(0, Date().timeIntervalSinceReferenceDate - lastDataTimestamp)
            interpolationOffset = Float(min(elapsed / secondsPerColumn, 1.0)) / Float(max(timeColumns, 1))
        } else {
            interpolationOffset = 0
        }
        var totalOffset = baseOffset + interpolationOffset + manualScrollOffset
        let fillRatio = min(1.0, Float(totalColumnsWritten) / Float(max(timeColumns, 1)))

        // Push axis metrics at ~30 Hz
        let nowUptime = ProcessInfo.processInfo.systemUptime
        if nowUptime - lastAxisMetricsPushUptime >= (1.0 / 30.0) {
            lastAxisMetricsPushUptime = nowUptime
            let recordingTime: Double
            if let first = firstDataTimestamp {
                recordingTime = max(0, lastDataTimestamp - first)
            } else {
                recordingTime = 0
            }
            let metrics = SpectrogramAxisMetrics(
                recordingTimeSeconds: recordingTime,
                scrollOffsetNormalized: totalOffset,
                fillRatio: fillRatio
            )
            DispatchQueue.main.async { [weak self] in
                self?.onAxisMetricsChanged?(metrics)
            }
        }

        // Write scroll offset to buffer
        let scrollBuffer = scrollBuffers[currentBufferIndex]
        memcpy(scrollBuffer.contents(), &totalOffset, MemoryLayout<Float>.stride)

        // Ensure colormap texture exists
        buildColormapTexture(type: colormapType)
        let cmTexture = colormapTextures[colormapType]

        // Encode render
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(spectrogramTexture, index: 0)
        encoder.setFragmentTexture(cmTexture, index: 1)
        encoder.setFragmentBuffer(scrollBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()

        currentBufferIndex = (currentBufferIndex + 1) % maxInFlightBuffers
    }

    // MARK: - Public API

    func reset() {
        currentColumn = 0
        totalColumnsWritten = 0
        columnAdvanceAccumulator = 0
        firstDataTimestamp = nil
        lastDataTimestamp = 0
        clearTexture()
        DispatchQueue.main.async { [weak self] in
            self?.onAxisMetricsChanged?(SpectrogramAxisMetrics())
        }
    }

    func setColormap(_ type: Int) {
        let clamped = max(0, min(ColormapType.allCases.count - 1, type))
        guard colormapType != clamped else { return }
        colormapType = clamped
        if Thread.isMainThread {
            setNeedsDisplay()
        } else {
            DispatchQueue.main.async { [weak self] in self?.setNeedsDisplay() }
        }
    }

    func setNoiseFloor(_ db: Float) { noiseFloor = db }
    func setKneeWidth(_ width: Float) { kneeWidth = max(0.0, width) }
    func setGamma(_ value: Float) { gamma = max(0.1, min(2.0, value)) }
    func setInterpolation(_ enabled: Bool) { /* no-op: hardware filtering always on */ }
    func setHorizontalBlur(_ blur: Float) { /* no-op: removed for performance */ }

    func setSensitivity(_ value: Float) {
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

    func setPaused(_ paused: Bool) { isUpdatesPaused = paused }
    func setManualScrollOffset(_ offset: Float) { manualScrollOffset = offset }

    private func updateTimeColumns() {
        let updateRate = 44100.0 / Double(hopSize)
        let newColumns: Int
        if currentTimeSpanValue == 0 {
            newColumns = 8192
        } else {
            newColumns = Int(Double(currentTimeSpanValue) * updateRate)
        }
        if newColumns != timeColumns {
            timeColumns = max(10, newColumns)
            setupTexture()
            reset()
        }
    }
}

// ============================================================================
// MARK: - SwiftUI Wrapper
// ============================================================================

struct HighEndSpectrogramAdapterView: UIViewRepresentable {
    var audioEngine: AudioEngine
    var colormapType: Int
    var timeSpan: SpectrogramTimeSpan
    var scrollSpeed: ScrollSpeed
    var isPaused: Bool
    var scrollOffset: Float
    var freqWeighting: String = "Z"
    var sensitivity: Float = 50.0
    var onAxisMetricsChanged: ((SpectrogramAxisMetrics) -> Void)? = nil

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
        context.coordinator.onAxisMetricsChanged = onAxisMetricsChanged
        view.onAxisMetricsChanged = { metrics in
            context.coordinator.onAxisMetricsChanged?(metrics)
        }
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
        context.coordinator.onAxisMetricsChanged = onAxisMetricsChanged
        uiView.onAxisMetricsChanged = { metrics in
            context.coordinator.onAxisMetricsChanged?(metrics)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(audioEngine: audioEngine, freqWeighting: freqWeighting)
    }

    class Coordinator: NSObject {
        var audioEngine: AudioEngine
        weak var view: HighEndSpectrogramAdapter?
        var cancellable: AnyCancellable?
        var freqWeighting: String
        var onAxisMetricsChanged: ((SpectrogramAxisMetrics) -> Void)?

        init(audioEngine: AudioEngine, freqWeighting: String = "Z") {
            self.audioEngine = audioEngine
            self.freqWeighting = freqWeighting
            super.init()

            cancellable = audioEngine.$currentSpectrogramData
                .compactMap { $0 }
                .sink { [weak self] data in
                    guard let self = self else { return }
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
    var audioEngine: AudioEngine
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
        let logMin = log10(20.0)
        let logMax = log10(16000.0)
        let logFreq = log10(freq)
        let normalized = (logFreq - logMin) / (logMax - logMin)
        return height * (1.0 - CGFloat(normalized))
    }

    private func frequencyLabel(_ freq: Double) -> String {
        freq >= 1000 ? String(format: "%.0f k", freq / 1000) : String(format: "%.0f", freq)
    }
}

// ============================================================================
// MARK: - Container with Axis Labels
// ============================================================================

struct HighEndSpectrogramAdapterWithAxes: View {
    var audioEngine: AudioEngine
    var colormapType: Int = 0
    var timeSpan: SpectrogramTimeSpan = .seconds5
    var scrollSpeed: ScrollSpeed = .fast
    var isPaused: Bool = false
    var scrollOffset: Float = 0.0
    var freqWeighting: String = "Z"
    var sensitivity: Float = 50.0
    let axisWidth: CGFloat = 35
    let axisHeight: CGFloat = 28
    let axisSpacing: CGFloat = 4
    @State private var axisMetrics = SpectrogramAxisMetrics()

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
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.black.opacity(0.24))

                        HighEndSpectrogramAdapterView(
                            audioEngine: audioEngine,
                            colormapType: colormapType,
                            timeSpan: timeSpan,
                            scrollSpeed: scrollSpeed,
                            isPaused: isPaused,
                            scrollOffset: scrollOffset,
                            freqWeighting: freqWeighting,
                            sensitivity: sensitivity,
                            onAxisMetricsChanged: { metrics in
                                axisMetrics = metrics
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(4)
                    }
                    .frame(height: spectrogramHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.black.opacity(0.75), lineWidth: 18)
                            .blur(radius: 10)
                            .mask(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.70), Color.white.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )

                    // X-Axis (Time)
                    GeometryReader { axisGeo in
                        Canvas { context, size in
                            let duration = max(axisMetrics.recordingTimeSeconds, 0)
                            let span = Double(timeSpan.rawValue)
                            guard span > 0 else { return }

                            let visibleEnd = duration
                            let visibleStart = max(0, visibleEnd - span)
                            let visibleRange = visibleEnd - visibleStart
                            let filledRatio = min(max(Double(axisMetrics.fillRatio), 0), 1)
                            let axisVisibleWidth = size.width * CGFloat(filledRatio)
                            let baselineY: CGFloat = 3

                            var baseline = Path()
                            baseline.move(to: CGPoint(x: 0, y: baselineY))
                            baseline.addLine(to: CGPoint(x: axisVisibleWidth, y: baselineY))
                            context.stroke(baseline, with: .color(Color.gray.opacity(0.7)), lineWidth: 0.8)

                            let tickStep = xAxisTickStep(for: visibleRange)
                            if tickStep <= 0 { return }

                            let firstTick = ceil(visibleStart / tickStep) * tickStep
                            let lastTick = visibleEnd + (tickStep * 0.5)
                            var lastLabelX: CGFloat = -.greatestFiniteMagnitude

                            for tick in stride(from: firstTick, through: lastTick, by: tickStep) {
                                let x = CGFloat((visibleEnd - tick) / span) * size.width
                                guard x >= 0 && x <= axisVisibleWidth else { continue }

                                var tickPath = Path()
                                tickPath.move(to: CGPoint(x: x, y: baselineY))
                                tickPath.addLine(to: CGPoint(x: x, y: baselineY + 5))
                                context.stroke(tickPath, with: .color(Color.gray.opacity(0.75)), lineWidth: 0.9)

                                if abs(x - lastLabelX) > 22 {
                                    context.draw(
                                        Text(formatAxisTime(tick))
                                            .font(.caption2)
                                            .foregroundColor(.gray),
                                        at: CGPoint(x: x, y: baselineY + 13),
                                        anchor: .center
                                    )
                                    lastLabelX = x
                                }
                            }
                        }
                    }
                    .frame(height: axisHeight)
                }
            }
        }
    }

    private func yPosition(for freq: Double, height: CGFloat) -> CGFloat {
        let logMin = log10(20.0)
        let logMax = log10(16000.0)
        let logFreq = log10(freq)
        let normalized = (logFreq - logMin) / (logMax - logMin)
        return height * (1.0 - CGFloat(normalized))
    }

    private func xAxisTickStep(for visibleRange: Double) -> Double {
        guard visibleRange > 0 else { return 0.1 }
        let rough = visibleRange / 4.0
        let candidates: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60]
        for c in candidates where rough <= c { return c }
        return 60
    }

    private func formatAxisTime(_ seconds: Double) -> String {
        if seconds < 10 { return String(format: "%.1f", seconds) }
        if seconds < 60 { return String(format: "%.0f", seconds) }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
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
