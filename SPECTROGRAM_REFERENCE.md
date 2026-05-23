# Spectrogram Reference — HighEndSpectrogramAdapter

Stand: 2026-05 (FFT-Messpfad + DCT-Visualpfad)  
Renderer: `HighEndSpectrogramAdapter` + `HighEndSpectrogramShaders.metal`

---

## Architektur-Überblick

```
AVAudioInputNode Tap (PCM Float)
        │
        ▼
AudioEngine.processFFTFrame(...)
        │
        ├──▶ FFTProcessor (Messpfad)
        │         │  4096 samples, konfigurierbares Window
        │         │  vDSP DFT → 2048 Bins (linear in Hz)
        │         ▼
        │    SpectrogramData (magnitudes[], frequencies[])
        │         │  für Pegel, Terz/Oktav, Recording-Messdaten
        │
        ├──▶ VisualSpectrogramProcessor (Visualpfad, Apple-Sample)
        │         │  gleiches Zeitfenster (Hann)
        │         │  vDSP DCT-II → |.| → 2/N Skalierung
        │         │  → MelSpectrogramProcessor (128 Bänder, 20 Hz – 20 kHz)
        │         │  → 20·log10 → +Kalibrierungsoffset
        │         ▼
        │    SpectrogramData (visualMagnitudes[128], visualFrequencies[128])
        │         │  Mel-Bandzentren in Hz, monoton steigend
        │
        ▼
HighEndSpectrogramAdapter
        │  empfängt SpectrogramData via spectrogramSubject
        │  bevorzugt visualMagnitudes[]; Fallback auf magnitudes[]
        │  bei vorhandenem visualFrequencies[] wird die Frequenzachse
        │  daraus interpoliert (keine zweite Log-Mapping-Stufe);
        │  ohne Frequenzen-Array: lineare 0…Nyquist Annahme.
        ▼
Metal Texture (Ring Buffer, 1200×1024, R32Float)
  – eine Spalte pro Audiofenster schreiben (O(height), nicht O(width×height))
        │
        ▼
HighEndSpectrogramShaders.metal (GPU @ 60 FPS)
  1. Ring-Buffer-Scroll-Mapping
  2. Logarithmische Frequenzachse (20 Hz – 20 kHz)
  3. Bilineare Textur-Interpolation (4 Texel)
  4. dB-Konversion + Soft-Knee Noise Gate
  5. Gamma-Korrektur
  6. Colormap (Turbo / Jet / Viridis)
  7. Ring-Buffer Fade (Anti-Aliasing am Schreibkopf)
        │
        ▼
Display (60 FPS)
```

> **Wichtig:** Messungen bleiben FFT-basiert. Spectrogramm, Wasserfall,
> Recording-Detail und Export verwenden DCT-Daten aus den `visual*`-Feldern.

---

## Konfigurationsparameter

### Messpfad: FFT (in AudioEngine / FFTProcessor)

| Parameter | Wert | Bedeutung |
|-----------|------|-----------|
| `fftSize` | 4096 | Tatsächliche Audio-Samples pro Fenster |
| `binCount` | 2048 | Ausgabebins der reellen FFT (`fftSize / 2`) |
| `hopSize` | 512 | Sliding-Window-Schritt (87,5 % Overlap) |
| Window | konfigurierbar, Hann als Default | Reduziert Spectral Leakage |
| **FFT-Rate** | **≈ 86 /s** | 44100 Hz ÷ 512 |

### Visualpfad: DCT + Mel (in AudioEngine / VisualSpectrogramProcessor)

| Parameter | Wert | Bedeutung |
|-----------|------|-----------|
| `transformSize` | entspricht `fftSize` (4096) | Gleiches Zeitfenster wie Messpfad |
| Transform | vDSP DCT-II | Real-only Darstellungsspektrum |
| `melBandCount` | 128 | Mel-Filterbank zwischen DCT und log10 |
| `frequencyRange` | 20 Hz … 20 kHz | Mel-Eckpunkte (Apple-Sample-Konvention) |
| dB-Konversion | `20·log10` + Kalibrierungs-Offset | Anschluss an dB SPL |
| Ausgabe | `visualMagnitudes[128]`, `visualFrequencies[128]` | Nur für Spectrogramm/Wasserfall/Export |
| Messdaten | unverändert FFT | Keine DCT-/Mel-Werte für Pegel oder Terzbänder |
| Legacy-Modus | `melBandCount = 0` | Pass-through: lineare DCT-Bins (Debug/Tests) |

