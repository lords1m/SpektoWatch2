# SpektoWatch2 Fullstack-Übersicht

Stand: 2026-03-25  
Repo: `SpektoWatch2` (iOS + watchOS, Swift/SwiftUI, ohne externe Package-Dependencies)

## 1) Stack auf einen Blick

- Sprache/UI: Swift, SwiftUI
- Audio/DSP: AVFoundation, Accelerate/vDSP
- Rendering: Metal/MetalKit (Live- und Playback-Spektrogramm)
- Kommunikation: WatchConnectivity
- State/Reactive: Combine, `@Published`, `EnvironmentObject`
- Logging/Profiling: `OSLog`, `os_signpost`, Diagnose-Flags via Scheme-Env
- Tests: XCTest (Unit, Integration, UI), `.xctestplan`, `run_tests.sh`

## 2) Targets und Projektstruktur

### Targets
- `SpektoWatch2` (iOS App)
- `SpektoWatch Watch App` (watchOS App)
- `SpektoWatch2Tests` / `SpektoWatch2UITests`

### Hauptordner
- `SpektoWatch2/` iOS-UI, AudioEngine, DSP, Renderer, Widget-System
- `SpektoWatch Watch App/` watch-UI und WatchAudioEngine
- `Shared/` gemeinsame Payloads, Mapping, Notifications, Logging

### Wichtiger Build-Mechanismus
Das Projekt nutzt **filesystem-synced groups** in `project.pbxproj` mit `PBXFileSystemSynchronizedBuildFileExceptionSet`.  
Damit werden einzelne Dateien trotz gleicher Namen gezielt aus Targets ausgeschlossen (wichtig bei Legacy-Duplikaten).

## 3) Laufzeit-Architektur (iOS)

### App Bootstrap
- Entry: `SpektoWatch2/SpektoWatch2App.swift`
- Instanziert und injiziert:
  - `AudioEngine`
  - `BandstopFilterManager`
  - `WatchConnectivityManager`
  - `RecordingManager`
  - `FFTConfiguration`

### UI-Schichten
- Root: `ContentView` -> `ModularDashboardView`
- Dashboard-Verwaltung:
  - `DashboardViewModel`
  - `DashboardManager` (persistiert Widget-Layout in `UserDefaults`)
- Widget-Rendering:
  - `WidgetCardView` + spezifische Widgets (`SpectrogramWidget`, `FrequencySpectrumWidget`, `LevelHistoryWidget`, etc.)
- Einstellungen:
  - Global: `SpectrogramSettingsView` (Audioquelle, Zeit-/Frequenzbewertung, FFT, Kalibrierung, Glättung)
  - Pro Widget: `WidgetSettingsView` mit Toggle `useWidgetOverrides`

### DSP-Pipeline (zentral)
- Zentraler Einstieg: `AudioEngine.processSamples(...)` / `processFFTFrame(...)`
- Komponenten:
  - `FFTProcessor` (eine zentrale FFT-Quelle für Live-Widgets)
  - `FrequencyWeightingProcessor` (A/C/Z)
  - `SpectrogramProcessor` (Bandstop, Binning, zeitliche Glättung, Oktavbänder)
  - `AcousticMetricsCalculator` (LAF/LAS/LCF/.../LAeq/Perzentile)
- Publiziert pro Frame:
  - `currentSpectrogramData`
  - `currentSpectrum`
  - `currentOctaveBands{Z,A,C}`
  - Pegel- und Historienwerte

## 4) Rendering-Pipeline

### Live-Spektrogramm
- Renderer: `HighEndSpectrogramAdapter` + `HighEndSpectrogramShaders.metal`
- Verarbeitung:
  - Eingang: FFT-Magnituden aus `currentSpectrogramData`
  - Frequenzmapping: aktuell logarithmische Frequenzachse (20 Hz - 20 kHz)
  - Dynamiknormalisierung + optional Frequenzglättung
  - Ringpuffer-Textur + column-based Update

### Spektrum-Widget
- `FrequencySpectrumWidget` / `SpectrumBandChartView`
- Nutzt dieselbe zentrale Datenquelle (`currentSpectrogramData`) plus voraggregierte Dritteloktavbänder.

### Playback-Spektrogramm
- Separater Pfad in `PlaybackSpectrogramView.swift`
- Enthält eigene FFT-Berechnung für Offline/Playback-Szenarien (nicht Teil des Live-Pfads).

## 5) Watch-Architektur

### Datenfluss

