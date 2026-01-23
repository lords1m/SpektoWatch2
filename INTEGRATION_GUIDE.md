# High-End Spectrogram Integration Guide

## Übersicht

Diese Implementation bietet professionelle Spektrogramm-Qualität mit:

- **4096-Sample FFT** für hohe Frequenzauflösung
- **75% Overlap** (Sliding Window) für flüssige Animation (4x mehr Updates)
- **Logarithmische Frequenzskalierung** im Shader (Mel-Scale ähnlich)
- **Ring Buffer Textur** für effizientes Scrolling
- **Perceptually Uniform Colormaps** (Turbo, Jet, Viridis)
- **GPU-beschleunigtes Rendering** mit Metal

## Dateien

1. **HighEndSpectrogramShaders.metal** - Metal Shader Code
2. **HighEndSpectrogramView.swift** - MTKView Implementation
3. **Integration in bestehende App**

---

## 1. Shader-Features erklärt

### Fragment Shader (`highEndSpectrogramFragmentShader`)

**Horizontales Scrolling (Ring Buffer):**
```metal
float texX = fmod(screenX + params.scrollOffset, 1.0);
```
- `scrollOffset` wird bei jedem neuen FFT-Update inkrementiert
- Kein komplettes Texture-Reupload nötig, nur eine Spalte

**Logarithmische Frequenzskalierung:**
```metal
float texY = linearToLogFrequency(screenY, minFreq, maxFreq, nyquist, fftSize);
```
- Konvertiert lineare Screen-Y-Koordinate zu logarithmischer Frequenz
- Bässe bekommen mehr Platz, Höhen werden komprimiert
- Ähnlich wie Mel-Scale in Audio-Software

**dB-Konversion & Normalisierung:**
```metal
float db = 20.0 * log10(magnitude + epsilon);
float normalized = (db - minDB) / (maxDB - minDB);
```
- Konvertiert lineare FFT-Magnitude zu Dezibel
- Normalisiert auf [0, 1] für Colormap
- Range: -80 dB (schwarz) bis 0 dB (rot)

**Horizontaler Blur:**
```metal
for (int i = 0; i < blurSamples; i++) {
    float offset = (float(i) - float(blurSamples) / 2.0) * pixelWidth;
    magnitude += texture.sample(..., float2(texX + offset, texY)).r;
}
```
- Sampelt mehrere benachbarte Pixel horizontal
- Erzeugt weichere, weniger "blockige" Darstellung

### Colormaps

**Turbo (Empfohlen):**
- Entwickelt von Google Research
- Perceptually uniform (gleichmäßige Wahrnehmung)
- Hoher Kontrast, gut für wissenschaftliche Visualisierung
- Schwarz → Blau → Cyan → Grün → Gelb → Orange → Rot

**Jet (Klassisch):**
- Standard in MATLAB/wissenschaftlicher Software
- Sehr hoher Kontrast
- Blau → Cyan → Grün → Gelb → Rot

**Viridis (Accessible):**
- Farbenblind-freundlich
- Perceptually uniform
- Lila → Blau → Grün → Gelb

---

## 2. Swift Integration

### Sliding Window (75% Overlap)

**Standard-Ansatz (schlecht):**
```swift
// Wartet auf vollen Buffer (4096 Samples)
if buffer.count >= 4096 {
    performFFT(buffer)  // Nur 10 Updates/Sekunde bei 44.1kHz
}
```

**High-End-Ansatz (gut):**
```swift
// Sliding Window mit 75% Overlap
let fftSize = 4096
let hopSize = 1024  // 25% von fftSize

while audioBuffer.count >= fftSize {
    let window = audioBuffer.prefix(fftSize)
    performFFT(Array(window))
    audioBuffer.removeFirst(hopSize)  // Nur 1024 Samples entfernen
}
// Ergebnis: 40 Updates/Sekunde → 4x flüssiger!
```

### Ring Buffer Texture

**Schreiben (CPU → GPU):**
```swift
// Nur eine Spalte schreiben (effizient!)
let region = MTLRegion(
    origin: MTLOrigin(x: currentColumn, y: 0, z: 0),
    size: MTLSize(width: 1, height: frequencyBins, depth: 1)
)
texture.replace(region: region, mipmapLevel: 0, withBytes: columnData, ...)

currentColumn = (currentColumn + 1) % timeColumns
```