### Texture (in HighEndSpectrogramAdapter)

| Parameter | Wert | Bedeutung |
|-----------|------|-----------|
| `frequencyBins` | 1024 | Vertikale Texturauflösung (Frequenzachse) |
| `timeColumns` | 1200 | Horizontale Texturauflösung |
| `pixelFormat` | `.r32Float` | 32-bit Float, Single Channel |
| **Texture-Größe** | **≈ 4,8 MB** | 1200 × 1024 × 4 Bytes |
| **Zeithistorie** | **≈ 14 s** | 1200 ÷ 86 Updates/s |

### Display-Parameter (zur Laufzeit anpassbar)

| Parameter | Default | Bereich | Effekt |
|-----------|---------|---------|--------|
| `noiseFloor` | −90 dB | −110 … −60 | Schwellwert für Noise Gate |
| `kneeWidth` | 10 dB | 0 … 20 | Weichheit des Gate-Übergangs |
| `gamma` | 0,7 | 0,1 … 2,0 | Helligkeitskurve |
| `useInterpolation` | `true` | Bool | Bilineare vs. Nearest-Neighbor |
| `colormapType` | 0 (Turbo) | 0 / 1 / 2 | Farbpalette |

---

## Die 7 Optimierungen — Was & Warum

### 1. Getrennter FFT-/DCT+Mel-Pfad

**Code:** `AudioEngine`, `FFTProcessor`, `VisualSpectrogramProcessor`, `MelSpectrogramProcessor`

Der Live-Pfad nutzt die FFT weiter als Messquelle. Parallel dazu berechnet der Visualpfad nach dem Apple-Sample "Visualizing Sound as an Audio Spectrogram":

1. **Hann-Fenster** auf 4096 Audio-Samples
2. **vDSP DCT-II** → 4096 reelle Koeffizienten
3. **|.| + 2/N Skalierung** → lineare Magnituden (Δf ≈ 5,4 Hz)
4. **Mel-Filterbank** (128 Bänder, 20 Hz – 20 kHz, dreieckige Filter) via `cblas_sgemv`
5. **20·log10** → Mel-dB
6. **+ Kalibrierungs-Offset** → dB SPL

Vergleich der Bin-Dichte:

```
FFT-Messpfad : 4096 Samples → 2048 Bins, Δf ≈ 10,8 Hz, linear in Hz
DCT-Visual   : 4096 Samples → 4096 Bins, Δf ≈  5,4 Hz, linear in Hz (Zwischenstufe)
Mel-Output   : 128 Bänder zwischen 20 Hz – 20 kHz, perzeptuell log-skaliert
```

Mel-Bandzentren werden mit `MelSpectrogramProcessor.melToFrequency()` berechnet und als `visualFrequencies` an `HighEndSpectrogramAdapter` durchgereicht. Der Adapter erkennt das Array über `inputFrequencies:` und nutzt es für sein Frequenz-Mapping, statt erneut eine lineare 0…Nyquist Annahme zu machen. Dadurch entfällt die frühere Doppel-Log-Verzerrung.

**Rechenaufwand:** Messungen lesen nur die FFT. Visuals lesen bevorzugt `visualMagnitudes`; Messwerte, Terzbänder und gespeicherte Measurement-Frames bleiben FFT-basiert. Die zusätzliche Mel-Multiplikation auf 4096 → 128 Bins kostet ~50 µs pro Frame (BLAS-optimiert) und ist gegenüber der DCT-Last vernachlässigbar.

---

### 2. Bilineare Interpolation

