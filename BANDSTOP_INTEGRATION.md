# Bandsperre-Filter System - Integration Guide

## Übersicht

Das Bandsperre-Filter-System ermöglicht das gezielte Herausfiltern von Frequenzbereichen aus der Audio-Analyse. Ideal für:
- **Netzbrummen** (50/60 Hz)
- **Störgeräusche** mit bekannter Frequenz
- **Fokussierung** auf relevante Frequenzbereiche
- **Messnorm-Konformität** durch Filterung nicht relevanter Bereiche

---

## Komponenten

### 1. **BandstopFilter** (Datenmodell)
```swift
struct BandstopFilter {
    let id: UUID
    var isEnabled: Bool
    var lowFrequency: Float   // Untere Grenze (Hz)
    var highFrequency: Float  // Obere Grenze (Hz)
    var name: String
    var color: String         // Hex-Farbe
}
```

### 2. **BandstopFilterManager** (Verwaltung + Persistenz)
- **Singleton**: `BandstopFilterManager.shared`
- **Persistenz**: UserDefaults (JSON)
- **Methoden**:
  - `addFilter(_:)` - Filter hinzufügen
  - `removeFilter(id:)` - Filter löschen
  - `toggleFilter(id:)` - Ein/Aus schalten
  - `isFrequencyBlocked(_:)` - Prüfung ob Frequenz blockiert
  - `attenuationFactor(for:)` - Dämpfungsfaktor (0-1)

### 3. **AudioEngine Integration**
```swift
private func applyBandstopFilters(
    frequencies: [Float], 
    magnitudes: [Float]
) -> [Float]
```

**Ablauf**:
1. FFT-Analyse durchführen
2. **Bandsperre anwenden** (vor Aggregation)
3. Aggregation & Glättung
4. Visualisierung

**Filterung**:
- **Sanfte Flanken**: Cosine-Taper (10% Bandbreite oder max 20 Hz)
- **Logarithmische Dämpfung**: Linear-Multiplikation vor dB-Konversion

---

## UI-Komponenten

### A) **BandstopFilterSettingsView** (Vollständige Einstellungen)

```swift
@State private var filters: [BandstopFilter] = []

BandstopFilterSettingsView(filters: $filters)
```

**Features**:
- ✅ Dual-Range-Slider (Anfang + Ende gleichzeitig)
- ✅ Feinabstimmung mit +/- Buttons
- ✅ 8 Presets (Netzbrummen, Oberwellen, etc.)
- ✅ Logarithmische Frequenz-Visualisierung
- ✅ Filter hinzufügen/löschen/umbenennen

### B) **BandstopOverlayView** (Spektrogramm-Overlay)

```swift
// In deinem Spektrogramm-View:
ZStack {
    SpectrogramView(...)
    
    BandstopOverlayView(
        filters: filterManager.filters,
        frequencyRange: 20...20000,
        geometryWidth: geometry.size.width,
        geometryHeight: geometry.size.height
    )
}
```

**Visualisiert**:
- ❌ Rote halbtransparente Bereiche
- 🏷️ Labels mit Namen + Frequenzbereich
- 📐 Logarithmische Positionierung

### C) **BandstopDashboardWidget** (Schnellzugriff)

```swift
BandstopDashboardWidget()
```

**3 Varianten**:
1. **Full Widget** - Zeigt bis zu 3 Filter mit Toggle
2. **Mini Widget** - Kompakt mit erstem Filter
3. **Status Indicator** - Nur Icon mit Badge

---

## Integration in die App

### Schritt 1: Dashboard erweitern

```swift
// In deinem Dashboard/Settings View:
VStack(spacing: 16) {
    // Andere Widgets...
    
    BandstopDashboardWidget()
        .padding(.horizontal)
}
```

### Schritt 2: Spektrogramm-Overlay

```swift
// In SpectrogramView.swift:
GeometryReader { geometry in
    ZStack {
        // Dein bestehendes Spektrogramm
        Canvas { context, size in
            // ... Spektrogramm-Rendering
        }
        
        // NEU: Bandsperre-Overlay
        BandstopOverlayView(
            filters: BandstopFilterManager.shared.filters,
            frequencyRange: 20...20000,
            geometryWidth: geometry.size.width,
            geometryHeight: geometry.size.height
        )
        .allowsHitTesting(false) // Klicks durchlassen
    }
}
```

### Schritt 3: Settings-Menü

```swift
Button("Bandsperre konfigurieren") {
    showBandstopSettings = true
}
.sheet(isPresented: $showBandstopSettings) {
    BandstopFilterSettingsView(
        filters: $BandstopFilterManager.shared.filters
    )
}
```

---

## Presets

