# Feature-Prompt: Adaptiver Maskierungs-Generator für SpektoWatch

## Kontext

SpektoWatch ist eine bestehende iOS-App zur spektralen Audio-Analyse. Wir wollen ein neues Feature ergänzen: einen **personalisierten Sound-Masking-Generator** für ADHS- und Misophonie-Betroffene, denen einzelne Störgeräusche (Tippen, Schmatzen, Knarzen, Klacken) die Konzentration nehmen.

Die Idee: Statt generisches Rauschen anzubieten, nimmt der Nutzer das Trigger-Geräusch *selbst* auf. Die App analysiert dessen Spektrum und schlägt einen passenden Masker (Textur + EQ + Pegel) vor. Der Nutzer kann das Ergebnis virtuell vorhören, indem das aufgenommene Trigger-Sample und der erzeugte Masker gemischt abgespielt werden.

iPhone-spezifischer Vorteil, der bewusst genutzt wird: Mikrofon und interner Lautsprecher sind ab Werk relativ kalibriert, sodass spektrale Messungen zwischen Geräten vergleichbar bleiben und keine Nutzer-Kalibrierung nötig ist.

## Wissenschaftliche Grundlage (für Onboarding/Hinweise)

- JAACAP-Meta-Analyse 2024 (OHSU): weißes/rosa Rauschen verbessert kognitive Leistung bei ADHS statistisch signifikant; ca. 30 % Nonresponder.
- Psychoakustik der kritischen Bänder (Zwicker/Fastl): effektive Maskierung erfordert ca. 4–6 dB Masker-Überpegel im selben kritischen Band wie das zu maskierende Signal.
- Misophonie-Trigger sind meist tonale, episodische Geräusche im 2–6 kHz-Bereich.

## User Flow

1. **Trigger aufnehmen.** Nutzer drückt Record und nimmt das störende Geräusch beliebig lang auf (10 s bis 10 min). Live-Wellenform und Live-Spektrum während der Aufnahme.
2. **Analyse.** App detektiert Event-Onsets, mittelt Spektrum nur über die lauten Frames, gibt 1/3-Oktav-Profil aus.
3. **Auto-Vorschlag.** App schlägt Masker-Textur (Wasser, Regen, Wind, White/Pink/Brown Noise, ggf. Café-Ambience) und EQ-Profil + Initial-Pegel vor.
4. **Anpassen.** Nutzer kann Masker-Textur wechseln, parametrische EQ-Bänder anpassen, Pegel justieren, Hi-/Lowpass setzen.
5. **Preview.** Trigger-Sample (Loop) + Masker werden gleichzeitig abgespielt. A/B-Toggle zwischen „nur Trigger", „Trigger + Vorschlag A", „Trigger + Vorschlag B". Trigger- und Masker-Pegel getrennt regelbar, um andere Distanzen zur Quelle zu simulieren.
6. **Speichern.** Profil mit Namen ablegen (z. B. „Büro – Kollege Tippen", „Zuhause – Kühlschrank").
7. **Daueralltag-Modus.** Profil auswählen, im Hintergrund laufen lassen (Background Audio), ohne Trigger-Sample.

## Technische Anforderungen

### Audio-Engine

- `AVAudioEngine` mit `AVAudioSession` (Kategorie `.playAndRecord`, Modus `.measurement` für möglichst neutrale Mic-Charakteristik).
- Sample Rate 48 kHz, Mono, 16-bit für Aufnahme; Float32 intern für Verarbeitung.
- Background-Audio-Capability im Info.plist für Daueralltag-Modus.
- Erkennung der aktuellen Output-Route (Built-in Speaker, Kopfhörer, Bluetooth) und situative Pegel-Empfehlung.

### Aufnahme & Spektral-Analyse

