import SwiftUI
import MetalKit
import Accelerate
import Combine

// MARK: - Playback Spectrogram Renderer (uses new minimal shaders)

/// Mapping uniform mirrored by `PlaybackMapping` in `HighEndSpectrogramShaders.metal`.
/// Layout must stay in sync (four 32-bit floats, 16-byte stride).
struct PlaybackMapping {
    var minDBFS: Float
    var maxDBFS: Float
    var gamma: Float
    var calibration: Float
}

class PlaybackSpectrogramRenderer: MTKView {
    // MARK: - Metal Resources
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var viewportBuffer: MTLBuffer!
    private var mappingBuffer: MTLBuffer!

    // MARK: - Textures
    private var spectrogramTexture: MTLTexture!
    private var colormapTexture: MTLTexture?
    private var textureWidth: Int = 0
    private var textureHeight: Int = 512

    // MARK: - Data
    private var magnitudeHistory: [[Float]] = []
    private var isTextureReady = false
    /// Identifies the uploaded history content. The SwiftUI layer bumps this
    /// whenever the matrix changes (e.g. a weighting switch that keeps the same
    /// column count), so the texture is re-uploaded even when the shape is
    /// unchanged — fixing the stale-image bug where A/C weighting never showed.
    private(set) var dataVersion: Int = Int.min
    /// Floor written into texture rows that have no data (above the highest bin).
    private let unfilledDBFloor: Float = -160

    /// True once Metal setup completed successfully. If false, the renderer
    /// silently no-ops in `draw()` and `loadSpectrogramData()` so the
    /// surrounding SwiftUI hierarchy can fall back to a plain view instead of
    /// the app crashing on devices/simulators where Metal pipeline creation
    /// fails (shader ABI mismatch, no Metal device, etc.).
    private(set) var isMetalReady = false

    // MARK: - Display Parameters
    var colormapType: Int = 0 {
        didSet { rebuildColormapTexture() }
    }
    private let displayMaxDBFS: Float = -20.0
    private let dynamicRange: Float = 90.0
    private var displayMinDBFS: Float { displayMaxDBFS - dynamicRange }
    private let gamma: Float = 1.15
    private var calibrationOffset: Float = 94.0

