# Lautheit-Rechner (ISO 226/532)

Interaktives Widget zur Konvertierung von Schalldruckpegel (dB SPL) zu psychoakustischen Maßen (Phon und Sone).

## Übersicht

Dieses Widget demonstriert den fundamentalen Unterschied zwischen physikalischer Schallmessung (dB SPL) und menschlicher Wahrnehmung (Phon/Sone). Es basiert auf:

- **ISO 226:2003**: Equal-Loudness-Konturen (Fletcher-Munson-Kurven)
- **ISO 532**: Zwicker-Methode für Lautheitsberechnung
- **Stevens' Power Law**: Phon-zu-Sone-Konversion

## Dateien

### Shared/LoudnessCalculator.swift
Berechnungslogik für:
- dB SPL → Phon Konvertierung (frequenzabhängig)
- Phon → Sone Konvertierung
- Interpolation zwischen ISO 226 Stützpunkten
- Interpretation der Ergebnisse

### Shared/LoudnessCalculatorView.swift
Vollständige SwiftUI-Benutzeroberfläche mit:
- Eingabefeldern für dB SPL (0-130) und Frequenz (20-20000 Hz)
- Live-Validierung
- Ergebnisanzeige mit kontextuellen Interpretationen
- Berechnung des SPL-Werts für doppelte Lautheit

## Integration in die App

### Option 1: Eigenständige View (Empfohlen)

Füge in `WatchContentView.swift` oder eine neue Navigation ein:

```swift
import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var audioEngine: WatchAudioEngine
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager
    @State private var showLoudnessCalculator = false

    var body: some View {
        NavigationView {
            VStack {
                WatchDashboardView()
                
                NavigationLink("Lautheit-Rechner", destination: LoudnessCalculatorView())
                    .padding()
            }
        }
    }
}
```

### Option 2: Als Tab in TabView

Für eine Tab-basierte Navigation:

```swift
TabView {
    WatchDashboardView()
        .tabItem {
            Label("Dashboard", systemImage: "waveform")
        }
    
    LoudnessCalculatorView()
        .tabItem {
            Label("Lautheit", systemImage: "speaker.wave.3")
        }
}
```

### Option 3: Als Dashboard-Widget (Erweitert)

Für Integration ins Dashboard-System:

1. Erweitere `WatchWidgetType` in `Shared/WatchWidgetConfiguration.swift`:
```swift
public enum WatchWidgetType: String, Codable, CaseIterable, Identifiable {
    // ... existing cases
    case loudnessCalculator = "Lautheit"
}
```

2. Erstelle `WatchWidgets/WatchLoudnessWidget.swift`:
```swift
import SwiftUI

struct WatchLoudnessWidget: View {
    @StateObject private var calculator = LoudnessCalculator()
    @State private var spl: Double = 60
    @State private var frequency: Double = 1000
    
    var body: some View {
        VStack(spacing: 2) {
            if let result = calculator.result {
                Text(String(format: "%.0f", result.phon))
                    .font(.system(size: 18, weight: .bold))
                Text("Phon")
                    .font(.system(size: 8))
                Text(String(format: "%.1f Sone", result.sone))
                    .font(.system(size: 8))
            } else {
                Text("--")
                    .font(.system(size: 18, weight: .bold))
                Text("Phon")
                    .font(.system(size: 8))
            }
        }
        .foregroundColor(.white)
        .onAppear {
            calculator.calculate(spl: spl, frequency: frequency)
        }
    }
}
```

3. Füge in `WatchDashboardView.swift` den neuen Case hinzu:
```swift
switch group.type {
// ... existing cases
case .loudnessCalculator:
    WatchLoudnessWidget()
        .frame(width: width, height: height)
        .cornerRadius(4)
}
```

## Funktionalität

### Eingabe
- **Schalldruckpegel**: 0-130 dB SPL
- **Frequenz**: 20-20000 Hz

### Berechnung
1. **dB SPL → Phon**: Berücksichtigt frequenzabhängige Hörempfindlichkeit
   - Bei 1000 Hz: dB SPL = Phon (Referenzfrequenz)
   - Bei anderen Frequenzen: Anwendung der ISO 226:2003 Equal-Loudness-Kurven

2. **Phon → Sone**: Stevens' Power Law
   - S = 2^((P-40)/10) für P ≥ 40 Phon
   - Für P < 40: S = (P/40)^2.642

3. **Verdopplung der Lautheit**:
   - +10 Phon = doppelte Lautheit
   - Zeigt erforderliche dB SPL-Erhöhung

### Ausgabe
- **Phon**: Lautstärkepegel mit Kontext (z.B. "Normal (Gespräch)")
- **Sone**: Wahrgenommene Lautheit (1 Sone = 40 Phon)
- **Verdopplung**: Benötigter SPL für doppelte Lautheit

## Psychoakustische Grundlagen

### Equal-Loudness-Konturen (ISO 226:2003)
Das menschliche Gehör ist frequenzabhängig:
- **Tiefe Frequenzen** (< 500 Hz): Benötigen höheren SPL für gleiche Lautheit
- **Mittlere Frequenzen** (1-5 kHz): Höchste Empfindlichkeit
- **Hohe Frequenzen** (> 8 kHz): Reduzierte Empfindlichkeit

### Phon vs. Sone
- **Phon**: Logarithmisches Maß (wie dB), aber frequenzkorrigiert
- **Sone**: Lineares Maß der wahrgenommenen Lautheit
- **Beziehung**: 10 Phon mehr = doppelte Lautheit in Sone

### Praktische Beispiele

| dB SPL | Frequenz | Phon | Sone | Interpretation |
|--------|----------|------|------|----------------|
| 60 | 1000 Hz | 60 | 2.0 | Normales Gespräch |
| 60 | 100 Hz | ~48 | ~1.15 | Gleicher SPL, leiser wahrgenommen |
| 70 | 1000 Hz | 70 | 4.0 | Doppelt so laut wie 60 Phon |
| 80 | 4000 Hz | ~78 | ~7.5 | Sehr laut (Straßenverkehr) |

## Verwendung im Code

```swift
import SwiftUI

struct ExampleView: View {
    @StateObject private var calculator = LoudnessCalculator()
    
    var body: some View {
        VStack {
            Button("Berechne 60 dB SPL bei 1000 Hz") {
                calculator.calculate(spl: 60, frequency: 1000)
            }
            
            if let result = calculator.result {
                Text("Phon: \(String(format: "%.1f", result.phon))")
                Text("Sone: \(String(format: "%.2f", result.sone))")
                Text(result.phonInterpretation)
            }
        }
    }
}
```

## Technische Details

### ISO 226 Stützpunkte
Das Widget verwendet tabellarische ISO 226:2003 Daten für folgende Frequenzen:
- 100, 200, 500, 1000, 2000, 4000, 8000 Hz
- Phon-Level: 20, 40, 60, 80, 100

Für andere Frequenzen wird linear interpoliert oder eine vereinfachte Approximation verwendet.

### Validierung
- SPL: 0-130 dB (0 dB SPL = Hörschwelle, 130 dB = Schmerzschwelle)
- Frequenz: 20-20000 Hz (Hörbarer Bereich)

## Referenzen

- ISO 226:2003 - Acoustics — Normal equal-loudness-level contours
- ISO 532-1:2017 - Acoustics — Methods for calculating loudness (Zwicker method)
- Stevens, S.S. (1957). "On the psychophysical law". Psychological Review, 64(3), 153–181

## Autor

Erstellt für SpektoWatch2 - Spektralanalyse für Apple Watch
