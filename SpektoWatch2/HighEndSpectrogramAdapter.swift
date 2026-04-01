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
    private var isMetalReady = false
    private var metalFailureReason: String?

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

    // MARK: - Smooth Display Scroll
    private var displayScrollPosition: Double = 0   // in columns, monotonically increasing
    private var lastCADrawTime: Double = 0
    private var displayScrollSynced: Bool = false

    // MARK: - Configuration
    private let frequencyBins: Int = 1024
    private var timeColumns: Int = 600
    private var hopSize: Int = 512
    private var currentTimeSpanValue: Int = 5
    private var currentSampleRate: Float = 44100.0
    private let minFrequency: Float = 20.0
    private let maxFrequency: Float = 20000.0

    // MARK: - Display Parameters
    private var dynamicRange: Float = 90.0
    /// Fester Spektrogramm-Deckel in dBFS.
    private let displayMaxDBFS: Float = -20.0
    /// Fester Spektrogramm-Boden in dBFS (über Dynamikbereich steuerbar).
    private var displayMinDBFS: Float { displayMaxDBFS - dynamicRange }
    /// dB SPL -> dBFS Umrechnung mit Runtime-Kalibrierung.
    private var calibrationOffset: Float = 94.0
    var colormapType: Int = 0
    var noiseFloor: Float = -120.0   // dBFS (standardmäßig effektiv aus)
    var kneeWidth: Float = 0.0
    var gamma: Float = 1.15
    private var frequencySmoothing: Float = 0.0
    var isUpdatesPaused: Bool = false
    var manualScrollOffset: Float = 0.0
    var onAxisMetricsChanged: ((SpectrogramAxisMetrics) -> Void)?

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
    private var reusableSmoothedColumnData: [Float] = []
    private var previousColumnData: [Float] = []
    private var reusableInterpolatedColumnData: [Float] = []

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
            markMetalUnavailable("Metal is not supported on this device")
            return
        }

        self.framebufferOnly = true   // We only render to it, no compute writes
        self.enableSetNeedsDisplay = false
        self.isPaused = false
        self.preferredFramesPerSecond = 120
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        self.colorPixelFormat = .bgra8Unorm
        self.sampleCount = 1

        guard let queue = device.makeCommandQueue() else {
            markMetalUnavailable("Failed to create Metal command queue")
            return
        }
        commandQueue = queue
        setupPipeline()
        guard isMetalReady else { return }
        setupTexture()
        setupScrollBuffers()
        buildColormapTexture(type: colormapType)
    }

    private func setupPipeline() {
        guard let device = device,
              let library = device.makeDefaultLibrary() else {
            markMetalUnavailable("Could not load Metal library")
            return
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
            markMetalUnavailable("Failed to create render pipeline state: \(error)")
            return
        }
        isMetalReady = true
    }

    private func setupTexture() {
        guard isMetalReady, let device = device else { return }

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
        guard isMetalReady, let device = device else { return }
        scrollBuffers.removeAll()
        for _ in 0..<maxInFlightBuffers {
            if let buf = device.makeBuffer(length: MemoryLayout<Float>.stride, options: .storageModeShared) {
                scrollBuffers.append(buf)
            }
        }
    }

    private func buildColormapTexture(type: Int) {
        guard isMetalReady, let device = device else { return }
        let cmType = ColormapType(rawValue: type) ?? .turbo
        if colormapTextures[type] == nil {
            colormapTextures[type] = ColormapTexture.makeTexture(device: device, type: cmType)
        }
    }

    // MARK: - Frequency Mapping (precomputed)

    private func precomputeMapping(inputSize: Int) {
        var newCache = [MappingCacheEntry]()
        newCache.reserveCapacity(frequencyBins)

        let nyquist = currentSampleRate / 2.0
        let logMin = log10(minFrequency)
        let logMax = log10(maxFrequency)
        let logSpan = max(logMax - logMin, 0.0001)
        let magCount = Float(max(1, inputSize - 1))

        for i in 0..<frequencyBins {
            let t = Float(i) / Float(frequencyBins - 1)
            // Log-frequency mapping: gleiche musikalische Intervalle
            // bleiben über die gesamte Höhe visuell konsistent.
            let frequency = pow(10.0, logMin + t * logSpan)

            let tNext = Float(i + 1) / Float(frequencyBins - 1)
            let freqNext = pow(10.0, logMin + tNext * logSpan)
            let pixelBandwidth = (i < frequencyBins - 1)
                ? (freqNext - frequency)
                : (frequency - pow(10.0, logMin + Float(i - 1) / Float(frequencyBins - 1) * logSpan))

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
    func updateWithFFTMagnitudes(_ magnitudes: [Float], sampleRate: Double, timestamp: Date) {
        guard isMetalReady, spectrogramTexture != nil, !isUpdatesPaused else { return }
        updateSampleRateIfNeeded(sampleRate)

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
        if reusableSmoothedColumnData.count != frequencyBins {
            reusableSmoothedColumnData = [Float](repeating: 0, count: frequencyBins)
        }
        if previousColumnData.count != frequencyBins {
            previousColumnData = [Float](repeating: 0, count: frequencyBins)
        }
        if reusableInterpolatedColumnData.count != frequencyBins {
            reusableInterpolatedColumnData = [Float](repeating: 0, count: frequencyBins)
        }

        guard let cache = mappingCache else { return }

        let minDBFS = displayMinDBFS
        let maxDBFS = displayMaxDBFS
        let range = maxDBFS - minDBFS
        let floorDBFS = max(noiseFloor, minDBFS)
        let kw = kneeWidth
        let gam = gamma

        // Per-bin: map frequencies, convert to dBFS, normalize to [0,1]
        for i in 0..<frequencyBins {
            let entry = cache[i]
            var dbValue: Float

            if entry.isInterpolated {
                let v0 = (entry.index0 >= 0 && entry.index0 < magnitudes.count) ? magnitudes[entry.index0] : -120.0
                let v1 = (entry.index1 >= 0 && entry.index1 < magnitudes.count) ? magnitudes[entry.index1] : -120.0
                // Leichte Peak-Betonung, aber deutlich weniger aggressiv als vorher.
                let linear = v0 * (1.0 - entry.fraction) + v1 * entry.fraction
                let peak = max(v0, v1)
                dbValue = linear + (peak - linear) * 0.2
            } else {
                let start = max(0, entry.startBin)
                let end = min(magnitudes.count - 1, entry.endBin)
                if start <= end {
                    var peakDb: Float = -1000.0
                    var sumLinear: Float = 0.0
                    var count: Int = 0
                    for b in start...end {
                        let db = magnitudes[b]
                        peakDb = max(peakDb, db)
                        sumLinear += pow(10.0, db / 10.0)
                        count += 1
                    }
                    let meanLinear = sumLinear / Float(max(count, 1))
                    let meanDb = 10.0 * log10(max(meanLinear, 1e-12))
                    dbValue = meanDb + (peakDb - meanDb) * 0.25
                } else {
                    dbValue = -120.0
                }
            }

            // Darstellung auf fixer dBFS-Skala, unabhängig von Frame-Peaks.
            var dbfsValue = dbValue - calibrationOffset

            if kw > 0, dbfsValue < floorDBFS + kw {
                if dbfsValue <= floorDBFS {
                    dbfsValue = minDBFS
                } else {
                    let t = (dbfsValue - floorDBFS) / kw
                    let factor = t * t * (3.0 - 2.0 * t)
                    dbfsValue = minDBFS * (1.0 - factor) + dbfsValue * factor
                }
            }

            // Normalize to [0, 1]
            var normalized = (dbfsValue - minDBFS) / range
            normalized = max(0, min(1, normalized))

            // Nur Gamma-Korrektur, keine zusätzliche per-frame Kontrastpumpung.
            normalized = powf(normalized, gam)

            reusableColumnData[i] = normalized
        }

        applyFrequencySmoothingIfNeeded(values: &reusableColumnData)

        // Determine how many columns to write based on elapsed time.
        // Uses effectiveSecondsPerColumn (timeSpan / timeColumns) so the
        // accumulator stays in sync with the actual texture resolution.
        let columnsToWrite: Int = {
            guard let prev = previousTimestamp else { return 1 }
            let dt = max(0, currentTimestamp - prev)
            let spc = effectiveSecondsPerColumn
            guard spc > 0 else { return 1 }
            columnAdvanceAccumulator += dt / spc
            let advanced = Int(columnAdvanceAccumulator.rounded(.down))
            if advanced > 0 {
                let clamped = min(advanced, max(1, timeColumns))
                columnAdvanceAccumulator -= Double(clamped)
                return clamped
            }
            return 1
        }()

        // Bei UI-/Scheduler-Drops nicht identische Spalten kopieren, sondern
        // Zwischenwerte schreiben. Das verhindert breite vertikale Blöcke.
        if columnsToWrite > 1, previousColumnData.count == reusableColumnData.count {
            for step in 1...columnsToWrite {
                let mixFactor = Float(step) / Float(columnsToWrite)
                for i in 0..<reusableColumnData.count {
                    reusableInterpolatedColumnData[i] =
                        previousColumnData[i] * (1.0 - mixFactor) + reusableColumnData[i] * mixFactor
                }
                writeColumn(reusableInterpolatedColumnData)
            }
        } else {
            writeColumn(reusableColumnData)
        }
        previousColumnData = reusableColumnData
        totalColumnsWritten += columnsToWrite
    }

    private func applyFrequencySmoothingIfNeeded(values: inout [Float]) {
        let strength = max(0.0, min(1.0, frequencySmoothing))
        guard strength > 0.001, values.count > 2 else { return }

        // Slider 0...1 bleibt erhalten, Effekt ist bewusst gedämpft,
        // damit feine Harmonische nicht verschmiert werden.
        let effectiveStrength = min(0.38, powf(strength, 1.4) * 0.45)
        let passCount = strength > 0.92 ? 2 : 1
        for _ in 0..<passCount {
            reusableSmoothedColumnData[0] = values[0]
            reusableSmoothedColumnData[values.count - 1] = values[values.count - 1]
            for i in 1..<(values.count - 1) {
                // 3-tap gaussian smoothing kernel in frequency direction
                reusableSmoothedColumnData[i] = values[i - 1] * 0.25 + values[i] * 0.5 + values[i + 1] * 0.25
            }

            for i in 0..<values.count {
                values[i] = values[i] * (1.0 - effectiveStrength) + reusableSmoothedColumnData[i] * effectiveStrength
            }
        }
    }

    private func writeColumn(_ columnData: [Float]) {
        let region = MTLRegion(
            origin: MTLOrigin(x: currentColumn, y: 0, z: 0),
            size: MTLSize(width: 1, height: frequencyBins, depth: 1)
        )
        spectrogramTexture.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: columnData,
            bytesPerRow: MemoryLayout<Float>.stride
        )
        currentColumn = (currentColumn + 1) % timeColumns
    }

    // MARK: - Rendering

    override func draw(_ rect: CGRect) {
        guard isMetalReady,
              pipelineState != nil,
              commandQueue != nil,
              spectrogramTexture != nil,
              !scrollBuffers.isEmpty
        else { return }
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

        // Smooth display scroll: advance at a constant rate tied to CACurrentMediaTime()
        // rather than data timestamps. This eliminates the micro-jumps that occur when
        // the integer columnsToWrite doesn't match the expected fractional advance.
        let lastWrittenColumn = (currentColumn - 1 + timeColumns) % timeColumns
        let now = CACurrentMediaTime()
        let frameDt = lastCADrawTime > 0 ? min(now - lastCADrawTime, 0.05) : 0
        lastCADrawTime = now

        if !displayScrollSynced && totalColumnsWritten > 0 {
            displayScrollPosition = Double(lastWrittenColumn)
            displayScrollSynced = true
        } else if frameDt > 0 && currentTimeSpanValue > 0 && totalColumnsWritten > 0 {
            let columnsPerSec = Double(timeColumns) / Double(currentTimeSpanValue)
            displayScrollPosition += frameDt * columnsPerSec

            // Re-sync if display has drifted more than 5 columns from the data write head.
            // This corrects for pauses, app-backgrounding, or sample-rate changes.
            let displayMod = displayScrollPosition.truncatingRemainder(dividingBy: Double(timeColumns))
            let dataPos = Double(lastWrittenColumn)
            var diff = displayMod - dataPos
            while diff >  Double(timeColumns) / 2 { diff -= Double(timeColumns) }
            while diff < -Double(timeColumns) / 2 { diff += Double(timeColumns) }
            if abs(diff) > 5.0 { displayScrollPosition -= diff }
        }

        var totalOffset = Float(displayScrollPosition.truncatingRemainder(dividingBy: Double(timeColumns))) / Float(timeColumns) + manualScrollOffset
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
        previousColumnData = [Float](repeating: 0, count: frequencyBins)
        displayScrollSynced = false
        if isMetalReady {
            clearTexture()
        }
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
    func setCalibrationOffset(_ value: Float) { calibrationOffset = value }
    func setInterpolation(_ enabled: Bool) { /* no-op: hardware filtering always on */ }
    func setHorizontalBlur(_ blur: Float) { /* no-op: removed for performance */ }

    func setSensitivity(_ value: Float) {
        dynamicRange = max(60.0, min(120.0, value))
    }

    func setFrequencySmoothing(_ value: Float) {
        frequencySmoothing = max(0.0, min(1.0, value))
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

    private func updateSampleRateIfNeeded(_ sampleRate: Double) {
        guard sampleRate > 1000 else { return }
        let normalized = Float((sampleRate * 10.0).rounded() / 10.0)
        guard abs(normalized - currentSampleRate) > 0.5 else { return }

        currentSampleRate = normalized
        mappingCache = nil
        cachedInputSize = 0
        columnAdvanceAccumulator = 0
        updateTimeColumns()
    }

    /// Seconds per texture column, derived from timeSpan / timeColumns.
    /// Used for the column-advance accumulator and draw-time scroll interpolation.
    private var effectiveSecondsPerColumn: Double {
        if currentTimeSpanValue > 0 {
            return Double(currentTimeSpanValue) / Double(max(timeColumns, 1))
        }
        // Continuous mode: fall back to audio hop rate
        return Double(max(hopSize, 1)) / Double(currentSampleRate)
    }

    private func updateTimeColumns() {
        let updateRate = Double(currentSampleRate) / Double(max(hopSize, 1))
        let newColumns: Int
        if currentTimeSpanValue == 0 {
            newColumns = 8192
        } else {
            // Ensure enough columns for sub-pixel resolution on modern displays.
            // Minimum 1200 prevents visible column banding on retina screens.
            let audioColumns = Int(Double(currentTimeSpanValue) * updateRate)
            newColumns = max(1200, audioColumns)
        }
        if newColumns != timeColumns {
            timeColumns = max(10, newColumns)
            // Pause the display link so no draw() fires while the texture is replaced.
            guard isMetalReady else { return }
            isPaused = true
            setupTexture()
            reset()
            isPaused = false
        }
    }

    private func markMetalUnavailable(_ reason: String) {
        isMetalReady = false
        metalFailureReason = reason
        isPaused = true
        enableSetNeedsDisplay = false
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
    var sensitivity: Float = 90.0
    var frequencySmoothing: Float = 0.0
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
        view.setFrequencySmoothing(frequencySmoothing)
        view.setCalibrationOffset(audioEngine.calibrationOffset)
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
        uiView.setFrequencySmoothing(frequencySmoothing)
        uiView.setCalibrationOffset(audioEngine.calibrationOffset)
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
                    self.view?.updateWithFFTMagnitudes(
                        magnitudes,
                        sampleRate: data.sampleRate,
                        timestamp: data.timestamp
                    )
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
    var sensitivity: Float = 90.0
    var frequencySmoothing: Float = 0.0

    let axisFrequencies: [Double] = [20000, 16000, 8000, 4000, 2000, 1000, 500, 250, 125, 63, 31.5]
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
                            .offset(y: freq == 20000 ? 6 : 0)
                    }
                }
                .frame(width: axisWidth, height: geometry.size.height)
                .clipped()

                HighEndSpectrogramAdapterView(audioEngine: audioEngine, colormapType: colormapType, timeSpan: timeSpan, scrollSpeed: scrollSpeed, isPaused: isPaused, scrollOffset: scrollOffset, freqWeighting: freqWeighting, sensitivity: sensitivity, frequencySmoothing: frequencySmoothing)
                    .cornerRadius(10)
            }
        }
    }

    private func yPosition(for freq: Double, height: CGFloat) -> CGFloat {
        let minF = 20.0
        let maxF = 20000.0
        let clamped = max(minF, min(maxF, freq))
        let normalized = (log10(clamped) - log10(minF)) / (log10(maxF) - log10(minF))
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
    var sensitivity: Float = 90.0
    var frequencySmoothing: Float = 0.0
    let axisWidth: CGFloat = 35
    let axisHeight: CGFloat = 28
    let axisSpacing: CGFloat = 4
    @State private var axisMetrics = SpectrogramAxisMetrics()

    let axisFrequencies: [Double] = [20000, 16000, 8000, 4000, 2000, 1000, 500, 250, 125, 63, 31.5]

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
                                .offset(y: freq == 20000 ? 6 : 0)
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
                            frequencySmoothing: frequencySmoothing,
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
        let minF = 20.0
        let maxF = 20000.0
        let clamped = max(minF, min(maxF, freq))
        let normalized = (log10(clamped) - log10(minF)) / (log10(maxF) - log10(minF))
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
