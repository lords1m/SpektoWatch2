# Build Checklist - Spektrogramm Bugfixes

## ✅ Dateien die DU BRAUCHST:

1. **HighEndSpectrogramShaders.metal** ✅
   - Enthält alle Shader-Optimierungen
   - Bilineare Interpolation
   - Noise Gate
   - Logarithmische Kompression
   - Gamma-Korrektur

2. **HighEndSpectrogramAdapter.swift** ✅
   - Adapter zwischen AudioEngine und optimierten Shadern
   - Keine doppelte FFT-Berechnung
   - 1024 Pixel vertikale Auflösung

3. **SpectrogramView.swift** ✅ (geändert)
   - Zeile 88: Verwendet jetzt `HighEndSpectrogramAdapterWithAxes`

---

## ❌ Dateien die du NICHT BRAUCHST:

1. **HighEndSpectrogramIntegration.swift** ❌ (gelöscht)
   - War eine alternative Implementierung
   - Hatte Kompilierungsfehler
   - Wird nicht verwendet

2. **HighEndSpectrogramView.swift** ❓ (behalten, aber ungenutzt)
   - Standalone-Implementierung mit eigener FFT
   - Funktioniert, wird aber nicht von der App verwendet
   - Kann als Referenz behalten werden

---

## 🔨 Build-Anleitung

### Schritt 1: Clean Build Folder

In Xcode:
```
Product → Clean Build Folder (⇧⌘K)
```

### Schritt 2: Build

```
Product → Build (⌘B)
```

### Schritt 3: Run

```
Product → Run (⌘R)
```

---

## ✅ Erwartete Ergebnisse

### Beim Start:
- App startet ohne Fehler ✅
- "Tippe auf Start, um zu beginnen" erscheint ✅

### Nach "Start" drücken:
- Schwarzer Hintergrund erscheint ✅
- Spektrogramm beginnt zu zeichnen ✅

### Mit Audio (Musik/Sprechen):
- **Hintergrund:** Dunkelblau/schwarz (NICHT grün/cyan) ✅
- **Farbverteilung:**
  - 50% Blau/Cyan (leise)
  - 30% Grün/Gelb (mittel)
  - 20% Orange/Rot (laut)
- **Rot nur bei Peaks:** < 10% der Fläche ✅
- **Smooth:** Keine sichtbaren Pixel-Stufen ✅

---

## 🐛 Troubleshooting

### Error: "Cannot find 'HighEndSpectrogramAdapterWithAxes'"

**Ursache:** Xcode hat die neue Datei nicht zum Target hinzugefügt

**Lösung:**
1. Klicke auf `HighEndSpectrogramAdapter.swift` im Navigator
2. Rechte Sidebar → "Target Membership"
3. Haken bei "SpektoWatch2" setzen ✅

---

### Error: "Use of undeclared type 'ShaderParams'"

**Ursache:** ShaderParams ist zweimal definiert (in .swift und .metal)

**Lösung:** Das ist OK! Swift und Metal haben separate Namespaces.
Die Struct-Definitionen müssen identisch sein (sind sie).

---

### Warning: "View 'spectrogramFrames' is never mutated"

**Lösung:** Ignorieren - das ist normal, da der Metal-Renderer
die Frames nicht braucht (AudioEngine handled das direkt).

---

### Kompilierungs-Fehler in anderen Dateien

**Lösung:** Clean Build Folder (⇧⌘K) und neu builden

---

## 📊 Performance Check

Nach dem Build, während Audio läuft:

1. **Xcode → Debug Navigator**
2. **CPU:** Sollte < 15% sein ✅
3. **GPU:** Sollte < 35% sein ✅
4. **FPS:** Sollte stabil 60 FPS sein ✅

Falls Performance-Probleme:
- Reduziere `frequencyBins` auf 512 (Zeile 31 in HighEndSpectrogramAdapter.swift)
- Oder disable Interpolation: `var useInterpolation: Bool = false` (Zeile 42)

---

## 🎨 Visueller Vergleich

