import MetalKit
import Accelerate
import SwiftUI
import Combine
import OSLog
import os

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
    // 2 statt 3: Metal-Pool hat 3 Drawables, wir reservieren einen frei →
    // verhindert dass nextDrawable() den Main Thread blockiert (Thread 0 im Crash).
    private var inFlightSemaphore = DispatchSemaphore(value: 2)

    // MARK: - Textures
    private var spectrogramTexture: MTLTexture!
    private var colormapTextures: [Int: MTLTexture] = [:]  // cached per colormap type

    // MARK: - Ring Buffer State
    //
    // These fields are mutated by `updateWithFFTMagnitudes` on a private
    // background `updateQueue` (subscribed to `audioEngine.spectrogramSubject`
    // in the Coordinator below) AND read by `draw(_:)` on the main thread.
    // `stateLock` serialises the scalar reads/writes; without it, even aligned
    // `Int` access can produce torn reads under contention, and `Bool`/`Double`
    // values are unsafe across threads. Texture writes are dispatched to the
    // main thread so they are serialised with draw(_:)'s GPU encoder submit —
    // no CPU/GPU texture race.
    private let stateLock = OSAllocatedUnfairLock()
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
    /// Noise-floor in dB SPL. −120 = off. Converted to dBFS at render time via
    /// calibrationOffset so the floor tracks calibration changes automatically.
    var noiseFloor: Float = -120.0
    var kneeWidth: Float = 0.0
    var gamma: Float = 1.15
    private var frequencySmoothing: Float = 0.0
    var isUpdatesPaused: Bool = false
    // `manualScrollOffset` removed 2026-05-21 (M9 task-1 audit): zero callers
    // ever set a non-zero value, so the storage + accessor + draw-time add
    // were all unreachable.
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
    /// Hash of the most-recent input frequency labels so the mapping cache is
    /// rebuilt when a producer switches between linear DCT bins, mel band
    /// centers, or another spacing. Apple's "Visualizing Sound as an Audio
    /// Spectrogram" sample produces mel-spaced bins; we honour that spacing
    /// instead of forcing linear-from-Nyquist remapping on top.
    private var cachedInputFrequenciesHash: UInt64 = 0
    private var cachedInputFrequencies: [Float]?
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
        self.preferredFramesPerSecond = 60
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        self.colorPixelFormat = .bgra8Unorm
        self.sampleCount = 1
        // Guarantee a 3-drawable pool so nextDrawable() is always non-blocking
        // when the semaphore (value=2) limits concurrent in-flight frames to 2.
        // Without this, iOS may provision only 2 drawables and the semaphore
        // cannot prevent the main-thread stall seen in the M19 trace.
        if let metalLayer = self.layer as? CAMetalLayer {
            metalLayer.maximumDrawableCount = 3
        }

        guard let queue = device.makeCommandQueue() else {
            markMetalUnavailable("Failed to create Metal command queue")
            return
        }
        commandQueue = queue
        setupPipeline()
        guard isMetalReady else {
            print("[HighEndSpectrogramAdapter] ❌ Setup failed - Metal not ready")
            return
        }
        print("[HighEndSpectrogramAdapter] ✅ Metal initialized successfully")
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
        let w = texture.width
        let h = texture.height
        // Row-by-row clear avoids a single large allocation (e.g. 16000×1024×4 B
        // ≈ 62 MB) that triggers a Metal runtime assertion.
        let rowData = [Float](repeating: 0, count: w)
        let bytesPerRow = w * MemoryLayout<Float>.stride
        for row in 0..<h {
            texture.replace(
                region: MTLRegion(origin: MTLOrigin(x: 0, y: row, z: 0),
                                  size: MTLSize(width: w, height: 1, depth: 1)),
                mipmapLevel: 0,
                withBytes: rowData,
                bytesPerRow: bytesPerRow
            )
        }
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

    private func precomputeMapping(inputSize: Int, inputFrequencies: [Float]? = nil) {
        var newCache = [MappingCacheEntry]()
        newCache.reserveCapacity(frequencyBins)

        let logMin = log10(minFrequency)
        let logMax = log10(maxFrequency)
        let logSpan = max(logMax - logMin, 0.0001)

        // Use producer-supplied frequencies (mel-spaced from
        // VisualSpectrogramProcessor, or any monotonically increasing
        // axis) when available. Falling back to linear-from-Nyquist
        // preserves backward compat for legacy FFT magnitude paths that
        // don't carry a frequencies array.
        let useExplicitFrequencies =
            (inputFrequencies?.count == inputSize) && (inputSize > 1)
        let explicitFrequencies = useExplicitFrequencies ? inputFrequencies! : []

        let nyquist = currentSampleRate / 2.0
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

            let centerBin: Float
            let binWidth: Float
            if useExplicitFrequencies {
                centerBin = sourceBinForFrequency(frequency, in: explicitFrequencies)
                let upper = sourceBinForFrequency(frequency + pixelBandwidth / 2.0, in: explicitFrequencies)
                let lower = sourceBinForFrequency(frequency - pixelBandwidth / 2.0, in: explicitFrequencies)
                binWidth = max(0, upper - lower)
            } else {
                centerBin = (frequency / nyquist) * magCount
                binWidth = (pixelBandwidth / nyquist) * magCount
            }

            if binWidth < 1.0 {
                let index0 = max(0, min(inputSize - 1, Int(floor(centerBin))))
                let index1 = min(inputSize - 1, index0 + 1)
                let fraction = max(0, min(1, centerBin - Float(index0)))
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
        cachedInputFrequencies = useExplicitFrequencies ? explicitFrequencies : nil
        cachedInputFrequenciesHash = useExplicitFrequencies ? Self.hashFrequencies(explicitFrequencies) : 0
    }

    /// Fractional index of `frequency` inside a monotonically increasing
    /// frequency table. Falls back to the nearest endpoint for out-of-range
    /// queries. Linear search is fine — this only runs during the cache
    /// rebuild path, never on the audio thread.
    private func sourceBinForFrequency(_ frequency: Float, in frequencies: [Float]) -> Float {
        guard let first = frequencies.first, let last = frequencies.last else { return 0 }
        if frequency <= first { return 0 }
        if frequency >= last { return Float(frequencies.count - 1) }
        for i in 1..<frequencies.count {
            let upper = frequencies[i]
            if upper >= frequency {
                let lower = frequencies[i - 1]
                let span = max(upper - lower, 1e-6)
                let frac = (frequency - lower) / span
                return Float(i - 1) + frac
            }
        }
        return Float(frequencies.count - 1)
    }

    private static func hashFrequencies(_ frequencies: [Float]) -> UInt64 {
        // Cheap content fingerprint: count + first/mid/last bit patterns.
        // Mel tables only switch on transform-size / sample-rate /
        // band-count changes, which all flip at least one of these.
        let count = UInt64(frequencies.count)
        let firstBits = UInt64(frequencies.first?.bitPattern ?? 0)
        let lastBits = UInt64(frequencies.last?.bitPattern ?? 0)
        let midBits = UInt64(frequencies[frequencies.count / 2].bitPattern)
        return count &* 0x9E3779B97F4A7C15 ^ firstBits &* 0x85EBCA77C2B2AE63 ^ midBits &* 0xC2B2AE3D27D4EB4F ^ lastBits
    }

    // MARK: - Data Input (CPU-side normalization)

    /// Accepts FFT magnitudes (in dB SPL from AudioEngine) and writes a
    /// pre-normalized [0,1] column into the history texture.
    func updateWithFFTMagnitudes(
        _ magnitudes: [Float],
        sampleRate: Double,
        timestamp: Date,
        inputFrequencies: [Float]? = nil
    ) {
        guard isMetalReady, spectrogramTexture != nil, !isUpdatesPaused else {
            if !isMetalReady {
                print("[HighEndSpectrogramAdapter] ⚠️ Cannot update - Metal not ready")
            }
            return
        }
        updateSampleRateIfNeeded(sampleRate)

        let currentTimestamp = timestamp.timeIntervalSinceReferenceDate

        // Throttle to ~62 Hz: the Metal draw loop runs at 60 FPS, so writing
        // columns faster just overwrites data before the GPU reads it. This
        // saves the 1024-bin remap + Gaussian smooth + texture write on frames
        // that arrive above display rate (~26 of 86 frames/sec at ScrollSpeed.fast).
        let shouldSkip = stateLock.withLockUnchecked {
            lastDataTimestamp > 0 && (currentTimestamp - lastDataTimestamp) < (1.0 / 62.0)
        }
        guard !shouldSkip else { return }

        let previousTimestamp = stateLock.withLockUnchecked { () -> TimeInterval? in
            let prev = (lastDataTimestamp > 0) ? lastDataTimestamp : nil
            lastDataTimestamp = currentTimestamp
            if firstDataTimestamp == nil { firstDataTimestamp = currentTimestamp }
            return prev
        }

        // Rebuild mapping cache if input size, frequency-axis content, or
        // (implicitly via updateSampleRateIfNeeded) the sample rate changed.
        let incomingHash: UInt64 = {
            guard let freqs = inputFrequencies, freqs.count == magnitudes.count, magnitudes.count > 1 else {
                return 0
            }
            return Self.hashFrequencies(freqs)
        }()
        if mappingCache == nil
            || cachedInputSize != magnitudes.count
            || cachedInputFrequenciesHash != incomingHash {
            precomputeMapping(inputSize: magnitudes.count, inputFrequencies: inputFrequencies)
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
        // noiseFloor is in dB SPL; convert to dBFS using the current calibration.
        let floorDBFS = max(noiseFloor - calibrationOffset, minDBFS)
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

        // Phase 1 (under stateLock): advance the ring-buffer pointer and
        // collect (column-index, pixel-data) pairs. No texture I/O here —
        // keeping the lock critical section short and avoiding any cross-
        // thread texture access.
        var pendingWrites: [(column: Int, data: [Float])] = []
        stateLock.withLockUnchecked {
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

            if columnsToWrite > 1, previousColumnData.count == reusableColumnData.count {
                for step in 1...columnsToWrite {
                    let mixFactor = Float(step) / Float(columnsToWrite)
                    for i in 0..<reusableColumnData.count {
                        reusableInterpolatedColumnData[i] =
                            previousColumnData[i] * (1.0 - mixFactor) + reusableColumnData[i] * mixFactor
                    }
                    pendingWrites.append((currentColumn, Array(reusableInterpolatedColumnData)))
                    currentColumn = (currentColumn + 1) % timeColumns
                }
            } else {
                pendingWrites.append((currentColumn, Array(reusableColumnData)))
                currentColumn = (currentColumn + 1) % timeColumns
            }
            previousColumnData = reusableColumnData
            totalColumnsWritten += columnsToWrite
        }

        // Phase 2: write column pixels to the Metal texture on the main thread.
        // Both this write and draw(_:)'s GPU-encoder submit happen on main,
        // so they are serialised by the main queue — no CPU/GPU texture race.
        let bins = frequencyBins
        DispatchQueue.main.async { [weak self] in
            guard let self, let texture = self.spectrogramTexture else { return }
            for (col, data) in pendingWrites {
                let region = MTLRegion(
                    origin: MTLOrigin(x: col, y: 0, z: 0),
                    size: MTLSize(width: 1, height: bins, depth: 1)
                )
                texture.replace(
                    region: region,
                    mipmapLevel: 0,
                    withBytes: data,
                    bytesPerRow: MemoryLayout<Float>.stride
                )
            }
        }
    }

    private func applyFrequencySmoothingIfNeeded(values: inout [Float]) {
        // Always-on baseline smoothing hides FFT-bin boundaries that become
        // visible on the log-frequency axis at low frequencies, where multiple
        // display pixels map to the same FFT bin and `precomputeMapping`'s
        // linear interpolation produces visible plateaus. The user slider
        // (`frequencySmoothing`) adds further smoothing on top.
        let userStrength = max(0.0, min(1.0, frequencySmoothing))
        let baselineStrength: Float = 0.25
        let strength = max(baselineStrength, userStrength)
        guard values.count > 2 else { return }

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

    // MARK: - Rendering

    override func draw(_ rect: CGRect) {
#if canImport(UIKit)
        if UIApplication.shared.applicationState != .active {
            return
        }
#endif
        guard isMetalReady,
              pipelineState != nil,
              commandQueue != nil,
              spectrogramTexture != nil,
              !scrollBuffers.isEmpty
        else { return }
        guard inFlightSemaphore.wait(timeout: .now()) == .success else { return }

        guard let renderPassDescriptor = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else {
            inFlightSemaphore.signal()
            return
        }

        let semaphore = inFlightSemaphore
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }

        // Snapshot the ring-buffer scalars in one locked block so we cannot
        // observe a torn write from the background updateQueue. Everything
        // below this point uses the local snapshots.
        let (snapCurrentColumn, snapTotalColumnsWritten, snapFirstDataTimestamp, snapLastDataTimestamp) =
            stateLock.withLockUnchecked {
                (currentColumn, totalColumnsWritten, firstDataTimestamp, lastDataTimestamp)
            }

        // Smooth display scroll: advance at a constant rate tied to CACurrentMediaTime()
        // rather than data timestamps. This eliminates the micro-jumps that occur when
        // the integer columnsToWrite doesn't match the expected fractional advance.
        let lastWrittenColumn = (snapCurrentColumn - 1 + timeColumns) % timeColumns
        let now = CACurrentMediaTime()
        let frameDt = lastCADrawTime > 0 ? min(now - lastCADrawTime, 0.05) : 0
        lastCADrawTime = now

        if !displayScrollSynced && snapTotalColumnsWritten > 0 {
            displayScrollPosition = Double(lastWrittenColumn)
            displayScrollSynced = true
        } else if frameDt > 0 && currentTimeSpanValue > 0 && snapTotalColumnsWritten > 0 && !isUpdatesPaused {
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

        var totalOffset = Float(displayScrollPosition.truncatingRemainder(dividingBy: Double(timeColumns))) / Float(timeColumns)
        let fillRatio = min(1.0, Float(snapTotalColumnsWritten) / Float(max(timeColumns, 1)))

        // Push axis metrics at ~30 Hz
        let nowUptime = ProcessInfo.processInfo.systemUptime
        if nowUptime - lastAxisMetricsPushUptime >= (1.0 / 10.0) {
            lastAxisMetricsPushUptime = nowUptime
            let recordingTime: Double
            if let first = snapFirstDataTimestamp {
                recordingTime = max(0, snapLastDataTimestamp - first)
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

        // Colormap texture is built eagerly in `setColormap`; no need to
        // build (or even gate-check) per frame inside the draw loop.
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
        stateLock.withLockUnchecked {
            currentColumn = 0
            totalColumnsWritten = 0
            columnAdvanceAccumulator = 0
            firstDataTimestamp = nil
            lastDataTimestamp = 0
            previousColumnData = [Float](repeating: 0, count: frequencyBins)
        }
        // `displayScrollSynced` is read/written only on the main thread inside
        // `draw(_:)`. `reset()` is conventionally called from main; keep it
        // outside the lock to avoid pretending we synchronize a value that
        // doesn't actually share a thread with the lock's other consumers.
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
        // Build the colormap texture eagerly so the draw loop never has to
        // (the previous per-frame call from inside `draw(_:)` was a cheap
        // dict lookup most of the time but still ran on every CADisplayLink
        // tick — there is no need for it there at all).
        buildColormapTexture(type: clamped)
        if Thread.isMainThread {
            setNeedsDisplay()
        } else {
            DispatchQueue.main.async { [weak self] in self?.setNeedsDisplay() }
        }
    }

    /// Set the noise floor in dB SPL. Values > −119 activate a 6 dB soft-knee
    /// transition so the floor boundary fades rather than hard-clips.
    func setNoiseFloor(_ spl: Float) {
        noiseFloor = spl
        kneeWidth = spl > -119 ? 6.0 : 0.0
    }
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

    func setPaused(_ paused: Bool) {
        let wasPaused = isUpdatesPaused
        isUpdatesPaused = paused
        if wasPaused && !paused { lastCADrawTime = 0 }  // prevent frameDt spike on resume
    }

    private func updateSampleRateIfNeeded(_ sampleRate: Double) {
        guard sampleRate > 1000 else { return }
        let normalized = Float((sampleRate * 10.0).rounded() / 10.0)
        guard abs(normalized - currentSampleRate) > 0.5 else { return }

        currentSampleRate = normalized
        mappingCache = nil
        cachedInputSize = 0
        cachedInputFrequencies = nil
        cachedInputFrequenciesHash = 0
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
        // Cap timeColumns at a value that fits within all Metal device texture
        // limits (8192 minimum across all Metal-capable iOS hardware). The UI
        // never requests more than 60 s × 86 Hz ≈ 5160 columns, so 6000 is
        // generous enough to cover future scroll speeds while staying safe.
        let deviceMaxColumns = 6000
        let newColumns: Int
        if currentTimeSpanValue == 0 {
            newColumns = min(8192, deviceMaxColumns)
        } else {
            // Ensure enough columns for sub-pixel resolution on modern displays.
            // Minimum 1200 prevents visible column banding on retina screens.
            let audioColumns = Int(Double(currentTimeSpanValue) * updateRate)
            newColumns = min(max(1200, audioColumns), deviceMaxColumns)
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
        print("[HighEndSpectrogramAdapter] ⚠️ Metal unavailable: \(reason)")
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
    var freqWeighting: String = "Z"
    var sensitivity: Float = 90.0
    var frequencySmoothing: Float = 0.0
    /// Noise floor in dB SPL. −120 = off. Passed to setNoiseFloor(), which
    /// auto-enables a 6 dB soft-knee when the floor is active.
    var noiseFloor: Float = -120.0
    var onAxisMetricsChanged: ((SpectrogramAxisMetrics) -> Void)? = nil

    func makeUIView(context: Context) -> HighEndSpectrogramAdapter {
        let view = HighEndSpectrogramAdapter(
            frame: .zero,
            device: MetalWidgetManager.shared.sharedDevice
        )
        view.setColormap(colormapType)
        view.setTimeSpan(timeSpan.rawValue)
        view.setHopSize(scrollSpeed.rawValue)
        view.setPaused(isPaused)
        view.setSensitivity(sensitivity)
        view.setFrequencySmoothing(frequencySmoothing)
        view.setNoiseFloor(noiseFloor)
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
        uiView.setSensitivity(sensitivity)
        uiView.setFrequencySmoothing(frequencySmoothing)
        uiView.setNoiseFloor(noiseFloor)
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

            // .userInitiated rather than .userInteractive: we want smooth
            // updates but not at the cost of competing with the main thread
            // for the same CPU priority tier (which caused 400% CPU + hangs).
            let updateQueue = DispatchQueue(label: "com.spektowatch.spectrogram.update", qos: .userInitiated)
            // Subscribe to spectrogramSubject (full audio rate, no objectWillChange trigger)
            // instead of $currentSpectrogramData (would cause SwiftUI to re-render at 60 Hz).
            cancellable = audioEngine.spectrogramSubject
                .receive(on: updateQueue)
                .sink { [weak self] data in
                    guard let self = self else { return }
                    let magnitudes = data.visualMagnitudes ?? data.magnitudes(for: self.freqWeighting)
                    // When the producer ran the Apple-style DCT→mel pipeline
                    // it emits mel-spaced bin centers in `visualFrequencies`;
                    // the adapter honours those instead of forcing the
                    // linear-from-Nyquist remap that the FFT path uses.
                    let inputFrequencies = (data.visualMagnitudes != nil) ? data.visualFrequencies : nil
                    self.view?.updateWithFFTMagnitudes(
                        magnitudes,
                        sampleRate: data.sampleRate,
                        timestamp: data.timestamp,
                        inputFrequencies: inputFrequencies
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
    var freqWeighting: String = "Z"
    var sensitivity: Float = 90.0
    var frequencySmoothing: Float = 0.0
    var noiseFloor: Float = -120.0

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

                HighEndSpectrogramAdapterView(audioEngine: audioEngine, colormapType: colormapType, timeSpan: timeSpan, scrollSpeed: scrollSpeed, isPaused: isPaused, freqWeighting: freqWeighting, sensitivity: sensitivity, frequencySmoothing: frequencySmoothing, noiseFloor: noiseFloor)
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
    var freqWeighting: String = "Z"
    var sensitivity: Float = 90.0
    var frequencySmoothing: Float = 0.0
    var noiseFloor: Float = -120.0
    let axisWidth: CGFloat = 35
    let axisHeight: CGFloat = 28
    let axisSpacing: CGFloat = 4
    @State private var axisMetrics = SpectrogramAxisMetrics()
    @State private var axisMetricsReceivedAt: Double = 0

    let axisFrequencies: [Double] = [20000, 16000, 8000, 4000, 2000, 1000, 500, 250, 125, 63, 31.5]

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: axisSpacing) {
                spectrogramContent
            }
        }
    }
    
    private var spectrogramView: some View {
        HighEndSpectrogramAdapterView(
            audioEngine: audioEngine,
            colormapType: colormapType,
            timeSpan: timeSpan,
            scrollSpeed: scrollSpeed,
            isPaused: isPaused,
            freqWeighting: freqWeighting,
            sensitivity: sensitivity,
            frequencySmoothing: frequencySmoothing,
            noiseFloor: noiseFloor,
            onAxisMetricsChanged: { metrics in
                axisMetrics = metrics
                axisMetricsReceivedAt = CACurrentMediaTime()
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(4)
    }
    
    private var frequencyAxisOverlay: some View {
        GeometryReader { spectroGeo in
            ZStack(alignment: .topLeading) {
                ForEach(axisFrequencies, id: \.self) { freq in
                    Text(frequencyLabel(freq))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 0)
                        .padding(.leading, 8)
                        .position(x: 25, y: yPosition(for: freq, height: spectroGeo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(4)
    }
    
    private var timeAxisOverlay: some View {
        TimelineView(.animation) { _ in
            GeometryReader { spectroGeo in
                Canvas { context, size in
                    // Extrapolate recording time at display refresh rate to stay in sync
                    // with the Metal spectrogram, which scrolls at 60 FPS via CACurrentMediaTime().
                    // Without this, labels update at 10 Hz and visibly lag the scrolling content.
                    let elapsed = (!isPaused && axisMetricsReceivedAt > 0)
                        ? min(CACurrentMediaTime() - axisMetricsReceivedAt, Double(timeSpan.rawValue))
                        : 0
                    let duration = max(axisMetrics.recordingTimeSeconds + elapsed, 0)
                    let span = Double(timeSpan.rawValue)
                    guard span > 0 else { return }

                    let visibleEnd = duration
                    let visibleStart = max(0, visibleEnd - span)
                    let visibleRange = visibleEnd - visibleStart
                    let filledRatio = min(max(Double(axisMetrics.fillRatio), 0), 1)
                    let axisVisibleWidth = size.width * CGFloat(filledRatio)
                    let baselineY = size.height - 12

                    let tickStep = self.xAxisTickStep(for: visibleRange)
                    guard tickStep > 0 else { return }

                    let firstTick = Foundation.ceil(visibleStart / tickStep) * tickStep
                    let lastTick = visibleEnd + (tickStep * 0.5)
                    var lastLabelX: CGFloat = -.greatestFiniteMagnitude

                    for tick in stride(from: firstTick, through: lastTick, by: tickStep) {
                        let x = CGFloat((visibleEnd - tick) / span) * size.width
                        guard x >= 0 && x <= axisVisibleWidth else { continue }

                        if abs(x - lastLabelX) > 28 {
                            var shadowContext = context
                            shadowContext.addFilter(.shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 0))

                            let text = Text(self.formatAxisTime(tick))
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.9))

                            shadowContext.draw(text, at: CGPoint(x: x, y: baselineY), anchor: .center)
                            lastLabelX = x
                        }
                    }
                }
            }
        }
        .padding(4)
    }
    
    private var spectrogramContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.24))

            spectrogramView
            frequencyAxisOverlay
            timeAxisOverlay
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.75), lineWidth: 18)
                .blur(radius: 10)
                .mask(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .drawingGroup()  // rasterize once, avoids per-frame Core Image blur
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
