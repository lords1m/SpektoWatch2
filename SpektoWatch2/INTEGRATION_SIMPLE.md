# Einfache Integration: HighEndSpectrogramView in SpektroWatch

## Problem

- `AudioEngine` berechnet bereits FFT und sendet `SpectrogramData` (Magnitudes)
- `HighEndSpectrogramView` erwartet rohe Audio-Samples und macht selbst FFT
- → Wir brauchen einen Adapter!

## Lösung 1: AudioEngine anpassen (Empfohlen)

### Schritt 1: AudioEngine erweitern

Füge in `AudioEngine.swift` eine neue Published-Property hinzu:

```swift
@Published var currentRawAudioSamples: [Float]?
```

### Schritt 2: Im Audio-Tap rohe Samples publishen

In der Funktion wo Audio verarbeitet wird, BEVOR FFT:

```swift
// Irgendwo in AudioEngine.swift, in installTap:
let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

// NEU: Publishe rohe Samples
DispatchQueue.main.async {
    self.currentRawAudioSamples = samples
}

// Dann weiter mit FFT wie bisher...
```

### Schritt 3: In HighEndSpectrogramIntegration.swift connecten

```swift
private func setupAudioSubscription(view: HighEndSpectrogramView) {
    cancellable = audioEngine.$currentRawAudioSamples
        .compactMap { $0 }
        .sink { samples in
            // Gain boost anwenden
            let boosted = samples.map { $0 * self.audioEngine.gainBoost }
            view.processAudioSamples(boosted)
        }
}
```

### Schritt 4: SpectrogramView.swift ändern

Zeile 87 ändern:

```swift
// VORHER:
MetalSpectrogramWithAxes(audioEngine: audioEngine)

// NACHHER:
HighEndSpectrogramWithAxes(audioEngine: audioEngine)
```

---

## Lösung 2: Hybri d-Ansatz (Schneller)

Nutze die existierenden FFT-Magnitudes von AudioEngine, aber mit den neuen Shadern.

### Vorteile:
- Kein doppeltes FFT (schneller)
- Weniger Code-Änderungen
- Funktioniert sofort

### Nachteile:
- Keine Zero-Padding (niedrigere Frequenz-Auflösung)
- Nutzt nicht das volle Potential von HighEndSpectrogramView

### Implementation:

Erstelle `HighEndSpectrogramAdap ter.swift`:

```swift
import MetalKit
import Accelerate

/// Adapter that uses HighEndSpectrogramShaders.metal
/// but accepts pre-computed FFT magnitudes from AudioEngine
class HighEndSpectrogramAdapter: MTKView {

    // Metal resources
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer!
    private var paramsBuffer: MTLBuffer!

    // Texture
    private var spectrogramTexture: MTLTexture!
    private var currentColumn: Int = 0

    // Configuration
    private let frequencyBins: Int = 1024  // Higher than AudioEngine's output
    private let timeColumns: Int = 1200

    private let sampleRate: Float = 44100.0
    private let minFrequency: Float = 20.0
    private let maxFrequency: Float = 20000.0
    private let minDB: Float = -120.0
    private let maxDB: Float = -20.0

    // Display Parameters (mit Bugfixes!)
    var colormapType: Int = 0
    var noiseFloor: Float = -100.0
    var kneeWidth: Float = 15.0
    var gamma: Float = 0.5
    var useInterpolation: Bool = true

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
            fatalError("Metal not supported")
        }

        self.framebufferOnly = false
        self.enableSetNeedsDisplay = false
        self.isPaused = false
        self.preferredFramesPerSecond = 60
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        commandQueue = device.makeCommandQueue()

        // Use HighEndSpectrogramShaders.metal!
        setupPipeline()
        setupGeometry()
        setupTexture()
        setupParametersBuffer()
    }

    private func setupPipeline() {
        guard let device = device,
              let library = device.makeDefaultLibrary() else {
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

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create render pipeline: \(error)")
        }
    }

    private func setupGeometry() {
        guard let device = device else { return }

        let vertices: [Float] = [
            -1.0, -1.0,  0.0, 1.0,
             1.0, -1.0,  1.0, 1.0,
            -1.0,  1.0,  0.0, 0.0,
             1.0,  1.0,  1.0, 0.0
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
            fftSize: Int32(4096),  // AudioEngine's FFT size
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
            length: MemoryLayout<ShaderParams>.stride,
            options: .storageModeShared
        )
    }

    // PUBLIC API: Accept pre-computed FFT magnitudes from AudioEngine
    func updateWithFFTMagnitudes(_ magnitudes: [Float]) {
        guard let texture = spectrogramTexture else { return }

        // Resample to texture resolution
        var columnData = [Float](repeating: 0.0, count: frequencyBins)

        for i in 0..<frequencyBins {
            let fftIndex = Int(Float(i) / Float(frequencyBins) * Float(magnitudes.count))
            columnData[i] = magnitudes[min(fftIndex, magnitudes.count - 1)]
        }

        // Reverse for proper orientation
        columnData.reverse()

        // Write column
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

        currentColumn = (currentColumn + 1) % timeColumns

        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let drawable = currentDrawable,
              let renderPassDescriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else { return }

        // Update params
        var params = ShaderParams(
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
            length: MemoryLayout<ShaderParams>.stride,
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
}
```

Dann erstelle einen SwiftUI Wrapper und verwende ihn:

```swift
struct HighEndSpectrogramAdapterView: UIViewRepresentable {
    @ObservedObject var audioEngine: AudioEngine

    func makeUIView(context: Context) -> HighEndSpectrogramAdapter {
        let view = HighEndSpectrogramAdapter(frame: .zero, device: MTLCreateSystemDefaultDevice())
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: HighEndSpectrogramAdapter, context: Context) {}

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
                    self?.view?.updateWithFFTMagnitudes(data.magnitudes)
                }
        }
    }
}
```

---

## Empfehlung

**Lösung 2 (Hybrid)** ist schneller zu implementieren und nutzt bereits die Bugfixes aus den Shadern!

Die Zero-Padding-Optimierung kannst du später noch in AudioEngine einbauen.

**Nächste Schritte:**

1. Erstelle `HighEndSpectrogramAdapter.swift` (Code oben kopieren)
2. In `SpectrogramView.swift` Zeile 87 ändern:
   ```swift
   HighEndSpectrogramAdapterView(audioEngine: audioEngine)
   ```
3. Build & Test!

Das sollte sofort funktionieren und die Bugs (Übersättigung, Interpolation) beheben!
