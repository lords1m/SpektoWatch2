# WatchConnectivityManager Duplicate — Ist-Analyse (Phase 2, Task 2.1)

Datum: 2026-06-10
Bezug: `VERBESSERUNGSPLAN.md` Phase 2; Vorläufer: `agent/tasks/milestone-6-code-audit-remediation/task-3-watchconnectivity-consolidation.md` (Konsolidierung war dort explizit als Follow-up vertagt).
Status: read-only Analyse — **kein Code geändert.**

## Kernbefund (entscheidend)

Es gibt zwei Typen mit identischem Namen `WatchConnectivityManager`:

| | `SpektoWatch2/WatchConnectivityManager.swift` | `Shared/WatchConnectivityManager.swift` |
|---|---|---|
| Zeilen | 618 | 573 |
| Sichtbarkeit | `public class` | interne `class` |
| Singleton | keiner | `static let shared` (**nirgends referenziert**) |
| `init` | `public override init()` | `private override init()` |
| Sende-Pfad | Retry-Queue (`messageQueue`, `sendWithRetry`, `processQueue`, exp. Backoff, `dispatchPrecondition(.main)`) | nur `guard isReachable` + fire-and-forget `sendMessage` |
| Logging | `Logger.connectivity` (OSLog) | `print(...)` |
| Signposts | nein | ja (`performance.connectivity`) |
| `didReceiveMessage`-Switch | **alle 11 `MessageType`-Cases** (inkl. `watchMeterLayoutConfig`, `watchMeasurementSourcePreference`, `recordingFileTransfer`/`recordingSynced`) | nur **7 Cases**, **kein `default`** |
| Extra-Sende-API | `sendFrequencyWeightingSelection`, `sendSpectrogramResolution`, `sendWatchAppSettings`, `sendWatchDashboardConfig` (+Context) | `onMicrophoneSourceChanged`-Callback; `sendWatchDashboardConfigViaContext` |
| Duration-Resolver | `RecordingManager.resolvedRecordingDuration(...)` | `RecordingDurationResolver.resolved(...)` |

### Welche Datei lebt?

`WatchConnectivityProtocol.MessageType` hat **11 Cases** (`Shared/WatchConnectivityProtocol.swift:4–28`). Der `didReceiveMessage`-Switch in `Shared/WatchConnectivityManager.swift` deckt nur 7 davon ab und hat **kein `default`** → dieser Switch ist **nicht erschöpfend** und würde einen Compile-Fehler erzeugen, wenn die Datei in irgendein Target kompiliert würde.

**Schlussfolgerung: `Shared/WatchConnectivityManager.swift` ist toter Code.** Sie wird in keinem Target kompiliert (s. Target-Mapping). Die lebende, gepflegte Implementierung ist `SpektoWatch2/WatchConnectivityManager.swift` (erschöpfender Switch, Retry-Queue, von M16/task-3 + task-3-Konsolidierung gehärtet).

Zusätzliche Bestätigung: Alle Aufrufstellen instanziieren über `WatchConnectivityManager()` (public init). Der `private init` + `static let shared` der Shared-Variante wird **nirgends** benutzt (`WatchConnectivityManager.shared` kommt nur in ihrer eigenen Definition vor).

## Target-Mapping (pbxproj)

Synchronisierte Root-Groups je Target:
- **SpektoWatch2 (iOS)** — Groups `[SpektoWatch2, Shared]`; Ausnahme `37C13FAD`: Shared-Ordner schließt `WatchConnectivityManager.swift` aus → iOS kompiliert **nur** `SpektoWatch2/WatchConnectivityManager.swift`.
- **SpektoWatch Watch App** — Groups `[SpektoWatch Watch App, Shared]`; Ausnahme `37C141FA`: Shared-Ordner schließt `WatchConnectivityManager.swift` aus.
- **SpektoWatch2WidgetExtension** — Group `[SpektoWatch2Widget]`.

### pbxproj-Inkonsistenzen (Drift-Beleg)

