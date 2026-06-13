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
// MARK: - Shared Column History (fullscreen continuity)
// ============================================================================
//
// Each `HighEndSpectrogramAdapter` (MTKView) owns its own scroll texture, so a
// second adapter — e.g. the fullscreen cover presented over the dashboard tile
// — would otherwise start blank and scroll in fresh, breaking the measurement's
// visual continuity. To avoid that, a single shared history records the exact
// normalized columns written by the persistent (tile) adapter; a newly mounted
// adapter primes its texture from that history so it picks up mid-stream.
//
// One adapter is the writer (the first to claim it, i.e. the always-mounted
// tile). Others are readers that only prime. The store is fed from the
// adapter's background update queue and read while priming on the main thread,
// so all access is serialised by `lock`.
final class SpectrogramColumnHistory {
    private let lock = OSAllocatedUnfairLock()
    private var ring: [[Float]] = []
    private var head: Int = 0
    private var filled: Int = 0
    private var capacity: Int = 0
    private var frequencyBins: Int = 0
    private var timeColumns: Int = 0
    private weak var writer: HighEndSpectrogramAdapter?

    /// The first adapter to claim becomes the single writer; returns whether
    /// `adapter` is (now) that writer. Idempotent for the current writer.
    func claimWriter(_ adapter: HighEndSpectrogramAdapter) -> Bool {
        lock.withLockUnchecked {
            if writer == nil || writer === adapter {
                writer = adapter
                return true
            }
            return false
        }
    }

    func resignWriter(_ adapter: HighEndSpectrogramAdapter) {
        lock.withLockUnchecked {
            if writer === adapter { writer = nil }
        }
    }

    /// Appends the columns just written to the writer's texture, in order.
    /// A change in texture geometry clears the history (the old columns no
    /// longer correspond to the new frequency/time axis).
    func record(columns newColumns: [[Float]], frequencyBins fb: Int, timeColumns tc: Int) {
        guard !newColumns.isEmpty, fb > 0, tc > 0 else { return }
        lock.withLockUnchecked {
            if fb != frequencyBins || tc != timeColumns || capacity != tc {
                frequencyBins = fb
                timeColumns = tc
                capacity = tc
                ring = [[Float]](repeating: [], count: tc)
                head = 0
                filled = 0
            }
            for col in newColumns where col.count == fb {
                ring[head] = col
                head = (head + 1) % capacity
                filled = min(filled + 1, capacity)
            }
        }
    }

    /// Ordered oldest→newest columns, or nil if the geometry doesn't match the
    /// caller's texture (in which case priming is skipped — no regression).
    func snapshot(frequencyBins fb: Int, timeColumns tc: Int) -> [[Float]]? {
        lock.withLockUnchecked {
            guard fb == frequencyBins, tc == timeColumns, filled > 0, capacity > 0 else { return nil }
            var result = [[Float]]()
            result.reserveCapacity(filled)
            let start = (head - filled + capacity) % capacity
            for i in 0..<filled {
                result.append(ring[(start + i) % capacity])
            }
            return result
        }
    }
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
    private var frequencyBins: Int = SpectrogramResolution.defaultValue.textureFrequencyBins
    private var timeColumns: Int = 600
    private var hopSize: Int = 512
    private var currentTimeSpanValue: Int = 5
    private var currentSampleRate: Float = 44100.0
    private var minFrequency: Float = 20.0
    private var maxFrequency: Float = 20000.0
    private var frequencyScale: SpectrogramFrequencyScale = .logarithmic

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

    // Interactive view window (pan/zoom), applied in the fragment shader.
    // timeStart 0 = newest edge; freqStart 0 = lowest displayed frequency.
    private var viewportTimeStart: Float = 0
    private var viewportTimeWidth: Float = 1
    private var viewportFreqStart: Float = 0
    private var viewportFreqHeight: Float = 1
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

    // MARK: - Shared History (fullscreen continuity)
    private var columnHistory: SpectrogramColumnHistory?
    private var isHistoryWriter = false