    // MARK: - Scroll/Zoom (two-axis viewport, normalized 0…1)
    var viewportStart: Float = 0.0
    var viewportWidth: Float = 1.0
    var freqViewportStart: Float = 0.0
    var freqViewportWidth: Float = 1.0

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
            print("[PlaybackSpectrogramRenderer] Metal device unavailable — falling back to disabled renderer.")
            isMetalReady = false
            return
        }

        self.framebufferOnly = true
        self.enableSetNeedsDisplay = true
        self.isPaused = true
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        self.colorPixelFormat = .bgra8Unorm

        guard let queue = device.makeCommandQueue() else {
            print("[PlaybackSpectrogramRenderer] Failed to create Metal command queue.")
            isMetalReady = false
            return
        }
        commandQueue = queue

        guard setupPipeline() else {
            isMetalReady = false
            return
        }

        guard let buffer = device.makeBuffer(
            length: MemoryLayout<SIMD4<Float>>.stride,
            options: .storageModeShared
        ) else {
            print("[PlaybackSpectrogramRenderer] Failed to create viewport buffer.")
            isMetalReady = false
            return
        }
        viewportBuffer = buffer

        guard let mapping = device.makeBuffer(
            length: MemoryLayout<PlaybackMapping>.stride,
            options: .storageModeShared
        ) else {
            print("[PlaybackSpectrogramRenderer] Failed to create mapping buffer.")
            isMetalReady = false
            return
        }
        mappingBuffer = mapping
        writeMappingBuffer()

        rebuildColormapTexture()
        isMetalReady = true
    }

    private func writeMappingBuffer() {
        guard let mappingBuffer else { return }
        var mapping = PlaybackMapping(
            minDBFS: displayMinDBFS,
            maxDBFS: displayMaxDBFS,
            gamma: gamma,
            calibration: calibrationOffset
        )
        memcpy(mappingBuffer.contents(), &mapping, MemoryLayout<PlaybackMapping>.stride)
    }

    /// Returns true on success. Previously called `fatalError` on pipeline
    /// creation failure, which crashes the app on Metal-incompatible
    /// simulators or after a shader ABI mismatch.
    @discardableResult
    private func setupPipeline() -> Bool {
        guard let device = device,
              let library = device.makeDefaultLibrary() else {
            print("[PlaybackSpectrogramRenderer] Default Metal library unavailable.")
            return false
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "spectrogramVertex")
        desc.fragmentFunction = library.makeFunction(name: "playbackSpectrogramFragment")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
            return true
        } catch {
            print("[PlaybackSpectrogramRenderer] Failed to create pipeline: \(error)")
            return false
        }
    }

    private func rebuildColormapTexture() {
        guard let device = device else { return }
        let cmType = ColormapType(rawValue: colormapType) ?? .turbo
        colormapTexture = ColormapTexture.makeTexture(device: device, type: cmType)
    }

    // MARK: - Data Loading

    func loadSpectrogramData(_ history: [[Float]], version: Int = Int.min) {
        guard !history.isEmpty else { return }

        magnitudeHistory = history
        dataVersion = version
        textureWidth = history.count
        textureHeight = history.first?.count ?? 512

        createTexture()
        fillTexture()
        isTextureReady = spectrogramTexture != nil
        setNeedsDisplay()
    }

    // `computeFromAudioSamples` was removed in M6 task-9. It was an alternate
    // entry point that computed the spectrogram from raw audio samples on the
    // calling thread (synchronously on main, blocking for long recordings).
    // It had no callers; `updateUIView` always feeds `loadSpectrogramData`
    // with a pre-computed history from `StoredDataProvider` or
    // `computeSpectrogramHistoryStreaming` on `RecordingDetailView`.

    private func createTexture() {
        guard let device = device else { return }

        let desc = MTLTextureDescriptor()
        desc.textureType = .type2D
        desc.pixelFormat = .r32Float
        desc.width = textureWidth
        desc.height = textureHeight
        desc.usage = .shaderRead
        desc.storageMode = .shared

        spectrogramTexture = device.makeTexture(descriptor: desc)
    }

    /// Uploads raw dB SPL values into the texture. The dB→colour mapping
    /// (calibration, dynamic range, gamma) is applied in the fragment shader,
    /// so calibration/range changes no longer require re-uploading the texture.
    private func fillTexture() {
        guard let texture = spectrogramTexture else { return }

        for (columnIndex, column) in magnitudeHistory.enumerated() {
            var columnData = [Float](repeating: unfilledDBFloor, count: textureHeight)
            let count = min(column.count, textureHeight)
            if count > 0 {
                column.withUnsafeBufferPointer { src in
                    columnData.withUnsafeMutableBufferPointer { dst in
                        dst.baseAddress!.update(from: src.baseAddress!, count: count)
                    }
                }
            }

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
        guard isMetalReady,
              isTextureReady,
              commandQueue != nil,
              pipelineState != nil,
              viewportBuffer != nil,
              mappingBuffer != nil,
              let renderPassDescriptor = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor),
              colormapTexture != nil
        else { return }

        let clampedWidth = max(0.0001, min(1.0, viewportWidth))
        let clampedStart = max(0.0, min(1.0 - clampedWidth, viewportStart))
        let clampedFreqWidth = max(0.0001, min(1.0, freqViewportWidth))
        let clampedFreqStart = max(0.0, min(1.0 - clampedFreqWidth, freqViewportStart))
        var viewport = SIMD4<Float>(clampedStart, clampedWidth, clampedFreqStart, clampedFreqWidth)
        memcpy(viewportBuffer.contents(), &viewport, MemoryLayout<SIMD4<Float>>.stride)

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(spectrogramTexture, index: 0)
        encoder.setFragmentTexture(colormapTexture, index: 1)
        encoder.setFragmentBuffer(viewportBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(mappingBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Public API

    func setColormap(_ type: Int) {
        let clamped = max(0, min(ColormapType.allCases.count - 1, type))
        guard colormapType != clamped else { return }
        colormapType = clamped
        setNeedsDisplay()
    }

    /// Sets the visible time and frequency windows (all values normalized 0…1,
    /// frequency measured from the low end). Returns without redrawing if
    /// nothing changed, so the SwiftUI layer can call it freely from `update`.
    func setViewport(start: Float, width: Float, freqStart: Float, freqWidth: Float) {
        let clampedWidth = max(0.0001, min(1.0, width))
        let newStart = max(0.0, min(1.0 - clampedWidth, start))
        let clampedFreqWidth = max(0.0001, min(1.0, freqWidth))
        let newFreqStart = max(0.0, min(1.0 - clampedFreqWidth, freqStart))

        guard newStart != viewportStart || clampedWidth != viewportWidth ||
                newFreqStart != freqViewportStart || clampedFreqWidth != freqViewportWidth
        else { return }

        viewportStart = newStart
        viewportWidth = clampedWidth
        freqViewportStart = newFreqStart
        freqViewportWidth = clampedFreqWidth
        setNeedsDisplay()
    }

    func setCalibrationOffset(_ value: Float) {
        guard value != calibrationOffset else { return }
        calibrationOffset = value
        writeMappingBuffer()
        setNeedsDisplay()
    }

    func getFrameCount() -> Int { magnitudeHistory.count }
}

// MARK: - SwiftUI Wrapper

struct PlaybackSpectrogramView: UIViewRepresentable {
    var magnitudeHistory: [[Float]]
    /// Bump whenever `magnitudeHistory` content changes but the column count
    /// may not (e.g. weighting switches). Drives texture re-upload.
    var dataVersion: Int = Int.min
    var playheadPosition: Float = 0
    var colormapType: Int
    var viewportStart: Float
    var viewportWidth: Float
    var freqViewportStart: Float = 0
    var freqViewportWidth: Float = 1
    var totalDuration: TimeInterval = 0
    var sampleRate: Float = 44_100
    var viewWidth: CGFloat = 1
    var viewHeight: CGFloat = 1
    var calibrationOffset: Float = 94.0
    var axisKind: SpectrogramHistoryAxisKind = .logSpaced

    func valueAt(viewX: CGFloat, viewY: CGFloat) -> (time: TimeInterval, frequency: Float, magnitude: Float)? {
        guard !magnitudeHistory.isEmpty, viewWidth > 0, viewHeight > 0 else { return nil }
        let xNorm = Float(max(0, min(1, viewX / viewWidth)))
        // y from the bottom of the visible window
        let yLocal = Float(max(0, min(1, 1.0 - (viewY / viewHeight))))
        let timelineNorm = viewportStart + xNorm * viewportWidth
        let clampedTimeline = max(0, min(1, timelineNorm))
        let time = TimeInterval(clampedTimeline) * totalDuration

        // Account for the frequency window: yLocal is relative to the visible
        // window, the axis model expects a global 0…1 frequency fraction.
        let yNorm = max(0, min(1, freqViewportStart + yLocal * freqViewportWidth))

        let columnIndex = min(magnitudeHistory.count - 1, max(0, Int(clampedTimeline * Float(magnitudeHistory.count - 1))))
        let column = magnitudeHistory[columnIndex]
        guard !column.isEmpty else { return nil }

        let binCount = column.count
        let frequency = SpectrogramHistoryAxis.frequency(
            yNorm: yNorm,
            kind: axisKind,
            binCount: binCount,
            sampleRate: Double(sampleRate)
        )
        let binIndex = SpectrogramHistoryAxis.binIndex(
            yNorm: yNorm,
            kind: axisKind,
            binCount: binCount,
            sampleRate: Double(sampleRate)
        )
        let magnitude = column[binIndex]

        return (time: time, frequency: frequency, magnitude: magnitude)
    }

    func makeUIView(context: Context) -> PlaybackSpectrogramRenderer {
        let view = PlaybackSpectrogramRenderer(
            frame: .zero,
            device: MetalWidgetManager.shared.sharedDevice
        )
        view.setColormap(colormapType)
        view.setCalibrationOffset(calibrationOffset)
        view.setViewport(start: viewportStart, width: viewportWidth, freqStart: freqViewportStart, freqWidth: freqViewportWidth)
        if !magnitudeHistory.isEmpty {
            view.loadSpectrogramData(magnitudeHistory, version: dataVersion)
        }
        return view
    }

    func updateUIView(_ uiView: PlaybackSpectrogramRenderer, context: Context) {
        uiView.setColormap(colormapType)
        uiView.setCalibrationOffset(calibrationOffset)
        uiView.setViewport(start: viewportStart, width: viewportWidth, freqStart: freqViewportStart, freqWidth: freqViewportWidth)

        let needsReload = !magnitudeHistory.isEmpty &&
            (uiView.dataVersion != dataVersion || uiView.getFrameCount() != magnitudeHistory.count)
        if needsReload {
            uiView.loadSpectrogramData(magnitudeHistory, version: dataVersion)
        }
    }
}

// `ScrollableSpectrogramView` and `GyroscopeScrollManager` were removed once
// `NavigableSpectrogramView` replaced the recording-playback spectrogram. The
// live-window/gyro-scroll behaviour they provided is superseded by the
// navigable viewport (pinch/pan/seek + minimap).
