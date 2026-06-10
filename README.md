# SpektoWatch

SpektoWatch ist eine SwiftUI-App für akustische Messungen auf iPhone und Apple
Watch. Sie zeigt Live-Pegel und Spektrogramme, zeichnet Messungen auf, erstellt
Exporte und unterstützt eigenständige Watch-Aufnahmen mit späterer
Synchronisierung zum iPhone.

Die integrierten Mikrofone liefern Orientierungswerte. Sie ersetzen keine
kalibrierte Schallpegelmessung.

## Projekt öffnen

```sh
open SpektoWatch2.xcodeproj
```

Wichtige Targets:

- `SpektoWatch2`: iOS-App
- `SpektoWatch Watch App`: watchOS-App
- `SpektoWatch2WidgetExtension`: iOS Live Activity
- `SpektoWatch Complications`: watchOS-Komplikationen
- `SpektoWatch2Tests`, `SpektoWatch2UITests`, `SpektoWatchTests`: Tests

## Dokumentation

- `TESTFLIGHT_EXTERNAL_TESTING.md`: Beschreibung und `What to Test` für externe
  TestFlight-Tests
- `docs/test-plans/`: manuelle Testmatrix, Xcode-Testpläne, Snapshot/UI-Anleitungen
- `FULLSTACK_UEBERSICHT.md`: Architekturüberblick
- `AGENT.md`: Repository-Kontext und Validierungsworkflow

## Validierung

```sh
./agent/scripts/acp-validate
xcodebuild -list -project SpektoWatch2.xcodeproj
```

Für Release-Akzeptanz sind echte Geräte erforderlich, insbesondere für
Mikrofonverhalten, WatchConnectivity, Live Activities und Komplikationen.