    deinit {
        isPaused = true
        columnHistory?.resignWriter(self)
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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Match the actual display's refresh rate (60 on LCD models, 120 on
        // ProMotion). window is nil on removal — keep the last value then.
        if let maxFPS = window?.screen.maximumFramesPerSecond {
            preferredFramesPerSecond = maxFPS
        }
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
        // Fallback until the view joins a window; didMoveToWindow raises this
        // to the display's native rate (120 on ProMotion, requires the
        // CADisableMinimumFrameDurationOnPhone Info.plist key). Scrolling is
        // CACurrentMediaTime()-based, so speed is frame-rate independent.
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
        let linearSpan = max(maxFrequency - minFrequency, 0.0001)
        let isLinear = (frequencyScale == .linear)

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

        // Maps a normalized axis position [0,1] to a frequency under the active
        // scale. Linear → uniform Hz steps (even FFT-bin rows); log → equal
        // musical intervals get equal height.
        func frequencyForT(_ t: Float) -> Float {
            isLinear ? (minFrequency + t * linearSpan)
                     : pow(10.0, logMin + t * logSpan)
        }

        for i in 0..<frequencyBins {
            let t = Float(i) / Float(frequencyBins - 1)
            let frequency = frequencyForT(t)

            let tNext = Float(i + 1) / Float(frequencyBins - 1)
            let freqNext = frequencyForT(tNext)
            let pixelBandwidth = (i < frequencyBins - 1)
                ? (freqNext - frequency)
                : (frequency - frequencyForT(Float(i - 1) / Float(frequencyBins - 1)))

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
                dbValue = linear + (peak - linear) * 0.35
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
                    dbValue = meanDb + (peakDb - meanDb) * 0.35
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

        // Feed the shared history (writer only) so a newly mounted adapter can
        // prime its texture and continue the same measurement seamlessly.
        if isHistoryWriter, let history = columnHistory {
            history.record(columns: pendingWrites.map { $0.data },
                           frequencyBins: frequencyBins,
                           timeColumns: timeColumns)
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
        // Minimal always-on smoothing: just enough to hide FFT-bin plateaus on
        // the log axis without smearing fine harmonics. The user slider adds
        // more on top when desired.
        let baselineStrength: Float = 0.08
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

        // Push axis metrics at ~30 Hz. The label x-positions are extrapolated
        // from CACurrentMediaTime() between pushes, so a sparse 10 Hz cadence
        // left a 100 ms gap that made each re-anchor visibly snap (choppy axis).
        // Pushing at 30 Hz shrinks the gap and the per-correction jump.
        let nowUptime = ProcessInfo.processInfo.systemUptime
        if nowUptime - lastAxisMetricsPushUptime >= (1.0 / 30.0) {
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
        var vp = SIMD4<Float>(viewportTimeStart, viewportTimeWidth, viewportFreqStart, viewportFreqHeight)
        encoder.setFragmentBytes(&vp, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
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

    /// Attaches the shared column history. The first adapter to attach becomes
    /// the writer (it feeds the history); later adapters are readers that prime
    /// their texture from it so they pick up the live measurement mid-stream.
    func setColumnHistory(_ history: SpectrogramColumnHistory?) {
        if columnHistory !== history {
            columnHistory?.resignWriter(self)
        }
        columnHistory = history
        isHistoryWriter = history?.claimWriter(self) ?? false
        if !isHistoryWriter {
            primeFromHistoryIfNeeded()
        }
    }

    /// Primes a *fresh* texture (nothing written yet) from the shared history so
    /// the reader adapter starts where the writer is, then continues live.
    private func primeFromHistoryIfNeeded() {
        guard isMetalReady, spectrogramTexture != nil, !isHistoryWriter,
              let history = columnHistory else { return }
        let alreadyWritten = stateLock.withLockUnchecked { totalColumnsWritten }
        guard alreadyWritten == 0 else { return }
        guard let cols = history.snapshot(frequencyBins: frequencyBins, timeColumns: timeColumns) else { return }
        primeTexture(with: cols)
    }

    /// Writes the historical columns into the texture (oldest→newest at columns
    /// 0…n-1, mirroring the normal sequential write model) and seeds the scroll
    /// state so the very next live column lands at the correct position.
    private func primeTexture(with cols: [[Float]]) {
        guard let texture = spectrogramTexture else { return }
        let count = min(cols.count, timeColumns)
        guard count > 0 else { return }
        let bins = frequencyBins
        let start = cols.count - count
        let bytesPerRow = MemoryLayout<Float>.stride
        for offset in 0..<count {
            let data = cols[start + offset]
            guard data.count == bins else { continue }
            let region = MTLRegion(origin: MTLOrigin(x: offset, y: 0, z: 0),
                                   size: MTLSize(width: 1, height: bins, depth: 1))
            texture.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: bytesPerRow)
        }
        let secondsPerColumn = effectiveSecondsPerColumn
        stateLock.withLockUnchecked {
            currentColumn = count % timeColumns
            totalColumnsWritten = count
            columnAdvanceAccumulator = 0
            previousColumnData = cols[start + count - 1]
            let nowTs = Date().timeIntervalSinceReferenceDate
            lastDataTimestamp = nowTs
            firstDataTimestamp = nowTs - Double(count) * secondsPerColumn
        }
        // Force draw() to re-anchor the smooth scroll to the new write head.
        displayScrollSynced = false
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

    /// Switches the frequency axis between log and linear. Invalidates the
    /// frequency-mapping cache so the next frame rebuilds the bin layout.
    func setFrequencyScale(_ scale: SpectrogramFrequencyScale) {
        guard frequencyScale != scale else { return }
        frequencyScale = scale
        invalidateMappingCache()
    }

    /// Sets the displayed frequency range (Hz). No-op if unchanged.
    func setFrequencyRange(min lo: Float, max hi: Float) {
        let clampedLo = max(1.0, min(lo, hi - 1.0))
        let clampedHi = max(clampedLo + 1.0, hi)
        guard abs(clampedLo - minFrequency) > 0.01 || abs(clampedHi - maxFrequency) > 0.01 else { return }
        minFrequency = clampedLo
        maxFrequency = clampedHi
        invalidateMappingCache()
    }

    private func invalidateMappingCache() {
        mappingCache = nil
        cachedInputSize = 0
        cachedInputFrequencies = nil
        cachedInputFrequenciesHash = 0
    }

    /// Interactive pan/zoom window applied in the shader (no CPU remap, so it is
    /// cheap and works while paused). All inputs are clamped to valid sub-windows.
    func setViewport(timeStart: Float, timeWidth: Float, freqStart: Float, freqHeight: Float) {
        let tw = max(0.02, min(1.0, timeWidth))
        let ts = max(0.0, min(1.0 - tw, timeStart))
        let fh = max(0.02, min(1.0, freqHeight))
        let fs = max(0.0, min(1.0 - fh, freqStart))
        guard ts != viewportTimeStart || tw != viewportTimeWidth
            || fs != viewportFreqStart || fh != viewportFreqHeight else { return }
        viewportTimeStart = ts
        viewportTimeWidth = tw
        viewportFreqStart = fs
        viewportFreqHeight = fh
        if Thread.isMainThread {
            setNeedsDisplay()
        } else {
            DispatchQueue.main.async { [weak self] in self?.setNeedsDisplay() }
        }
    }

    func setHopSize(_ size: Int) {
        if hopSize != size {
            hopSize = size
            updateTimeColumns()
        }
    }

    func setTimeSpan(_ span: Int) {
        guard span != currentTimeSpanValue else { return }
        currentTimeSpanValue = span
        updateTimeColumns()
    }

    func setFrequencyBinCount(_ count: Int) {
        let clamped = max(256, min(2048, count))
        guard clamped != frequencyBins else { return }
        frequencyBins = clamped
        mappingCache = nil
        cachedInputSize = 0
        cachedInputFrequencies = nil
        cachedInputFrequenciesHash = 0
        reusableColumnData = []
        reusableSmoothedColumnData = []
        previousColumnData = []
        reusableInterpolatedColumnData = []
        guard isMetalReady else { return }
        isPaused = true
        setupTexture()
        reset()
        isPaused = false
    }

    func applySpectrogramResolution(_ resolution: SpectrogramResolution) {
        setFrequencyBinCount(resolution.textureFrequencyBins)
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
    var frequencyScale: SpectrogramFrequencyScale = .logarithmic
    var minFrequency: Float = 20.0
    var maxFrequency: Float = 20000.0
    var viewportTimeStart: Float = 0
    var viewportTimeWidth: Float = 1
    var viewportFreqStart: Float = 0
    var viewportFreqHeight: Float = 1
    var onAxisMetricsChanged: ((SpectrogramAxisMetrics) -> Void)? = nil
    /// Optional shared history enabling seamless continuity when the same
    /// measurement is shown in more than one adapter (e.g. tile + fullscreen).
    var columnHistory: SpectrogramColumnHistory? = nil

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
        view.setFrequencyRange(min: minFrequency, max: maxFrequency)
        view.setFrequencyScale(frequencyScale)
        view.setViewport(timeStart: viewportTimeStart, timeWidth: viewportTimeWidth,
                         freqStart: viewportFreqStart, freqHeight: viewportFreqHeight)
        view.applySpectrogramResolution(audioEngine.spectrogramResolution)
        view.setColumnHistory(columnHistory)
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
        uiView.setFrequencyRange(min: minFrequency, max: maxFrequency)
        uiView.setFrequencyScale(frequencyScale)
        uiView.setViewport(timeStart: viewportTimeStart, timeWidth: viewportTimeWidth,
                           freqStart: viewportFreqStart, freqHeight: viewportFreqHeight)
        uiView.applySpectrogramResolution(audioEngine.spectrogramResolution)
        uiView.setColumnHistory(columnHistory)
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
// MARK: - Container with Axis Labels
// ============================================================================

struct HighEndSpectrogramAdapterWithAxes: View {
    @ObservedObject var audioEngine: AudioEngine
    var colormapType: Int = 0
    var timeSpan: SpectrogramTimeSpan = .seconds5
    var scrollSpeed: ScrollSpeed = .fast
    var isPaused: Bool = false
    var freqWeighting: String = "Z"
    var sensitivity: Float = 90.0
    var frequencySmoothing: Float = 0.0
    var noiseFloor: Float = -120.0
    var columnHistory: SpectrogramColumnHistory? = nil
    let axisWidth: CGFloat = 35
    let axisHeight: CGFloat = 28
    let axisSpacing: CGFloat = 4
    @State private var axisMetrics = SpectrogramAxisMetrics()
    @State private var axisMetricsReceivedAt: Double = 0

    private var frequencyScale: SpectrogramFrequencyScale { audioEngine.spectrogramFrequencyScale }
    private var minFreq: Double { audioEngine.spectrogramMinFrequency }
    private var maxFreq: Double { audioEngine.spectrogramMaxFrequency }

    private var axisFrequencies: [Double] {
        SpectrogramAxisMath.axisTickFrequencies(
            scale: frequencyScale,
            minFrequency: minFreq,
            maxFrequency: maxFreq
        )
    }

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
            frequencyScale: frequencyScale,
            minFrequency: Float(minFreq),
            maxFrequency: Float(maxFreq),
            onAxisMetricsChanged: { metrics in
                axisMetrics = metrics
                axisMetricsReceivedAt = CACurrentMediaTime()
            },
            columnHistory: columnHistory
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
        SpectrogramAxisMath.yPosition(
            for: freq,
            height: height,
            scale: frequencyScale,
            minFrequency: minFreq,
            maxFrequency: maxFreq
        )
    }

    private func xAxisTickStep(for visibleRange: Double) -> Double {
        SpectrogramAxisMath.xAxisTickStep(for: visibleRange)
    }

    private func formatAxisTime(_ seconds: Double) -> String {
        SpectrogramAxisMath.formatAxisTime(seconds)
    }

    private func frequencyLabel(_ freq: Double) -> String {
        SpectrogramAxisMath.frequencyLabel(freq)
    }
}