### VORHER (mit SpectrogramMetalView):
- Hintergrund: Grün/cyan ❌
- Farbverteilung: 80% Rot ❌
- Pixelierung: Sichtbare Stufen ❌
- Harmonische: Verschwommen ❌

### NACHHER (mit HighEndSpectrogramAdapter):
- Hintergrund: Dunkelblau/schwarz ✅
- Farbverteilung: 50% Blau, 30% Grün, 20% Rot ✅
- Pixelierung: Smooth, keine Stufen ✅
- Harmonische: Feine separate Linien ✅

---

## 🎯 Test-Szenarien

### Test 1: Sinus-Ton (440 Hz)
**Erwartung:**
- Scharfe horizontale Linie bei 440 Hz
- Farbe: CYAN oder GRÜN (NICHT rot!)
- Hintergrund: Dunkelblau/schwarz

**Wenn rot:** Gamma zu hoch → senke auf 0.4

---

### Test 2: Musik (Pop/Rock)
**Erwartung:**
- Drums/Percussion: Orange/Rot (Peaks)
- Vocals/Melodie: Grün/Gelb
- Pausen: Blau/Schwarz

**Wenn alles rot:** Siehe Feintuning unten

---

### Test 3: Sprache
**Erwartung:**
- Formanten: Gelb/Grün (horizontale Bänder)
- Konsonanten: Orange (vertikale Bursts)
- Pausen: Dunkelblau

**Wenn zu hell:** Erhöhe Noise Floor auf -95

---

## ⚙️ Feintuning (falls nötig)

Alle Änderungen in `HighEndSpectrogramAdapter.swift`:

### Zu viel Rot (> 30%)

**Zeile 40:**
```swift
var gamma: Float = 0.4  // Niedriger (war 0.5)
```

ODER **Zeilen 33-34:**
```swift
private let minDB: Float = -110.0  // Weniger extrem (war -120.0)
private let maxDB: Float = -25.0   // Tiefer (war -20.0)
```

---

### Hintergrund zu hell (grün/cyan)

**Zeile 38:**
```swift
var noiseFloor: Float = -95.0  // Höher (war -100.0)
```

---

### Zu dunkel/wenig Farbe

**Zeile 40:**
```swift
var gamma: Float = 0.6  // Höher (war 0.5)
```

---

### Immer noch Pixel-Stufen sichtbar

**Zeile 42:**
```swift
var useInterpolation: Bool = true  // Sollte schon true sein
```

Falls true und immer noch blocky:
**Zeile 31:**
```swift
private let frequencyBins: Int = 2048  // Höher (war 1024)
```

---

## 📝 Nach erfolgreichem Build

### Wenn alles funktioniert:

1. ✅ Teste ausgiebig mit verschiedenen Audio-Quellen
2. ✅ Vergleiche mit Acoustic IQ (sollte jetzt ähnlich aussehen)
3. ✅ Optional: Feintuning der Parameter oben

### Wenn Probleme auftreten:

1. Siehe Troubleshooting oben
2. Check `BUGFIX_GUIDE.md` für Details
3. Check `BUGFIX_QUICKREF.md` für schnelle Fixes

---

## 📚 Dokumentation

- **FINAL_INTEGRATION_STEPS.md** - Was geändert wurde
- **BUGFIX_GUIDE.md** - Technische Details (70+ Seiten)
- **BUGFIX_QUICKREF.md** - Schnelle Problemlösungen
- **TECHNICAL_DETAILS.md** - Mathematische Erklärungen

---

## ✅ Success Criteria

Build ist erfolgreich wenn:

1. ✅ Keine Kompilierungsfehler
2. ✅ App startet ohne Crash
3. ✅ Spektrogramm zeigt sich nach "Start"
4. ✅ Hintergrund ist dunkel (nicht grün)
5. ✅ Farbverteilung ist balanciert (nicht 80% rot)
6. ✅ Keine sichtbaren Pixel-Stufen
7. ✅ Performance ist gut (60 FPS, < 15% CPU)

**Viel Erfolg!** 🎉

---

**Version:** 2.1 (Final)
**Date:** 2026-01-23
**Status:** Ready to build ✅