```mermaid
flowchart LR
    WMic["Watch Mic"] --> WAE["WatchAudioEngine"]
    WAE -->|AudioData| WC["WatchConnectivity"]
    WC --> IAE["iOS AudioEngine"]
    IAE --> DSP["FFT + Weighting + Metrics"]
    DSP --> SD["SpectrogramData"]
    SD --> WC2["WatchConnectivity"]
    WC2 --> WUI["Watch Widgets"]
```

- Watch App Entry: `SpektoWatch Watch App/SpektoWatchApp.swift`
- Lokale Watch-Verarbeitung:
  - `WatchAudioEngine` macht zusätzlich eine lokale FFT für sofortige Anzeige auf der Uhr.
  - Parallel wird Audio an iPhone gesendet, wo die Hauptverarbeitung läuft.

## 6) Datenmodelle, Persistenz und Konfig-Priorität

### Kernmodelle
- `Shared/SpectrogramData.swift`
  - `frequencies`, `magnitudes`, optional `magnitudesA/C`, `levels`, `sampleRate`, `timestamp`
- `Shared/WatchWidgetConfiguration.swift`
  - Watch-Dashboard-Layout und Persistenz

### Persistenz
- Dashboard-Widgets iOS: `DashboardConfiguration_v5` (`DashboardManager`)
- FFT-Settings: `fft_*` Keys (`FFTConfiguration`)
- Kalibrierung/Glättung: `calibrationOffset`, `spectrogramFrequencySmoothing` (`AudioEngine`)
- Watch-Layout: `watchDashboardConfig` (`WatchDashboardConfig`)

### Settings-Priorität (heute)
1. Global App-Settings (Engine/FFTConfiguration)
2. Widget-Settings nur wenn `useWidgetOverrides == true`
3. Sonst Fallbacks aus `WidgetSettings.default*`

Hinweis: Bei einigen Widget-Parametern (z. B. Colormap/TimeSpan/Sensitivity) ist der Fallback aktuell ein statischer Default, nicht immer ein globaler Runtime-Wert.

## 7) Tests und Qualitätssicherung

### Testsuite
- Unit/Integration: `SpektoWatch2Tests/*`
- UI: `SpektoWatch2UITests/*`
- Runner: `run_tests.sh`

### Auffälligkeiten
- Mehrere Tests sind aktuell per `XCTSkip` deaktiviert (u. a. Memory-Management- oder Stress/Race-Condition-Hinweise in Testcode).

### Diagnose-Flags
- `SPEKTO_DEBUG_SPECTRUM=1`  
  -> loggt `[SpectrumDiag] ...` aus `AudioEngine`
- `SPEKTO_DEBUG_WIDGET_SPECTRUM=1`  
  -> loggt `[SpectrumWidgetDiag] ...` aus `AudioWidgets`

## 8) Redundanzen und potenzielle Konflikte

### Vorhandene Duplikate (historisch/legacy)
- `SpektoWatch2/RecordingManager.swift` und `SpektoWatch2/Managers/RecordingManager.swift`
- `SpektoWatch2/WatchConnectivityManager.swift` und `Shared/WatchConnectivityManager.swift`

Diese Doppelungen sind teilweise per Target-Exceptions entschärft, erhöhen aber Wartungsrisiko und Verwechslungsgefahr.

### Harte Samplerate-Annahmen
- Einzelne Komponenten rechnen weiterhin implizit mit 44.1 kHz (z. B. in bestimmten Zeitachsen-/Buffergrößen-Berechnungen).
- Der zentrale Live-DSP-Pfad in `AudioEngine` arbeitet bereits mit dynamischer `processingSampleRate`.

## 9) End-to-End für Live iOS (Referenzfluss)

```mermaid
flowchart TD
    Mic["AVAudioInputNode Tap"] --> Buf["AudioEngine sampleBuffer + hop"]
    Buf --> FFT["FFTProcessor"]
    FFT --> DB["dB SPL + Calibration"]
    DB --> W["Weighting A/C/Z"]
    W --> SP["SpectrogramProcessor"]
    SP --> M["AcousticMetricsCalculator"]
    SP --> SD["SpectrogramData"]
    M --> SD
    SD --> UI["Widgets (Spectrogram/Spectrum/History/Values)"]
    SD --> WC["WatchConnectivity sendSpectrogramData"]
```

## 10) Kurzfazit

- Die Live-Analyse ist zentral in `AudioEngine` gebündelt und wird von den iOS-Widgets gemeinsam genutzt.
- Watch unterstützt Hybridbetrieb (lokale Sofort-FFT + iPhone-Hauptverarbeitung).
- Der größte technische Schuldenblock liegt bei Legacy-Duplikaten und einzelnen verbleibenden 44.1-kHz-Annahmen außerhalb des Kernpfads.