- Ausnahme `37C141F9` ("SpektoWatch2-Ordner im *SpektoWatch Watch App* Target" schließt `WatchConnectivityManager.swift` aus) referenziert eine Mitgliedschaft, die **nicht (mehr) existiert** — die Watch-App-Group-Liste enthält die `SpektoWatch2`-Group nicht. → **Orphan-Ausnahme.**
- Ausnahme `3741BDD1` ("Shared-Ordner im Widget-Target") referenziert ebenfalls eine Group, die in der Widget-Target-Group-Liste fehlt. → **Orphan-Ausnahme.**
- `project.pbxproj` ist im Arbeitsbaum aktuell stark verändert (uncommitted: 43 +, 58 −) — die Target-Mitgliedschaften werden offenbar gerade umgebaut. Es existiert eine 365 KB große `.watch-build.log` im Root.

**Folge:** Wie genau die Watch-App ihren `WatchConnectivityManager` bezieht, lässt sich allein aus dem (mid-refactor) pbxproj nicht zweifelsfrei ableiten und braucht einen echten Build zur Verifikation.

## Aufrufstellen (Konsumenten)

`WatchConnectivityManager()` (public init) wird instanziiert in:
- iOS App: `AppServices.swift` (×2: `live`/`testFixture`), `Views/AdvancedAnalysisView.swift`, Tests (`IntegrationTests`, `AudioEngineTests`, `PDFReportGeneratorTests`, `RecordingManagerTests`, `PerformanceMetricsTests`, `PerformanceProfilingTests`).
- Watch App: `SpektoWatch Watch App/SpektoWatchApp.swift:17` (`let cm = WatchConnectivityManager()`), als `@StateObject` + `@EnvironmentObject` in ~10 Watch-Views.
- Watch-Tests: `SpektoWatchTests/WatchAudioEngineTests.swift`.
- Als Dependency injiziert in `AudioEngine`, `DashboardViewModel`, `ModularDashboardView`.

Kein einziger Konsument nutzt `.shared`.

## Empfohlenes Zielbild (für Task 2.2)

**Option A (bevorzugt, deckt sich mit Plan):**
1. `Shared/WatchConnectivityManager.swift` löschen (toter Code).
2. Die lebende `SpektoWatch2/WatchConnectivityManager.swift` nach `Shared/` verschieben (sie ist bereits vollständig plattform-gegated mit `#if os(iOS)`/`#if os(watchOS)`).
3. pbxproj: die drei WCM-Ausnahmesets (`37C13FAD`, `37C141F9`, `37C141FA`) **entfernen** und sicherstellen, dass die (verschobene) Datei in iOS- **und** Watch-Target kompiliert wird. Orphan-Ausnahmen gleich mitentfernen.
4. `WatchConnectivityProtocol.swift` bleibt unverändert (Wire-Format/Encoding nicht anfassen).

Damit gibt es genau eine Definition pro Typname; die fragile Ausnahme-Mechanik entfällt.

## Risiken / Voraussetzungen für Task 2.2

- **Isolation nicht möglich:** Beide Quelldateien **und** `project.pbxproj` sind bereits Teil nicht-committeter Arbeit (mid-refactor). Ein sauberer, isolierter Phase-2-Commit (wie in Phase 1) ist hier nicht machbar, ohne diese laufende Arbeit zu berühren.
- **Build-Gate unsicher:** Der Vorläufer-Task vermerkt "simulator broken"; die `.watch-build.log` deutet auf laufende Watch-Build-Probleme. Das in den Arbeitsregeln geforderte 4-Target-Kompilier-Gate ist auf diesem Arbeitsbaum derzeit nicht verlässlich ausführbar.
- **Wächter-Tests:** `WatchConnectivityTests`, `WatchProtocolVersioningTests`, `WatchDataProtocolTests` müssen vor Merge grün sein.

## Fazit

Die Konsolidierung ist inhaltlich **eindeutig** (Shared-Variante ist tot, iOS-Variante behalten + nach `Shared/` ziehen, Ausnahmen entfernen). Der **Ausführungs-Block** liegt nicht im Code, sondern im Repo-Zustand: die betroffenen Dateien sind Teil eines laufenden, nicht-committeten pbxproj/Target-Umbaus, und das Build-Gate ist auf diesem Baum nicht verlässlich.
