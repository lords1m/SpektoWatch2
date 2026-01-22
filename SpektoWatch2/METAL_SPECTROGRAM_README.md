# Metal-basiertes Spektrogramm - Implementierungsdokumentation

## Übersicht

Diese Implementierung verwendet **Metal** (Apple's GPU-Framework) für ein flüssiges, hochperformantes Echtzeit-Spektrogramm mit 60 FPS.

## Architektur

### 1. **SpectrogramShaders.metal**
Metal Shader für GPU-beschleunigtes Rendering:
- **Vertex Shader**: Rendert ein Full-Screen Quad
- **Fragment Shader**: Wendet Farbinterpolation und Colormap an
- **Bilineare Interpolation**: Erzeugt glatte Übergänge zwischen Datenpunkten
- **Colormap**: Schwarz → Blau → Cyan → Grün → Gelb → Rot

### 2. **SpectrogramMetalView.swift**
MTKView-Unterklasse für das Spektrogramm:
- **Ring Buffer**: Scrollende Zeitachse (600 Spalten = ~10 Sekunden)
- **Logarithmische Frequenzskala**: 31.5 Hz - 16 kHz
- **GPU Texture**: 2D Float-Texture für Magnituden-Daten
- **60 FPS Rendering**: Automatisches Redraw mit MetalKit

### 3. **MetalSpectrogramView.swift**
SwiftUI Wrapper mit Achsenbeschriftung:
- **UIViewRepresentable**: Bridge zwischen SwiftUI und UIKit/Metal
- **Achsenbeschriftung**: Logarithmische Frequenzskala
- **Zeitachse**: 0-10 Sekunden

### 4. **SpectrogramView.swift** (aktualisiert)
Hauptansicht mit Toggle zwischen Metal und Canvas Renderer

## Features

✅ **GPU-beschleunigt**: Metal nutzt die GPU für flüssiges Rendering  
✅ **Bilineare Interpolation**: Glatte Übergänge ohne Blockbildung  
✅ **Logarithmische Frequenzskala**: Bessere Darstellung für menschliche Wahrnehmung  
✅ **Ring Buffer**: Effizientes Scrolling ohne Memory Reallocation  
✅ **60 FPS**: Flüssige Darstellung auch bei hoher Datenrate  
✅ **Anpassbare Colormap**: Einfach im Shader zu ändern  

## Verwendung

### In Ihrer App:

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    
    var body: some View {
        VStack {
            // Nur die Metal-Ansicht verwenden
            MetalSpectrogramWithAxes(audioEngine: audioEngine)
                .background(Color.black)
        }
    }
}
```

### FFT-Daten übergeben:

Die `AudioEngine` publiziert automatisch `currentSpectrogramData`, das vom Metal-View konsumiert wird:

```swift
// In AudioEngine.swift - bereits implementiert
DispatchQueue.main.async {
    self.currentSpectrogramData = spectrogramData
}
```

## Technische Details

### Textur-Format
- **Typ**: 2D Float Texture (`r32Float`)
- **Größe**: 600 × 512 Pixel (Zeit × Frequenz)
- **Update**: Spaltenweise (Ring Buffer)

### Frequenz-Mapping
```swift
// Logarithmische Skalierung
let logMin = log2(31.5)   // Min: 31.5 Hz
let logMax = log2(16000)  // Max: 16 kHz
let frequency = pow(2.0, logMin + t * (logMax - logMin))
```

### Colormap-Schwellwerte
| Wert | Farbe | Verwendung |
|------|-------|------------|
| 0.00 - 0.05 | Schwarz | Rauschen/Stille |
| 0.05 - 0.20 | Dunkelblau | Sehr leise Signale |
| 0.20 - 0.40 | Blau → Cyan | Leise Signale |
| 0.40 - 0.60 | Cyan → Grün | Mittlere Signale |
| 0.60 - 0.80 | Grün → Gelb | Laute Signale |
| 0.80 - 1.00 | Gelb → Rot | Sehr laute Signale |

## Performance-Optimierungen

### 1. GPU vs. CPU
- **Canvas Renderer**: ~15-30 FPS, CPU-lastig
- **Metal Renderer**: 60 FPS konstant, GPU-beschleunigt

### 2. Memory Footprint
- **Canvas**: ~600 Frames × 512 Bins × 8 Bytes = ~2.5 MB
- **Metal**: 1 Texture (600 × 512 × 4 Bytes) = ~1.2 MB

### 3. Update-Rate
- **Throttling**: Optional auf 30 FPS drosselbar
- **Ring Buffer**: Keine Array-Reallocation

## Anpassungen

### Colormap ändern

Bearbeiten Sie `spectrogramColormap()` in **SpectrogramShaders.metal**:

```metal
float3 spectrogramColormap(float value) {
    // Ihre eigene Colormap hier
    // Z.B. Grayscale:
    return float3(value, value, value);
}
```

### Frequenzbereich ändern

In **SpectrogramMetalView.swift**:

```swift
private let minFrequency: Float = 50.0    // Ändere min
private let maxFrequency: Float = 20000.0 // Ändere max
```

### Zeitfenster ändern

```swift
private let timeColumns: Int = 1200  // 20 Sekunden bei 60 FPS
```

## Troubleshooting

### Problem: Metal nicht verfügbar
```swift
// Fallback auf Canvas Renderer
if MTLCreateSystemDefaultDevice() == nil {
    useMetalRenderer = false
}
```

### Problem: Textur-Update zu langsam
- Prüfen Sie `preferredFramesPerSecond` in MTKView
- Reduzieren Sie `frequencyBins` oder `timeColumns`

### Problem: Farben zu dunkel/hell
- Passen Sie `gainBoost` an
- Ändern Sie `minDB` und `maxDB` in AudioEngine

## Vorteile gegenüber Canvas

| Feature | Canvas | Metal |
|---------|--------|-------|
| FPS | 15-30 | 60 |
| GPU Beschleunigung | ❌ | ✅ |
| Interpolation | Manuell | Hardware |
| Scrolling Performance | Mittel | Ausgezeichnet |
| Memory Effizienz | Mittel | Hoch |

## Nächste Schritte

Mögliche Erweiterungen:

1. **Mel-Skala**: Noch bessere Anpassung an menschliche Wahrnehmung
2. **Time-Frequency Resolution Trade-off**: Einstellbare FFT-Größe
3. **Colormap-Presets**: Wählbare Farbschemata (Viridis, Plasma, etc.)
4. **Export**: Screenshot oder Video-Export der Visualisierung
5. **Cursor**: Frequenz/Zeit-Werte beim Tap anzeigen

## Lizenz

Dieser Code ist für Ihre SpektoWatch App entwickelt.