- Aufnahme via `installTap(onBus:)` auf den InputNode, in Ringpuffer.
- **Onset-Detection**: gleitender RMS, Threshold = Median + 2×MAD über die letzten N Frames; markiere Frames als „Event" oder „Stille". Verwerfe Stille-Frames für die Spektrum-Schätzung.
- **FFT**: Hann-Fenster, 2048 Punkte, 50 % Overlap, nur über Event-Frames akkumuliert.
- **Banding**: 1/3-Oktav-Mittelung von 50 Hz bis 16 kHz (ca. 25–28 Bänder). Speichere Mittelwert + Standardabweichung in dB pro Band.
- Output-Datenstruktur: `TriggerSpectrum { bands: [Float], stdDev: [Float], peakBand: Int, totalRMSdBFS: Float }`.

### Masker-Library

Vorgefertigte, nahtlos loop-bare Samples (≥ 30 s, AAC oder Apple Lossless), jedes mit vorab gemessenem 1/3-Oktav-Naturspektrum:

- Wasserplätschern (Bach)
- Regen (gleichmäßig, ohne Donner)
- Wind in Bäumen
- White Noise (synthetisch generiert)
- Pink Noise (synthetisch)
- Brown Noise (synthetisch)
- Optional: Lüfter, Bibliotheks-/Café-Ambience

Synthetische Rauscharten zur Laufzeit generieren (kein Sample), Naturklänge als Asset.

### Auto-Vorschlag-Algorithmus

```
Eingabe: TriggerSpectrum T
Für jeden Masker M in Library:
  natural_M = vorab-gemessenes Spektrum
  distance(T, natural_M) = cosine_distance(log(T.bands), log(natural_M.bands))
Wähle M* mit geringster Distanz.

EQ-Korrektur pro Band b:
  target_b = T.bands[b] + 6 dB
  needed_gain[b] = target_b - natural_M*.bands[b]
  clamp needed_gain[b] auf [-12, +12] dB

Vereinfache zu 5 parametrischen EQ-Bändern, indem benachbarte 1/3-Oktav-Bänder zusammengefasst werden (LowShelf < 200 Hz, 3× Peak im Mittelbereich, HighShelf > 6 kHz).

Initial-Volume:
  v0 = T.totalRMSdBFS + 6 dB - 6 dB Sicherheits-Reserve
  cap bei -10 dBFS (Hörschutz)
```

### EQ-Implementierung

- Verkettete `AVAudioUnitEQ` mit 5 Bändern (LowShelf, 3× Parametric, HighShelf).
- Pro Band: Frequenz, Q, Gain manuell einstellbar.
- Optional: Highpass und Lowpass als zusätzliche „extreme Beschneidung"-Filter.

### Preview-Mixer

- Zwei `AVAudioPlayerNode`-Instanzen:
  - Node A: Trigger-Sample, geloopt
  - Node B: Masker (Sample oder synthetisch generiertes Rauschen via `AVAudioSourceNode`)
- Beide durch separate `volumeMixer`-Bus-Ebenen, individuell regelbar (dB-Slider).
- A/B-Toggle steuert, welche Konfiguration aktiv ist (mind. zwei speicherbare Slots).
- UI-Hinweis: „Vorhören mit dem Setup, das du später nutzen wirst (Kopfhörer/Lautsprecher)."

### Profile-Management

- Lokale Speicherung als JSON in App-Sandbox (CoreData oder SwiftData).
- Felder: `name`, `triggerSampleURL?`, `maskerType`, `eqBands: [EQBand]`, `volume`, `createdAt`, `lastUsed`.
- Trigger-Samples optional (manche Nutzer wollen das aufgenommene Geräusch nicht behalten).
- Export/Import als `.spektoprofile`-JSON-Datei (Sharing via UIActivityViewController).

### Daueralltag-Modus

- Profil ohne Trigger-Sample auswählen, nur Masker spielt.
- Hintergrund-Wiedergabe via Background-Audio-Mode.
- Now-Playing-Info-Center-Integration mit Pause/Resume-Steuerung.
- Optional: Sleep-Timer.

### Sicherheit & Hinweise