**Lesen (GPU):**
```metal
// Shader berechnet korrekten Offset automatisch
float scrollOffset = float(currentColumn) / float(textureWidth);
float texX = fmod(screenX + scrollOffset, 1.0);
```

---

## 3. Integration in deine App

### Option A: Ersetze die bestehende MetalView

**Schritt 1:** In `SpectrogramView.swift`:
```swift
import SwiftUI

struct SpectrogramView: View {
    @StateObject private var audioEngine = AudioEngine()

    var body: some View {
        HighEndSpectrogramViewRepresentable(audioEngine: audioEngine)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HighEndSpectrogramViewRepresentable: UIViewRepresentable {
    @ObservedObject var audioEngine: AudioEngine

    func makeUIView(context: Context) -> HighEndSpectrogramView {
        let view = HighEndSpectrogramView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        return view
    }

    func updateUIView(_ uiView: HighEndSpectrogramView, context: Context) {
        // Audio samples werden direkt über processAudioSamples() geschickt
    }
}
```

**Schritt 2:** In `AudioEngine.swift` - Ändere `processAudioBuffer`:
```swift
private var highEndView: HighEndSpectrogramView?

func setHighEndView(_ view: HighEndSpectrogramView) {
    self.highEndView = view
}

private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
    guard let channelData = buffer.floatChannelData?[0] else { return }

    let frameCount = Int(buffer.frameLength)
    let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

    // Direkt an High-End View senden (mit Sliding Window)
    highEndView?.processAudioSamples(samples)
}
```

### Option B: Parallelbetrieb (für Testing)

Füge einen Toggle hinzu:
```swift
@State private var useHighEndRenderer = false

var body: some View {
    VStack {
        Toggle("High-End Renderer", isOn: $useHighEndRenderer)

        if useHighEndRenderer {
            HighEndSpectrogramViewRepresentable(audioEngine: audioEngine)
        } else {
            MetalSpectrogramWithAxes(audioEngine: audioEngine)
        }
    }
}
```

---

## 4. Parameter-Tuning

### Farbpalette ändern
```swift
highEndView.setColormap(0)  // 0 = Turbo (empfohlen)
highEndView.setColormap(1)  // 1 = Jet (klassisch)
highEndView.setColormap(2)  // 2 = Viridis (accessible)
```

### Horizontal Blur anpassen
```swift
highEndView.setHorizontalBlur(1.0)   // Kein Blur (scharf)
highEndView.setHorizontalBlur(3.0)   // Leichter Blur (Standard)
highEndView.setHorizontalBlur(10.0)  // Starker Blur (weich)
```

### dB-Range anpassen (in ShaderParams)
```swift
// In HighEndSpectrogramView.swift
private let minDB: Float = -80.0  // Noise floor (dunkler)
private let maxDB: Float = 0.0    // Peak (heller)

// Für leisere Signale:
private let minDB: Float = -60.0  // Mehr Kontrast bei leisen Sounds
```

### Frequenz-Range anpassen
```swift
private let minFrequency: Float = 20.0    // Tiefster Bass
private let maxFrequency: Float = 20000.0 // Höchste Frequenz

// Für Musik/Voice (weniger Höhen):
private let minFrequency: Float = 80.0
private let maxFrequency: Float = 8000.0
```

---

## 5. Performance-Optimierung

### CPU-Seite (FFT)
- **FFT-Größe:** 4096 ist ein guter Kompromiss (hohe Auflösung, moderate CPU-Last)
- **Hop Size:** 1024 (75% Overlap) gibt 4x mehr Updates
- **Windowing:** Hann-Window reduziert Spektral Leakage

### GPU-Seite (Rendering)
- **Texture-Format:** `r32Float` (32-bit float, single channel) - optimal für Magnitude-Daten
- **Texture-Größe:** 1200×512 (~2 MB) - 2 Minuten Recording bei 10 Updates/Sek.
- **Ring Buffer:** Nur eine Spalte schreiben statt kompletter Textur → 1200x schneller!

### Wenn Performance-Probleme auftreten:

