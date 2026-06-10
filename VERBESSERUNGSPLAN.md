# Verbesserungsplan SpektoWatch2 (für Claude Code)

> Erstellt: 2026-06-10, basierend auf Architektur-Review.
> Format folgt der bestehenden `agent/`-Milestone-Struktur. Jede Phase ist ein
> eigener, unabhängig abnehmbarer Arbeitsblock. Phasen in der angegebenen
> Reihenfolge abarbeiten — spätere Phasen setzen auf den früheren auf.

## Arbeitsregeln (gelten für jede Phase)

- **Ein Task = ein Branch = ein Commit-Set.** Keine Phasen mischen.
- **Kompilier-Gate:** Nach jedem Task müssen alle vier Targets bauen
  (`SpektoWatch2`, `SpektoWatch Watch App`, `SpektoWatch Complications`, Tests).
- **Test-Gate:** `xcodebuild test -scheme SpektoWatch2 -destination 'platform=iOS Simulator,name=iPhone 16'`
  muss grün sein, bevor ein Task als erledigt gilt. Bei Watch-Änderungen
  zusätzlich die Watch-Tests (`SpektoWatchTests`).
- **Verhaltensneutralität:** Phasen 1–4 sind reine Refactorings/Hygiene.
  Kein beobachtbares Verhalten ändern; Messwerte (LAeq, LCpeak, Spektrogramm)
  müssen bitidentisch bleiben — `WatchDSPParityTests` und
  `AcousticMetricsCalculatorTests` sind die Wächter.
- **Echtzeit-Regeln aus `agent/design/requirements.md` einhalten:** keine
  Allokationen im Audio-Hot-Path, keine Blockierung von Audio-Callbacks,
  UI-Updates gedrosselt halten.