- Pegel-Hard-Cap entsprechend ca. 60 dB SPL bei iPhone-Standard-Volume; Warnung bei Annäherung.
- Onboarding-Hinweis: „Diese App kann nicht jedem helfen – etwa 30 % der ADHS-Betroffenen profitieren nicht von Maskierungs-Geräuschen. Probier es aus, aber zwing dich nicht."
- Datenschutz: Trigger-Aufnahmen bleiben lokal, kein Cloud-Upload. Wenn Aufnahmen Dritte enthalten, kurzer Hinweis zur Verantwortung des Nutzers.
- Hörschutz-Empfehlung bei langen Sessions (>2 h).

## UI-Struktur (Vorschlag)

- **Tab 1 – Aufnahme**: großer Record-Button, Live-Wellenform, Live-Spektrum, „Genug aufgenommen"-Indikator (basiert auf spektraler Konvergenz).
- **Tab 2 – Vorschlag**: gewählte Masker-Textur (mit Möglichkeit zum Wechseln), EQ-Kurven-Visualisierung (Trigger-Spektrum + Masker-Spektrum überlagert), 5 parametrische EQ-Bänder als Touch-Drag-Punkte, Volume-Slider.
- **Tab 3 – Preview**: Play/Pause, A/B-Toggle, getrennte Pegel-Slider für Trigger und Masker, optional kurze Konzentrations-Selbsteinschätzung nach Test (1–5 Sterne, hilft Algorithmus-Tuning).
- **Tab 4 – Profile**: Liste, anlegen, umbenennen, löschen, exportieren, „jetzt aktivieren"-Button.

## Integration in bestehendes SpektoWatch

- Wiederverwenden: bestehende FFT-Pipeline, Spektrum-Visualisierung, AVAudioSession-Setup.
- Neuer Code: Onset-Detector, Auto-Vorschlag-Algorithmus, Masker-Library, Preview-Mixer-Logik, Profile-Modell, Background-Audio-Konfiguration.
- Dependency-Risiko prüfen: bei vorhandenem `AVAudioEngine`-Stack keine zusätzlichen externen Audio-Frameworks nötig.

## MVP-Scope (erste Iteration)

Drosseln auf das Minimum, das den Konzept-Wert validiert:

- Aufnahme + Analyse + Auto-Vorschlag.
- 3 Masker-Texturen (Pink Noise, Brown Noise, Regen).
- 3-Band-EQ statt 5.
- Preview mit fixer A-Konfig (kein A/B noch).
- 1 Profil im Speicher.
- Kein Daueralltag-Modus.

Wenn die Hörbarkeits-Validierung mit 5–10 ADHS-/Misophonie-Testnutzern positiv ausfällt, dann den vollen Funktionsumfang ausbauen.

## Test-Strategie

- Synthetische Test-Trigger generieren (Tippen-Sample, Schmatzen-Sample, HVAC-Drone) und prüfen, dass der Auto-Vorschlag plausibel ist (z. B. höhenlastiger Masker bei Tippen).
- Unit-Tests für Onset-Detection (Anzahl detektierter Events vs. erwartet).
- Unit-Tests für 1/3-Oktav-Banding (bekannte Sinus-Eingaben → Energie genau in einem Band).
- Manueller Hör-Test: kann ein Test-Trigger im Preview-Mix bei sinnvollem Pegel als „kaum noch wahrnehmbar" eingestuft werden?

## Offene Fragen für die Umsetzung

- Welche Mindest-Sample-Länge ist nötig, bevor das Spektrum stabil genug für einen Vorschlag ist? (Empirisch ermitteln, wahrscheinlich 15–30 s bei episodischen Triggern.)
- Soll der Nutzer mehrere Trigger gleichzeitig adressieren können (Tippen *und* HVAC) → eine kombinierte Spektrum-Analyse oder zwei separate Profile mit Crossfade?
- Welche Konzentrations-Selbsteinschätzung passt zur Zielgruppe – kurze 1–5-Skala oder validiertes Instrument (PSAS, NASA-TLX-Subset)?