**Code:** `sampleBilinear()`, `HighEndSpectrogramShaders.metal:136–167`

Statt des nächsten Texels werden 4 Nachbarn gewichtet gemittelt:

```metal
float2 fract = pixelCoord - floor(pixelCoord);
float v0 = mix(v00, v10, fract.x);
float v1 = mix(v01, v11, fract.x);
return mix(v0, v1, fract.y);
```

**Ergebnis:** Glatte Farbverläufe, kein Treppeneffekt, professioneller Look.  
**GPU-Kosten:** +40 % (von ~20 % auf ~28 %), akzeptabel für den Qualitätsgewinn.

---

### 3. Noise Gate mit Soft-Knee

**Code:** `applyNoiseGate()`, `HighEndSpectrogramShaders.metal:95–113`

Ein harter Schwellwert würde Atem-Artefakte erzeugen. Stattdessen wird eine kubische S-Kurve (Smoothstep) über den Knee-Bereich gelegt:

```
dB < noiseFloor              → output = 0
noiseFloor ≤ dB < floor+knee → output = smoothstep(t) × dB   (Übergang)
dB ≥ noiseFloor + knee       → output = dB                   (pass-through)
```

**Ergebnis:** Stilles Hintergrundfeld ist dunkelblau/schwarz statt grünlich.  
**Einstellung:** `noiseFloor` kalibrieren, bis der Hintergrund bei Stille dunkel ist.

---

### 4. Gamma-Korrektur

**Code:** `HighEndSpectrogramShaders.metal:240`

```metal
normalizedValue = pow(normalizedValue, params.gamma);
```

| Gamma | Effekt |
|-------|--------|
| 0,5 | Leise Details werden stark aufgehellt (wissenschaftlich) |
| 0,7 | Ausgewogen — leise und laute Teile sichtbar (Standard) |
| 1,0 | Linear |
| 1,5 | Nur laute Peaks hervorgehoben |

**Praxis:** Bei Musik mit breiter Dynamik (Klassik) auf 0,6, bei komprimierter Musik (Pop/Rock) auf 0,8.

---

### 5. Erhöhte Texturauflösung

512 → **1024 vertikale Pixel**. Individuelle Obertöne erscheinen als separate Linien statt als verschwommener Block. Doppelter Speicher (~2,5 → ~5 MB), weiterhin vernachlässigbar.

---

### 6. 87,5 % Overlap (hopSize = 512)

| Overlap | hopSize | Updates/s | Erscheinungsbild |
|---------|---------|-----------|------------------|
| 75 % | 1024 | ~43 | Sichtbare Spalten-Schritte |
| **87,5 %** | **512** | **~86** | **Flüssig, keine Artefakte** |

Doppelt so viele Updates bei gleichem Audiofenster — flüssiges horizontales Scrollen ohne sichtbare Zeitdiskontinuitäten.

---

### 7. Ring-Buffer Anti-Aliasing am Schreibkopf

Ohne Fade sieht man einen harten Übergang zwischen alter und neuer Textur-Spalte. Der Shader blendet nahe dem aktuellen Schreibkopf linear aus:

```metal
float distToHead = abs(texX - scrollOffset);
if (distToHead < fadeWidth) {
    color *= distToHead / fadeWidth;
}
```

**Ergebnis:** Kein sichtbarer Schnitt beim Textur-Wrap.

---

## Performance

### Profil (iPhone 12, Release-Build, Szenario S2 Live)

| Ressource | Wert | Grenzwert (Budget) |
|-----------|------|--------------------|
| CPU (App) | ~12 % | ≤ 15 % ✅ |
| GPU | ~28 % | ≤ 35 % ✅ |
| Memory (RSS) | ~150 MB | ≤ 150 MB ✅ |
| Frame Rate | 60 FPS stabil | ≥ 58 FPS ✅ |
| Audio-Latenz | ~35–40 ms | ≤ 120 ms p95 ✅ |

**CPU-Breakdown:**
```
FFT-Berechnung (vDSP):  ~9 %
Texture-Upload:         ~2 %
Buffer-Management:      ~1 %
```

