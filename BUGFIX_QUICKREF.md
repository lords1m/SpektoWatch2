# Bugfix Quick Reference

## 🔴 Problem: Alles ist ROT

### Schnelle Fixes

```swift
// Fix 1: Erweitere dB-Range (schon implementiert)
minDB: -120.0  // vorher: -80.0
maxDB: -20.0   // vorher: 0.0

// Fix 2: Reduziere Gamma (schon implementiert)
gamma: 0.5  // vorher: 0.7

// Fix 3: Noise Floor anpassen (schon implementiert)
noiseFloor: -100.0  // vorher: -90.0
```

**Wenn immer noch zu rot:**
```swift
spectrogramView.setGamma(0.4)  // Noch niedriger
// oder
spectrogramView.maxDB = -15.0  // Höher setzen
```

---

## 📊 Debug-Logging

**Console Output:**
```
📊 FFT dB Range: min=-92.1 avg=-58.3 max=-24.7
```

**Interpretation:**

| Wert | Gut | Warnung |
|------|-----|---------|
| min | < -80 dB | > -70 dB → Noise Floor zu niedrig |
| avg | -65 bis -45 dB | < -70 dB → Audio zu leise |
| max | -35 bis -20 dB | > -10 dB → OK, aber viel Rot |

---

## 🎨 Erwartete Farbverteilung

**Richtig:**
- 50% Blau/Cyan (Stille, leise Bereiche)
- 30% Grün/Gelb (mittlere Lautstärke)
- 20% Orange/Rot (laute Peaks)

**Falsch (vor Bugfix):**
- 10% Blau/Cyan
- 20% Grün/Gelb
- 70% Orange/Rot ❌

---

## 🐛 Debug-Modi

```swift
spectrogramView.setDebugMode(mode)
```

| Mode | Anzeige | Zweck |
|------|---------|-------|
| 0 | Normal | Production |
| 1 | Grayscale | Normalized value direkt sehen |
| 2 | Colormap Test | Horizontal-Gradient 0→1 |
| 3 | Raw Magnitude | Ungefilterte FFT-Werte |

**Test-Procedure:**

1. **Mode 2:** Prüfe Colormap
   - Sollte zeigen: Blau links → Rot rechts
   - Wenn nicht: Colormap ist kaputt

2. **Mode 1:** Prüfe Normalisierung
   - Hintergrund sollte dunkel sein (schwarz/grau)
   - Laute Bereiche sollten weiß sein
   - Wenn alles weiß: Normalisierung falsch

3. **Mode 3:** Prüfe FFT
   - Sollte sehr dunkel sein (FFT-Magnitudes sind klein)
   - Wenn hell: Gain zu hoch

---

## 🔧 Kalibrierungs-Schnellstart

### 1. Teste mit Sinus-Ton (440 Hz)

**Erwartung:**
- Scharfe horizontale Linie bei 440 Hz
- Farbe: **CYAN oder GRÜN** (NICHT rot!)
- Hintergrund: Dunkelblau/Schwarz

**Falls rot:**
```swift
spectrogramView.setGamma(0.4)
```

---

### 2. Teste mit Musik

**Erwartung:**
- Viel Blau/Cyan in Pausen
- Grün/Gelb bei Vocals/Melodie
- Rot nur bei Drum-Hits

**Falls zu viel Rot:**
```swift
// Option A: Niedrigeres Gamma
spectrogramView.setGamma(0.4)

// Option B: Höheres maxDB
// In HighEndSpectrogramView.swift Zeile 48:
private let maxDB: Float = -15.0  // statt -20.0
```

---

### 3. Teste Interpolation

**Erwartung:**
- Smoothe Farbübergänge
- Keine sichtbaren Pixel-Stufen
- Keine horizontalen Streifen

**Falls blocky:**
```swift
// Prüfe ob aktiviert:
print(spectrogramView.useInterpolation)  // sollte true sein

// Falls true aber immer noch blocky:
// Erhöhe Texture-Auflösung in HighEndSpectrogramView.swift Zeile 41:
private let frequencyBins: Int = 2048  // statt 1024
```