- **Kommentarstil beibehalten:** Entscheidungen mit Milestone-/Task-Referenz
  dokumentieren, wie im Bestand (z. B. „M13 task-1").

---

## Phase 1 — Repo-Hygiene (Aufwand: klein, Risiko: minimal)

### Task 1.1: Build-Artefakte aus Git entfernen

**Problem:** 305 Dateien unter `DerivedData/` sind in Git getrackt (`git ls-files | grep -c '^DerivedData/'`).
Zusätzlich liegen `.derivedData-sharpen2/`, `build/`, `.build/` mit ~2.700
Swift-Dateien im Arbeitsbaum.

**Schritte:**
1. `git rm -r --cached DerivedData/` (nur Index, Dateien lokal behalten).
2. `.gitignore` ergänzen: `DerivedData/`, `.derivedData-*/`, `.build/`
   (Anmerkung: aktuell steht dort nur `.DerivedData/` mit Punkt — das greift nicht).
3. Prüfen, ob weitere Artefakte getrackt sind:
   `git ls-files | grep -E '^(build|\.build|\.derivedData)' `.
4. Commit. **Kein** History-Rewrite (kein filter-branch/BFG) ohne explizite
   Freigabe des Nutzers — Remote-Branches existieren.

**Akzeptanz:** `git ls-files | grep -cE '^(DerivedData|build|\.build|\.derivedData)'` → 0.
`git status` zeigt keine Artefakt-Dateien mehr als Änderungen.

### Task 1.2: Root-Dokumente konsolidieren

**Problem:** `BUTTON_FIX_SUMMARY.md`, `PERFORMANCE_REVIEW.md` u. a. liegen lose im Root.

**Schritte:** Historische Einmal-Dokumente nach `agent/reports/` verschieben;
lebende Verträge (`PERFORMANCE_BUDGET.md`, `PERFORMANCE_CONTRACT.md`) im Root
belassen. Verweise in `agent/` aktualisieren (grep nach Dateinamen).

**Akzeptanz:** Root enthält nur lebende Dokumente; `./agent/scripts/acp-validate` läuft durch.

---

## Phase 2 — WatchConnectivityManager-Duplikat auflösen (Aufwand: mittel, Risiko: mittel)

**Problem:** Zwei Klassen mit identischem Namen:
- `SpektoWatch2/WatchConnectivityManager.swift` (618 Z., `public`, WCSessionDelegate)
- `Shared/WatchConnectivityManager.swift` (573 Z., non-public)

Die Target-Zuordnung erfolgt über `PBXFileSystemSynchronizedBuildFileExceptionSet`-
Ausnahmen im pbxproj — fehleranfällig und für Leser unsichtbar. Drift-Risiko ist real.

### Task 2.1: Ist-Analyse (read-only)

1. Beide Dateien vollständig diffen: gemeinsame API, Unterschiede, welche
   Properties/Methoden nur in einer Version existieren.
2. Über pbxproj exakt klären, welches Target welche Datei kompiliert
   (Abschnitt `PBXFileSystemSynchronizedBuildFileExceptionSet`, Zeilen ~170–210).
3. Alle Aufrufstellen sammeln: `grep -rn "WatchConnectivityManager" SpektoWatch2/ Shared/ "SpektoWatch Watch App/" "SpektoWatch Complications/"`.
4. Ergebnis als Tabelle in `agent/reports/` dokumentieren, bevor Code angefasst wird.

### Task 2.2: Konsolidierung

**Zielbild (eine der beiden Optionen, nach Analyse entscheiden):**
- **Option A (bevorzugt):** Eine Datei in `Shared/` mit `#if os(iOS)` / `#if os(watchOS)`
  für plattformspezifische Teile; pbxproj-Ausnahmen entfernen.
- **Option B (falls die Implementierungen zu weit auseinander sind):**
  Gemeinsames Protokoll + Basisklasse in `Shared/`, plattformspezifische
  Subklassen mit eindeutigen Namen (`PhoneConnectivityManager`,
  `WatchSideConnectivityManager`). Keine zwei Typen mit gleichem Namen.

**Schritte:** Diff-getrieben mergen, Protokoll-Encoding nicht anfassen
(`WatchConnectivityProtocol.swift` bleibt unverändert), pbxproj-Ausnahmen entfernen.

**Akzeptanz:**
- Genau eine Definition pro Typname im Repo.
- `WatchConnectivityTests`, `WatchProtocolVersioningTests`, `WatchDataProtocolTests` grün.
- Manueller Smoke-Test: Live-Daten Phone→Watch und Watch-Recording-Ingest
  Watch→Phone funktionieren (`onWatchRecordingReceived`-Pfad in `AppServices`).

---

## Phase 3 — AudioEngine zerlegen (Aufwand: groß, Risiko: hoch — schrittweise!)

**Problem:** `SpektoWatch2/AudioEngine.swift` hat 2.181 Zeilen und mindestens
sieben Verantwortlichkeiten: AVAudioEngine-Session/Capture, FFT-Orchestrierung,
Weighting, Metriken, Spektrogramm-Verteilung, Watch-Ingest, UI-Throttling,
Diagnostik/Impulslogging.

**Strategie:** Strangler-Pattern — Verantwortlichkeiten einzeln herauslösen,
AudioEngine bleibt als Fassade bestehen, damit die ~20 `@EnvironmentObject`-
Konsumenten zunächst unverändert weiterlaufen. **Pro Task maximal eine
Extraktion.** Nach jeder Extraktion: Tests + manueller Audio-Smoke-Test.

### Task 3.1: Charakterisierungstests sichern

Vor dem Refactoring prüfen, was `AudioEngineTests`, `IntegrationTests`,
`PerformanceMetricsTests` bereits abdecken. Fehlende Abdeckung für die
herauszulösenden Pfade ergänzen — insbesondere:
- Sample-Pufferung/Offset-Logik (`sampleBuffer`/`sampleBufferOffset`, O(1)-removeFirst)
- UI-Throttling-Intervalle (60 Hz / 15 Hz)
- Wearable-Ingest-Pfad (`wearableMetricsCalculator`, `lastWearableIngestTime`)

### Task 3.2: `AudioCaptureSession` extrahieren

AVAudioEngine-Besitz, Tap-Installation, Session-Konfiguration, Sample-Rate-
Beobachtung, `prewarmCaptureGraph()`, Stereo-Input-Modi. Liefert Sample-Blöcke
über einen Callback an die Pipeline. Kein Combine im Hot Path.

### Task 3.3: `ProcessingPipeline` extrahieren

FFT-Frame-Assembly, Scratch-Buffer-Verwaltung, `processingLock`,
FFTProcessor/Weighting/SpectrogramProcessor-Orchestrierung. Die Lock- und
Buffer-Disziplin (OSAllocatedUnfairLock, Vorallokation) 1:1 übernehmen —
Begründungskommentare mitnehmen.

### Task 3.4: `WearableIngestCoordinator` extrahieren

Watch-als-Mikrofon-Pfad inkl. Fallback-Leq-Integration für alte Watch-Builds.

### Task 3.5: `UIPublishThrottle` extrahieren

Die Drosselungslogik (targetUIInterval, targetSpectrogramUIInterval,
`spectrogramSubject`) als eigene, testbare Einheit.

### Task 3.6: Abnahme

**Akzeptanz für die gesamte Phase:**
- `AudioEngine.swift` < 600 Zeilen, nur noch Fassade + Published-State.
- Alle bestehenden Tests grün, inkl. `WatchDSPParityTests` (Messwert-Parität!).
- Instruments-/Signpost-Check: keine neuen Allokationen im Audio-Callback
  (os_signpost-Kategorien `performance.audio` vergleichen).
- `PERFORMANCE_BUDGET.md`-Grenzen eingehalten.

---

## Phase 4 — DI-Migration abschließen (Aufwand: mittel, Risiko: niedrig)

**Problem:** `AppServices` konsolidiert nur die Producer-Seite (laut eigenem
Kommentar „M13 task-1"). Views beziehen weiterhin 7 einzelne
`@EnvironmentObject`s; `SpektoWatch2App` injiziert beides parallel.

**Schritte:**
1. Konsumenten inventarisieren: `grep -rn "@EnvironmentObject" SpektoWatch2/ | sort`.
2. Views schrittweise (5–10 pro Commit) auf `@EnvironmentObject var services: AppServices`
   umstellen; Zugriff dann `services.filterManager` etc.
3. Für `audioEngine`/`maskingEngine` (optional bis `startAudio()`): Views
   erhalten die Engines weiterhin non-optional — der Gate in `SpektoWatch2App`
   (Splash bis `isAudioReady`) bleibt bestehen; Engines per Parameter oder
   eigenem Environment-Key durchreichen.
4. Am Ende die 7 `.environmentObject(...)`-Aufrufe in `SpektoWatch2App` auf
   eine reduzieren. `AppServices.testFixture` entsprechend in Tests nutzen.

**Akzeptanz:** Genau ein `.environmentObject` in `SpektoWatch2App`;
Snapshot-/UI-Tests unverändert grün.

### Task 4.2 (Folge-Refactor): `startAudio()` auf strukturierte Concurrency

Die verschachtelte GCD-Kette (`DispatchQueue.global` → `main.async`) durch
`Task.detached` + `await MainActor.run` ersetzen. Idempotenz-Guard beibehalten.
Nur nach Abschluss von 4.1, damit Änderungen isoliert testbar sind.

---

## Phase 5 — Kleinere Qualitätsthemen (Aufwand: klein–mittel, parallelisierbar)

### Task 5.1: Lokalisierung vorbereiten

Hartkodierte deutsche UI-Strings (`ScrollSpeed.label`: „Sehr Langsam",
`StereoInputMode`-RawValues, WindowFunction-Beschreibungen u. a.) in einen
String-Catalog (`Localizable.xcstrings`) überführen. **Achtung:**
`StereoInputMode` nutzt den deutschen Text als `RawValue` — vermutlich
persistiert. Vor Umstellung prüfen (`PersistenceKeys.swift`, UserDefaults-Reads)
und ggf. Migrationsschritt im `PersistenceMigrator` ergänzen
(Tests: `PersistenceMigratorTests`).

### Task 5.2: ChartRenderer entdoppeln

`drawLineChart`/`drawBarChart` teilen sich ~40 Zeilen Achsen-/Grid-/Tick-Code.
Gemeinsame private Helfer extrahieren (`drawAxisGrid(in:rect:ticks:) -> CGRect`).
Rein mechanisch, Pixel-Output identisch (Snapshot-Tests, falls vorhanden, sonst
visueller Vergleich).

### Task 5.3: Naming-Konventionen festschreiben

Deutsch/Englisch-Mix in Typnamen (`WatchPegelmesserFace`, `SpektralanalyseLaborWidget`
vs. englischer Rest). Konvention in `agent/design/requirements.md` ergänzen
(Empfehlung: Code englisch, UI-Strings über Lokalisierung). Bestehende Namen
nur umbenennen, wenn ohnehin an der Datei gearbeitet wird — kein Big-Bang-Rename.

### Task 5.4: SpectrogramProcessor-Terzbänder deduplizieren

`SpectrogramProcessor.thirdOctaveCenters` dupliziert die kanonische Liste aus
`SpectrumBandAggregator` (laut Kommentar in `AudioEngine` ist letztere kanonisch).
Auf eine Quelle zusammenführen.

---

## Phase 6 — Protokoll-Evolution Watch-Transfer (Aufwand: mittel, Risiko: hoch — Kompatibilität!)

**Ist-Zustand (`Shared/WatchConnectivityProtocol.swift`):** Nachrichten sind
untypisierte `[String: Any]`-Dictionaries mit String-Keys (`type`, `value`,
`config`, …). Es gibt keinen expliziten Protokollversions-Feld in den
Nachrichten selbst; Kompatibilität mit alten Watch-Builds wird implizit
gehandhabt (z. B. Fallback-Leq-Integration in `AudioEngine`, wenn `bandLeq*`
fehlt). Binärpakete kennen nur `BinaryPacketKind.spectrogram = 0x01`.

**Grundregel für alle Tasks dieser Phase:** Ein altes Watch-Build muss mit
einem neuen Phone-Build weiter funktionieren und umgekehrt (Nutzer aktualisieren
nicht synchron). Jede Änderung ist additiv; Felder werden nie umgedeutet oder
entfernt. `WatchProtocolVersioningTests` und `WatchDataProtocolTests` vor jedem
Merge grün.

### Task 6.1: Explizite Protokollversion einführen

1. `static let protocolVersion: UInt16` in `WatchConnectivityProtocol` ergänzen
   (Start: 1 = heutiger Stand).
2. Version in jede ausgehende Nachricht unter neuem Key `protocolVersion`
   einbetten und beim Empfang lesen; fehlender Key ⇒ Version 0 (Alt-Build).
3. Versionsaustausch beim Session-Start über `updateApplicationContext`
   (überlebt Neustarts, wird nicht gequeued wie `transferUserInfo`).
4. Empfangene Gegenseiten-Version in beiden ConnectivityManagern publizieren
   (`@Published var peerProtocolVersion`), damit Sender Features abhängig von
   der Gegenseite aktivieren können — ersetzt die heutigen impliziten Heuristiken.

**Akzeptanz:** Neue Tests: Nachricht ohne Versionsfeld wird als v0 akzeptiert;
Nachricht mit höherer Version wird nicht verworfen, unbekannte Keys werden
ignoriert (Forward-Kompatibilität).

### Task 6.2: Typisierte Codable-Envelopes statt `[String: Any]`

1. Pro `MessageType` eine Codable-Payload-Struct definieren (z. B.
   `GainPayload`, `RecordingControlPayload`); Envelope:
   `{ type, protocolVersion, payload: Data }`.
2. **Wire-Format unverändert lassen** für bestehende Typen — die Codable-Layer
   serialisiert in exakt dieselben Dictionary-Shapes (Charakterisierungstests:
   altes `makeGainMessage(...)`-Dictionary == neues Encoding, Key für Key).
   Erst neue Nachrichtentypen nutzen das reine Codable-Envelope.
3. Die ~12 `make*Message`-Factories und ihre Gegenstücke (Parser) paarweise
   in eine Datei pro Richtung bündeln, damit Encoder/Decoder nicht driften.

**Akzeptanz:** Kein `[String: Any]`-Zugriff mehr außerhalb der Protokoll-Datei;
Round-Trip-Tests für jeden MessageType (encode → decode → Gleichheit).

### Task 6.3: Binärpaket-Header härten

1. Binärpaketen einen 4-Byte-Mini-Header geben: `kind (UInt8)`,
   `version (UInt8)`, `reserved (UInt16)` — heute existiert nur das Kind-Byte.
   Alt-Decoder-Pfad für Pakete ohne Header beibehalten (erkennbar am ersten
   Byte `0x01` + Längen-Plausibilität), zwei Releases später entfernen.
2. Optional (nach Messung): Spektrogramm-Payload mit `compression_encode`
   (lzfse) komprimieren, gated auf `peerProtocolVersion >= 2`. Vorher mit
   Signposts belegen, dass Transfergröße der Engpass ist — nicht raten.

**Akzeptanz:** Parity-Test alt/neu dekodiertes Spektrogramm bitidentisch;
Thermal-Intervalle (`*SpectrogramSendInterval`) unverändert eingehalten.

---

## Phase 7 — Messdatenformat .spekto v3 (Aufwand: mittel–groß, Risiko: hoch — Bestandsdaten!)

**Ist-Zustand (`Shared/MeasurementDataFormat.swift`):** Binärformat „SPKT",
Version 2, Little-Endian, fixer Header (36 Bytes) + `metricKeys`-Stringliste,
Frames mit Timestamp, Metriken, Terzbändern (Z/A/C, 31 Bänder), optional
Full-FFT (`flagHasFullFFT`). `headerSize` ist bereits im Header gespeichert —
gute Basis für Erweiterbarkeit.

**Grundregeln:**
- **Bestandsdateien sind unantastbar.** v2-Dateien müssen für immer lesbar
  bleiben (`MeasurementDataReader` behält den v2-Pfad).
- **Dual-Read, gestaffeltes Write:** Reader versteht v2+v3 sofort; Writer
  schreibt zunächst weiter v2, v3-Write kommt hinter einem Debug-Flag und wird
  erst nach Task 7.4 (Abnahme) zum Default.
- Jede Format-Änderung braucht Fixture-Dateien in den Tests: eine eingecheckte
  v2-Datei und eine v3-Datei als Golden Files (`MeasurementDataIOTests` erweitern).

### Task 7.1: v3-Spezifikation schreiben (read-only)

Spezifikation als `agent/design/spekto-format-v3.md` mit Byte-Layout-Tabelle.
Inhaltliche Kandidaten (mit dem Nutzer priorisieren, bevor implementiert wird):

1. **Integrität:** CRC32 über Header + optional pro Frame-Block. Heute wird
   eine korrupte Datei erst beim Frame-Parsen erkannt (`invalidFrameIndex`).
2. **Seek-Index:** Frame-Offset-Tabelle am Dateiende (Offset im Header) für
   O(1)-Sprünge in langen Aufnahmen — relevant für Waterfall-Scrubbing
   (`WaterfallPlaybackController`). Heute erfordert Frame n sequentielles Lesen,
   wenn Frames variable Größe haben (Full-FFT-Flag).
3. **Kalibrierungs-Metadaten im Header:** Mikrofonquelle, Gain,
   Kalibrier-Offset, Geräte-Modell — heute geht beim Export verloren, womit
   gemessen wurde. Wichtig für die Glaubwürdigkeit der Reports (Phase „Nutzen":
   orientierende Messung dokumentierbar machen).
4. **Komprimierte Full-FFT-Frames:** lzfse-Block pro Frame, neues Flag-Bit
   (`flagCompressedFFT = 1 << 1`). Full-FFT dominiert die Dateigröße.
5. **Erweiterbare TLV-Header-Sektion:** Typ-Länge-Wert-Blöcke nach dem fixen
   Header, unbekannte Typen werden übersprungen — verhindert, dass v4 wieder
   ein Versions-Bump sein muss.

### Task 7.2: Reader dual-fähig machen

1. `MeasurementDataReader`: Version-Switch (2 → Bestandspfad unverändert,
   3 → neuer Pfad). `unsupportedVersion` erst ab > 3 werfen.
2. Golden-File-Tests: v2-Fixture liest mit altem und neuem Reader identische
   Frames (bitgenauer Vergleich aller Floats).

### Task 7.3: Writer v3 hinter Flag

1. `MeasurementDataWriter` schreibt v3, wenn Debug-Flag/Launch-Argument gesetzt
   (Muster: `UITestRuntime` / `SPEKTO_DEBUG_SPECTRUM`-Env-Var).
2. Backpressure-Verhalten des Writers nicht verändern (M2 task-3,
   `RealtimeAudioFileWriter`-Disziplin gilt analog): Kompression und
   CRC-Berechnung gehören auf den Writer-Thread, nie auf den Audio-Callback.
3. Round-Trip-Test: schreiben (v3) → lesen → Frame-Parität mit v2-Schreibpfad
   derselben Quelldaten.

### Task 7.4: Konsumenten + Abnahme

1. Alle Leser durchprüfen: `StoredDataProvider`, `WaterfallDataBuilder`,
   `PlaybackAnalyzer`, CSV-/PDF-Export, Watch-Transfer (`.swr`-Dateien aus
   `recordingFileTransfer` — klären, ob das Watch-Format dasselbe `.spekto`
   ist; wenn ja, schreibt die Watch weiter v2, bis ihre Mindest-iOS-Version
   den v3-Reader garantiert hat).
2. Migrations-Frage explizit entscheiden: v2-Bestandsdateien werden **nicht**
   konvertiert (Dual-Read macht das unnötig) — nur dokumentieren.
3. v3 als Default-Write aktivieren, `MeasurementDataFormat.version = 3`.

**Akzeptanz Phase 7:** `MeasurementDataIOTests`, `StoredDataProviderTests`,
`WaterfallDataBuilderTests`, `MeasurementSpectralAvailabilityTests` grün;
v2-Golden-File unverändert lesbar; Waterfall/Export auf einer echten alten
Aufnahme manuell geprüft.

---

## Phase 8 — Verifikation & Abschlussbericht

1. Kompletter Testlauf aller Targets + UI-Tests mit `-SeedTestData`.
2. Performance-Vergleich gegen `BASELINE_PROFILING_MATRIX.md`
   (Signposts `performance.audio`, `performance.spectrogram`).
3. Watch-Smoke-Test: Standalone-Messung, Companion-Stream, Recording-Übertragung.
4. Abschlussbericht nach `agent/reports/<datum>-improvement-plan-acceptance.md`
   im Stil der bestehenden Milestone-Abnahmen.

---

## Priorisierung im Überblick

| Phase | Nutzen | Aufwand | Risiko | Abhängig von |
|---|---|---|---|---|
| 1 Repo-Hygiene | hoch (Repo-Größe, Klarheit) | klein | minimal | — |
| 2 ConnectivityManager | hoch (Drift-Risiko beseitigt) | mittel | mittel | 1 |
| 3 AudioEngine-Zerlegung | sehr hoch (Wartbarkeit) | groß | hoch | 1, idealerweise 2 |
| 4 DI-Migration | mittel | mittel | niedrig | 3 (teilbar) |
| 5 Qualitätsthemen | mittel | klein | niedrig | parallel möglich |
| 6 Protokoll-Evolution | mittel–hoch | mittel | hoch (Kompatibilität) | 2 |
| 7 .spekto v3 | hoch (Integrität, Seek, Kalibrier-Metadaten) | mittel–groß | hoch (Bestandsdaten) | 6 (Task 6.1) |
| 8 Verifikation | — | klein | — | alle |

**Explizit außerhalb des Scopes:** neue Features (außer den in Phase 6/7
spezifizierten Format-Erweiterungen), Git-History-Rewrite.