**GPU-Breakdown:**
```
Bilineare Textur-Samples:  ~12 %
Log-Frequenz-Mapping:       ~4 %
dB-Konversion + Gate:       ~2 %
Colormap (Turbo-Polynom):   ~3 %
Texture-Upload:             ~6 %
Sonstiges:                  ~1 %
```

### Performance-Stellschrauben (falls nötig)

```swift
// Weniger CPU: hopSize verdoppeln
hopSize = 1024          // ~43 Updates/s, leicht ruckeliger

// Weniger GPU: Interpolation deaktivieren
useInterpolation = false // spart ~5 % GPU, leicht blockiger

// Weniger Memory: Historienbreite halbieren
timeColumns = 600        // ~7 s statt ~14 s, 2,4 MB Textur

// Weniger Frequenzauflösung (ältere Geräte):
frequencyBins = 512      // halbiert Textur-Höhe, −40 % GPU
```

---

## Colormaps

| Typ | Kennung | Eigenschaften |
|-----|---------|---------------|
| **Turbo** | `0` (Standard) | Perceptually uniform, hoher Kontrast, Google Research |
| Jet | `1` | Klassisch (Matlab-Stil), nicht perceptually uniform |
| Viridis | `2` | Farbenblind-sicher, druckbar in Graustufen, geringer Kontrast |

**Empfehlung:** Turbo für Produktion, Viridis für Accessibility/wissenschaftliche Publikationen.

---

## Kalibrierung (5 Minuten)

### Schritt 1 — Noise Floor

1. App starten, kein Audio abspielen
2. Hintergrundfarbe beobachten — grünlich = Noise Floor zu niedrig
3. `noiseFloor` in 5-dB-Schritten erhöhen (-95 → -90 → -85)
4. Stoppen wenn Hintergrund dunkelblau/schwarz
5. Mit leisem Audio testen — sollte noch sichtbar sein

**Typische Werte:** −88 bis −92 dB

---

### Schritt 2 — Gamma

1. Repräsentatives Audio abspielen (Musik oder Sprache)
2. Standard `gamma = 0.7`
3. Leise Teile nicht sichtbar? → Gamma auf 0,6 senken
4. Nur laute Teile interessant? → Gamma auf 0,9 erhöhen

---

### Presets nach Anwendungsfall

```swift
// Musik (ausgewogen)
setNoiseFloor(-90.0); setKneeWidth(10.0); setGamma(0.7); setColormap(0)

// Klassik (große Dynamik)
setNoiseFloor(-92.0); setKneeWidth(12.0); setGamma(0.6); setColormap(0)

// Live-Mikrofon (aggressives Gate)
setNoiseFloor(-80.0); setKneeWidth(8.0);  setGamma(0.8); setColormap(0)

// Sprachaufnahme
setNoiseFloor(-85.0); setKneeWidth(12.0); setGamma(0.65); setColormap(0)

// Wissenschaft (maximales Detail)
setNoiseFloor(-95.0); setKneeWidth(15.0); setGamma(0.5);  setColormap(2)

// Ältere Geräte (Performance-Modus)
setNoiseFloor(-85.0); setInterpolation(false)
// + frequencyBins=512, hopSize=1024 in Adapter-Init
```

---

## Troubleshooting

| Symptom | Ursache | Lösung |
|---------|---------|--------|
| Hintergrund grün/cyan | `noiseFloor` zu niedrig | `setNoiseFloor(-85)` oder höher |
| Leise Töne abgeschnitten | `noiseFloor` zu hoch | `setNoiseFloor(-95)` oder `kneeWidth` erhöhen |
| Alles rot/orange | `gamma` zu hoch oder dB-Range falsch | `setGamma(0.5)` |
| Alles blau, kaum Farbe | Audio zu leise oder `gamma` zu niedrig | `setGamma(0.8)` |
| Blocky/pixeliert | Interpolation aus | `setInterpolation(true)` |
| App ruckelt | Zu viele Updates | `hopSize=1024`, `frequencyBins=512` |
| Scharfer Schnitt sichtbar | Ring-Buffer-Seam | `fadeWidth` im Shader erhöhen (Zeile ~105) |
| Obertöne verschwommen | `frequencyBins` zu niedrig | Auf 2048 erhöhen (mehr Memory) |