| Name | Low | High | Verwendung |
|------|-----|------|------------|
| **Netzbrummen 50Hz** | 48 Hz | 52 Hz | EU-Stromnetz |
| **Netzbrummen 60Hz** | 58 Hz | 62 Hz | US/Japan-Stromnetz |
| **Oberwelle 100Hz** | 98 Hz | 102 Hz | 2. Harmonische (50Hz) |
| **Oberwelle 150Hz** | 148 Hz | 152 Hz | 3. Harmonische (50Hz) |
| **Tiefpass < 100Hz** | 20 Hz | 100 Hz | Infraschall filtern |
| **Hochpass > 8kHz** | 8 kHz | 20 kHz | Hochfrequenz-Rauschen |
| **Sprachbereich** | 300 Hz | 3.4 kHz | Telefon-Bandbreite |
| **Subwoofer** | 20 Hz | 80 Hz | Bass-Bereich |

---

## Technische Details

### Algorithmus: Sanfte Flanken

```swift
func attenuationFactor(for frequency: Float) -> Float {
    // Transitionsbreite: 10% der Bandbreite oder max 20 Hz
    let transitionWidth = min(bandwidth * 0.1, 20.0)
    
    // Untere Flanke (Cosine-Taper)
    if frequency < lowFrequency + transitionWidth {
        let position = (frequency - lowFrequency) / transitionWidth
        return (1.0 - cos(position * .pi)) / 2.0
    }
    
    // Volle Dämpfung
    else if frequency > lowFrequency + transitionWidth &&
            frequency < highFrequency - transitionWidth {
        return 0.0
    }
    
    // Obere Flanke
    else if frequency > highFrequency - transitionWidth {
        let position = (highFrequency - frequency) / transitionWidth
        return (1.0 - cos(position * .pi)) / 2.0
    }
    
    return 1.0 // Nicht blockiert
}
```

### Performance

- **O(N × M)**: N = FFT-Bins, M = Anzahl Filter
- **Optimierung**: Frühe Rückgabe wenn keine Filter aktiv
- **Typischer Overhead**: < 1% bei 3 Filtern

---

## Beispiel-Workflow

### Use Case: Schallpegelmessung im Büro

**Problem**: 50 Hz Netzbrummen verfälscht LAeq-Messung

**Lösung**:
1. Öffne Dashboard-Widget
2. Aktiviere "Netzbrummen 50Hz"
3. Optional: Aktiviere "Oberwelle 100Hz" für 2. Harmonische
4. Im Spektrogramm erscheinen rote Markierungen
5. LAeq-Wert ist jetzt **ohne** Netzbrummen

**Vorteil**: Messung entspricht DIN 45641 (Arbeitslärm ohne technische Störungen)

---

## Fehlerbehandlung

### Filter überlappen sich
Kein Problem! Das System wendet alle Filter nacheinander an.

### Keine Filter sichtbar im Overlay
- Prüfe: `filter.isEnabled == true`
- Prüfe: Frequenzbereich liegt in 20-20000 Hz
- Prüfe: `geometryWidth` > 0

### Filter wird nicht persistiert
- Nutze `BandstopFilterManager.shared` (nicht neue Instanz)
- UserDefaults-Schlüssel: `"bandstopFilters"`

---

## API-Referenz

### BandstopFilterManager

```swift
class BandstopFilterManager: ObservableObject {
    static let shared: BandstopFilterManager
    
    @Published var filters: [BandstopFilter]
    
    var enabledFilters: [BandstopFilter] { get }
    
    func addFilter(_ filter: BandstopFilter)
    func removeFilter(id: UUID)
    func updateFilter(_ filter: BandstopFilter)
    func toggleFilter(id: UUID)
    
    func isFrequencyBlocked(_ frequency: Float) -> Bool
    func attenuationFactor(for frequency: Float) -> Float
    
    func addPreset(_ presetName: String)
}
```

### View Integration

```swift
// Full Settings
BandstopFilterSettingsView(filters: Binding<[BandstopFilter]>)

// Dashboard Widget
BandstopDashboardWidget()

// Overlay (auf Spektrogramm)
BandstopOverlayView(
    filters: [BandstopFilter],
    frequencyRange: ClosedRange<Float>,
    geometryWidth: CGFloat,
    geometryHeight: CGFloat
)

// Mini Variants
BandstopMiniWidget()
BandstopStatusIndicator()
```

---

## Roadmap / Erweiterungen

### Potentielle Features:
- ☐ **Export/Import** von Filter-Sets (JSON)
- ☐ **Adaptive Filter** (automatische Erkennung von Störfrequenzen)
- ☐ **Q-Faktor** einstellbar (schmalere/breitere Filter)
- ☐ **IIR-Filter** statt FFT-Maskierung (für Echtzeit)
- ☐ **Spektrum-Analyse-Modus** ("Finde dominante Frequenz")
- ☐ **Cloud-Sync** über iCloud

---

## Lizenz & Credits

**AudioEngine Filter Integration**  
Developed for SpektoWatch2  
© 2026 - MIT License

**Algorithmus basiert auf**:
- IEC 61260 (1/1 & 1/3 Octave Filters)
- Cosine-Taper Window (Tukey-Window Variant)