1. **Reduziere FFT-Größe:**
   ```swift
   private let fftSize: Int = 2048  // Statt 4096
   ```

2. **Reduziere Overlap:**
   ```swift
   private let hopSize: Int = 2048  // 50% Overlap statt 75%
   ```

3. **Reduziere Texture-Auflösung:**
   ```swift
   private let frequencyBins: Int = 256  // Statt 512
   private let timeColumns: Int = 600    // Statt 1200
   ```

4. **Reduziere Horizontal Blur:**
   ```swift
   var horizontalBlur: Float = 1.0  // Kein Blur, schneller
   ```

---

## 6. Erweiterte Features (Optional)

### Color Lookup Table (1D Texture)

Statt algorithmischer Colormap kannst du eine 1D-Texture verwenden:

**Shader:**
```metal
texture1d<float> colormapTexture [[texture(1)]];
float3 color = colormapTexture.sample(sampler, normalizedValue).rgb;
```

**Swift:**
```swift
// Erstelle 1D Texture mit Gradient
let descriptor = MTLTextureDescriptor()
descriptor.textureType = .type1D
descriptor.pixelFormat = .rgba8Unorm
descriptor.width = 256
let colormapTexture = device.makeTexture(descriptor: descriptor)

// Fülle mit Farbwerten (256 Farben von Blau bis Rot)
var colors: [UInt8] = []
for i in 0..<256 {
    let t = Float(i) / 255.0
    let rgb = turboColormap(t)
    colors.append(UInt8(rgb.r * 255))
    colors.append(UInt8(rgb.g * 255))
    colors.append(UInt8(rgb.b * 255))
    colors.append(255)
}
colormapTexture.replace(region: ..., withBytes: colors, ...)
```

### Mel-Scale (statt Log-Scale)

Für noch bessere Bass-Darstellung:

```metal
float linearToMelFrequency(float hz) {
    return 2595.0 * log10(1.0 + hz / 700.0);
}

float melToLinearFrequency(float mel) {
    return 700.0 * (pow(10.0, mel / 2595.0) - 1.0);
}
```

---

## 7. Troubleshooting

**Problem: Spektrogramm ist zu dunkel**
- Erhöhe `minDB` (z.B. von -80 auf -60)
- Oder füge Gain-Verstärkung hinzu vor FFT

**Problem: Spektrogramm ruckelt**
- Reduziere FFT-Größe oder Overlap
- Prüfe ob Audio-Thread blockiert wird
- Nutze `DispatchQueue` für FFT-Berechnung

**Problem: Farben sehen falsch aus**
- Prüfe ob Magnitude → dB Konversion korrekt ist
- Teste andere Colormaps (Jet, Viridis)
- Prüfe minDB/maxDB Range

**Problem: Hohe Frequenzen fehlen**
- Erhöhe `maxFrequency`
- Prüfe FFT-Größe (größer = bessere Frequenzauflösung)

**Problem: Scrolling ist nicht flüssig**
- Erhöhe `hopSize` (weniger Overlap)
- Prüfe ob `preferredFramesPerSecond` zu niedrig ist

---

## 8. Vergleich: Vorher vs. Nachher

### Vorher (Original Implementation)
- ❌ 512 FFT-Größe → geringe Frequenzauflösung
- ❌ Kein Overlap → nur 10 Updates/Sek
- ❌ Linear Frequency Scale → Bässe zu klein
- ❌ Einfache Colormap → wenig Kontrast
- ❌ Komplettes Texture-Upload → ineffizient

### Nachher (High-End Implementation)
- ✅ 4096 FFT-Größe → hohe Frequenzauflösung
- ✅ 75% Overlap → 40 Updates/Sek (4x flüssiger)
- ✅ Logarithmic Frequency Scale → Bässe deutlich sichtbar
- ✅ Turbo Colormap → maximaler Kontrast
- ✅ Ring Buffer → nur eine Spalte schreiben (1200x schneller)

---

## 9. Nächste Schritte

1. **Integriere die neue View** (siehe Option A oder B)
2. **Teste verschiedene Colormaps** und finde deine Favorit
3. **Tune die Parameter** für deine Anwendung (Music vs. Voice)
4. **Optimiere Performance** falls nötig

Viel Erfolg! 🚀