---

## 📈 Typische Werte

### Musik (Pop/Rock)

```swift
minDB: -120.0
maxDB: -20.0
noiseFloor: -100.0
gamma: 0.5
```

### Klassik (große Dynamik)

```swift
minDB: -120.0
maxDB: -25.0  // Leiser als Pop
noiseFloor: -105.0
gamma: 0.45  // Noch mehr Detail in leisen Teilen
```

### Live-Mikrofon

```swift
minDB: -110.0
maxDB: -15.0  // Lauter
noiseFloor: -95.0  // Aggressiveres Gate
gamma: 0.55
```

### Voice Recording

```swift
minDB: -115.0
maxDB: -20.0
noiseFloor: -100.0
gamma: 0.5
```

---

## ⚠️ Häufige Fehler

### Fehler 1: "Hintergrund ist grün statt blau"

**Ursache:** Noise Floor zu niedrig

**Fix:**
```swift
spectrogramView.setNoiseFloor(-95.0)  // Höher
```

---

### Fehler 2: "Leise Töne werden abgeschnitten"

**Ursache:** Noise Floor zu hoch

**Fix:**
```swift
spectrogramView.setNoiseFloor(-105.0)  // Niedriger
```

---

### Fehler 3: "Immer noch zu rot"

**Ursache:** maxDB zu niedrig

**Fix:**
```swift
// In HighEndSpectrogramView.swift:
private let maxDB: Float = -10.0  // statt -20.0
```

---

### Fehler 4: "Alles ist blau, kaum Farbe"

**Ursache:** Audio zu leise oder minDB zu hoch

**Fix:**
```swift
// Senke minDB:
private let minDB: Float = -100.0  // statt -120.0

// Oder erhöhe Audio-Gain vor FFT
```

---

## 🎯 Optimale Settings (Empfohlen)

### Standard (schon implementiert)

```swift
// In HighEndSpectrogramView.swift:
private let minDB: Float = -120.0
private let maxDB: Float = -20.0

// Display Parameters:
var noiseFloor: Float = -100.0
var kneeWidth: Float = 15.0
var gamma: Float = 0.5
var useInterpolation: Bool = true
```

**Das sollte für 90% der Anwendungsfälle passen!**

---

## 🔬 Vergleich: Vorher vs. Nachher

### Normalisierung

**Vorher:**
```
Signal @ -40 dB:
normalized = (-40 - (-80)) / (0 - (-80))
          = 40 / 80 = 0.5
→ Turbo Colormap @ 0.5 = GRÜN/GELB (sollte CYAN sein!)
```

**Nachher:**
```
Signal @ -40 dB:
normalized = (-40 - (-120)) / (-20 - (-120))
          = 80 / 100 = 0.8
→ Log-Kompression: log10(1 + 9*0.8) = 0.86
→ Gamma 0.5: pow(0.86, 0.5) = 0.93
→ Turbo Colormap @ 0.93 = GELB/ORANGE ✓
```

---

### Logarithmische Kompression

**Effekt auf Farbverteilung:**

| Input | Ohne Log | Mit Log | Farbe (Turbo) |
|-------|----------|---------|---------------|
| 0.1 | 0.1 | 0.28 | Blau → Cyan ✓ |
| 0.3 | 0.3 | 0.48 | Cyan → Grün ✓ |
| 0.5 | 0.5 | 0.64 | Grün → Gelb ✓ |
| 0.7 | 0.7 | 0.77 | Gelb → Orange ✓ |
| 0.9 | 0.9 | 0.90 | Orange → Rot ✓ |

→ Mehr Spreizung in mittleren Bereichen!

---

## 📞 Support

**Console zeigt keine Logs?**
→ Stelle sicher, dass du im Debug-Build bist

**Debug-Modi funktionieren nicht?**
→ Siehe BUGFIX_GUIDE.md Abschnitt "Troubleshooting"

**Performance Probleme?**
→ Setze `gamma = 0.7` (weniger Berechnung)
→ Oder `useInterpolation = false`

---

**Version:** 2.1
**Date:** 2026-01-23