---

## API Reference (`HighEndSpectrogramAdapter`)

```swift
// Haupt-Einstiegspunkt (wird von AudioEngine-Subscription aufgerufen)
func updateWithSpectrogramData(_ data: SpectrogramData)

// Zustand zurücksetzen
func reset()

// Colormap (0=Turbo, 1=Jet, 2=Viridis)
func setColormap(_ type: Int)

// Noise Gate Schwellwert in dB (−110 … −50)
func setNoiseFloor(_ db: Float)

// Soft-Knee-Breite in dB (0 … 20)
func setKneeWidth(_ width: Float)

// Gamma-Korrektur (0,1 … 2,0)
func setGamma(_ value: Float)

// Bilineare Interpolation ein/aus
func setInterpolation(_ enabled: Bool)
```

**SwiftUI-Integration:**
```swift
// Vollansicht mit Achsenbeschriftung
HighEndSpectrogramAdapterWithAxes(
    audioEngine: audioEngine,
    colormapType: 0,
    timeSpan: .seconds10,
    scrollSpeed: .normal,
    isPaused: false,
    freqWeighting: .a,
    sensitivity: 0.0,
    frequencySmoothing: 0.3
)
```

---

## Erweiterte Anpassungen

### Frequenzbereich einschränken

```swift
// Nur Sprachbereich (im Shader oder Adapter)
private let minFrequency: Float = 80.0
private let maxFrequency: Float = 8000.0
```

### Höhere FFT-Auflösung für Messungen

```swift
// Warnung: 2× FFT-Rechenzeit
private let fftSize: Int = 16384  // 8192 Bins
// Sinnvoll nur für wissenschaftliche Präzisionsanalyse
```

### Längere Zeithistorie

```swift
// 30 Sekunden (~8 MB Textur)
private let timeColumns: Int = 2580  // 86 updates/s × 30 s
```

---

## Bekannte Grenzen

**FFT-Latenz (~50 ms):** Die 4096-Sample-Fenstergröße bei 44,1 kHz bedingt eine inhärente Latenz. Für Echtzeit-kritische Anwendungen kann `audioFFTSize = 2048` reduziert werden (halbe Frequenzauflösung).

**Ring-Buffer-Seam:** Ein sehr feiner Übergang am Schreibkopf ist trotz Fade-Out bei manchen Colormaps sichtbar. `fadeWidth` im Shader leicht erhöhen wenn störend.

**Samplerate-Annahme:** Einzelne Textur-/Zeitachsen-Berechnungen rechnen implizit mit 44,1 kHz. Bei abweichender `processingSampleRate` muss `timeColumns` entsprechend angepasst werden (→ `FULLSTACK_UEBERSICHT.md`, Abschnitt 8).

---

## Referenzen

- [Apple: Visualizing Sound as an Audio Spectrogram](https://developer.apple.com/documentation/accelerate/visualizing-sound-as-an-audio-spectrogram) — Referenz-Pipeline (DCT-II → Mel)
- [Turbo Colormap — Google Research](https://ai.googleblog.com/2019/08/turbo-improved-rainbow-colormap-for.html)
- [Apple vDSP / Accelerate](https://developer.apple.com/documentation/accelerate/vdsp)
- [Metal Shading Language Spec](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf)
- Zero-Padding: [dsprelated.com](https://www.dsprelated.com/showarticle/800.php)

---

**Erstellt:** 2026-01-23 (Rendering-Optimierung)  
**Aktualisiert:** 2026-05-06 (Konsolidierung)  
**Ersetzt:** QUICK_START.md, OPTIMIZATION_SUMMARY.md, SPECTROGRAM_OPTIMIZATION_GUIDE.md, TECHNICAL_DETAILS.md
