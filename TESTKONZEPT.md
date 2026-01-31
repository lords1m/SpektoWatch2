# SpektoWatch - Detailliertes Testkonzept

## Übersicht

Dieses Dokument beschreibt das systematische Testkonzept für die SpektoWatch Audio-Analyse-App auf iPhone und Apple Watch. Es umfasst Funktions-, Integrations-, Performance- und Stresstests.

---

## 1. Testumgebung

### 1.1 Hardware
| Gerät | Mindestanforderung | Empfohlen |
|-------|-------------------|-----------|
| iPhone | iPhone 11 (iOS 16+) | iPhone 14 Pro oder neuer |
| Apple Watch | Series 6 (watchOS 9+) | Series 8/Ultra oder neuer |
| Referenz-Schallpegelmesser | Klasse 2 (IEC 61672) | Klasse 1 |
| Kalibrator | 94 dB @ 1 kHz | 94 dB @ 1 kHz |

### 1.2 Software
- Xcode 15+ mit iOS 17 SDK
- macOS Sonoma oder neuer
- Testflight für Beta-Tests

### 1.3 Testumgebungen
| Umgebung | Beschreibung | Verwendung |
|----------|--------------|------------|
| Leise Umgebung | < 35 dB(A), schallisoliert | Rauschboden-Tests |
| Büro | 40-50 dB(A) | Standard-Funktionstests |
| Laute Umgebung | > 80 dB(A) | Dynamikbereich-Tests |

---

## 2. iPhone App - Funktionstests

### 2.1 Audio Engine

#### TEST-IE-001: Audio-Aufnahme Start/Stop
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | App starten | Startbildschirm erscheint |
| 2 | "Live" Button drücken | Spektrogramm zeigt Echtzeit-Daten |
| 3 | In Mikrofon sprechen | Pegel steigt, Frequenzen sichtbar |
| 4 | "Stop" drücken | Anzeige stoppt, keine Abstürze |

**Pass-Kriterien:** Keine Abstürze, Latenz < 100ms

#### TEST-IE-002: Aufnahme in Datei
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | "Aufnahme" Button drücken | Recording-Indikator erscheint |
| 2 | 30 Sekunden aufnehmen | Dauer-Anzeige aktualisiert sich |
| 3 | "Stop" drücken | Datei wird gespeichert |
| 4 | Aufnahme in Liste öffnen | Datei ist abspielbar |

**Pass-Kriterien:** Datei existiert, Länge ±1s korrekt

#### TEST-IE-003: Mikrofon-Quellen Wechsel
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Einstellungen → Mikrofon öffnen | Liste verfügbarer Quellen |
| 2 | "Vorne" auswählen | Quelle wechselt ohne Unterbrechung |
| 3 | "Hinten" auswählen | Quelle wechselt ohne Unterbrechung |
| 4 | "Unten" auswählen | Quelle wechselt ohne Unterbrechung |

**Pass-Kriterien:** Nahtloser Wechsel, kein Audio-Dropout

---

### 2.2 FFT-Analyse (Erweiterte Frequenzanalyse)

#### TEST-IE-010: Fensterfunktion Wechsel
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Spektralanalyse-Labor öffnen | UI lädt korrekt |
| 2 | Hann → Hamming wechseln | Spektrum ändert sich leicht |
| 3 | Hamming → Blackman wechseln | Seitenkeulen werden kleiner |
| 4 | Blackman → Rectangular | Spektrale Leckage sichtbar |
| 5 | Während Live-Modus wechseln | Kein Absturz, flüssiger Übergang |

**Pass-Kriterien:** Kein Absturz, visuelle Unterschiede erkennbar

#### TEST-IE-011: Blockgröße Änderung
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Blockgröße 512 wählen | Zeitauflösung ~12ms, Freq.aufl. ~86Hz |
| 2 | Blockgröße 2048 wählen | Zeitauflösung ~46ms, Freq.aufl. ~21Hz |
| 3 | Blockgröße 8192 wählen | Zeitauflösung ~186ms, Freq.aufl. ~5Hz |
| 4 | Blockgröße 16384 wählen | Zeitauflösung ~372ms, Freq.aufl. ~2.7Hz |
| 5 | Schnell zwischen Größen wechseln | Kein Absturz |

**Pass-Kriterien:** Angezeigte Auflösungswerte stimmen, kein Absturz

#### TEST-IE-012: A/B Vergleichsmodus
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Vergleichs-Tab öffnen | Split-View erscheint |
| 2 | Config A: Hann/4096 einstellen | Linkes Spektrum zeigt Config A |
| 3 | Config B: Blackman/8192 einstellen | Rechtes Spektrum zeigt Config B |
| 4 | 1 kHz Testton abspielen | Unterschiede in Bins sichtbar |

**Pass-Kriterien:** Beide Spektren zeigen unterschiedliche Charakteristiken

---

### 2.3 Frequenzbewertung

#### TEST-IE-020: A-Bewertung Korrektheit
| Frequenz | Erwartete Dämpfung | Toleranz |
|----------|-------------------|----------|
| 31.5 Hz | -39.4 dB | ±1 dB |
| 125 Hz | -16.1 dB | ±1 dB |
| 1000 Hz | 0 dB | ±0.5 dB |
| 4000 Hz | +1.0 dB | ±0.5 dB |
| 8000 Hz | -1.1 dB | ±1 dB |

**Testmethode:** Sinus-Generator mit bekanntem Pegel, Vergleich mit Referenzgerät

#### TEST-IE-021: C-Bewertung Korrektheit
| Frequenz | Erwartete Dämpfung | Toleranz |
|----------|-------------------|----------|
| 31.5 Hz | -3.0 dB | ±1 dB |
| 125 Hz | -0.2 dB | ±0.5 dB |
| 1000 Hz | 0 dB | ±0.5 dB |
| 4000 Hz | -0.8 dB | ±0.5 dB |
| 8000 Hz | -3.0 dB | ±1 dB |

#### TEST-IE-022: Z-Bewertung (Linear)
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Z-Bewertung aktivieren | Keine Frequenzkorrektur |
| 2 | Weißes Rauschen abspielen | Flaches Spektrum |
| 3 | Mit A-Bewertung vergleichen | A zeigt tiefe Freq. gedämpft |

---

### 2.4 Kalibrierung

#### TEST-IE-030: Kalibrierung mit 94 dB Referenz
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Kalibrator auf Mikrofon setzen | 94 dB @ 1 kHz Signal |
| 2 | Angezeigten Wert ablesen | Wert notieren |
| 3 | Offset anpassen bis 94 dB angezeigt | Offset-Wert merken |
| 4 | Kalibrator entfernen | Pegel fällt auf Umgebungsniveau |
| 5 | App neu starten | Kalibrierung bleibt gespeichert |

**Pass-Kriterien:** Abweichung < ±1 dB nach Kalibrierung

#### TEST-IE-031: Gerätespezifische Kalibrierung
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | "Auf Gerätewert zurücksetzen" drücken | Empfohlener Offset wird geladen |
| 2 | Gerätemodell in Logs prüfen | Korrektes Modell erkannt |

---

### 2.5 Spektrogramm-Visualisierung

#### TEST-IE-040: Farbskala und Dynamik
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Leise Umgebung (< 40 dB) | Dunkle/blaue Farben dominieren |
| 2 | Mittlere Lautstärke (60 dB) | Grüne/gelbe Farben |
| 3 | Laute Umgebung (> 80 dB) | Rote Farben, keine Übersteuerung |
| 4 | Scroll-Geschwindigkeit ändern | Spektrogramm scrollt entsprechend |

#### TEST-IE-041: Bandstop-Filter
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Filter für 50 Hz aktivieren | 50 Hz Band wird unterdrückt |
| 2 | Netzbrummen-Quelle testen | 50 Hz nicht mehr sichtbar |
| 3 | Filter deaktivieren | 50 Hz wieder sichtbar |

---

### 2.6 Tongenerator

#### TEST-IE-050: Frequenz-Genauigkeit
| Einstellung | Erwartetes Ergebnis | Toleranz |
|-------------|---------------------|----------|
| 100 Hz | 100 Hz im Spektrum | ±1 Hz |
| 440 Hz | 440 Hz im Spektrum | ±1 Hz |
| 1000 Hz | 1000 Hz im Spektrum | ±1 Hz |
| 10000 Hz | 10000 Hz im Spektrum | ±5 Hz |

#### TEST-IE-051: Wellenform-Typen
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Sinus 1 kHz | Reine Linie bei 1 kHz |
| 2 | Rechteck 1 kHz | Oberwellen bei 3, 5, 7 kHz |
| 3 | Sägezahn 1 kHz | Alle Oberwellen sichtbar |
| 4 | Rauschen | Breitband-Spektrum |

#### TEST-IE-052: Memory Leak Test (Tongenerator)
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Tongenerator 50x starten/stoppen | Kein Memory-Anstieg |
| 2 | Instruments → Leaks prüfen | Keine Leaks |

---

## 3. Apple Watch App - Funktionstests

### 3.1 Watch Audio Engine

#### TEST-WA-001: Lokale Aufnahme
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Watch App starten | Dashboard erscheint |
| 2 | Aufnahme starten | Mikrofon-Zugriff wird angefragt |
| 3 | Permission erteilen | Audio-Aufnahme startet |
| 4 | In Watch sprechen | Pegel reagiert |
| 5 | Aufnahme stoppen | Keine Abstürze |

**Pass-Kriterien:** Funktioniert ohne iPhone-Verbindung

#### TEST-WA-002: Extended Runtime Session
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Aufnahme starten | Extended Session aktiv |
| 2 | 5 Minuten laufen lassen | Session bleibt aktiv |
| 3 | App in Hintergrund | Session läuft weiter |
| 4 | Handgelenk senken | Session pausiert nicht vorzeitig |

---

### 3.2 Watch Dashboard

#### TEST-WA-010: Widget-Konfiguration
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Dashboard-Einstellungen öffnen | Alle Widgets aufgelistet |
| 2 | Spektrogramm aktivieren | Widget erscheint |
| 3 | Oktavband aktivieren | Widget erscheint |
| 4 | Pegel-Widget aktivieren | Widget erscheint |
| 5 | Widgets neu anordnen | Reihenfolge ändert sich |

#### TEST-WA-011: Widget-Darstellung
| Widget | Prüfpunkte |
|--------|------------|
| Spektrogramm | Farben korrekt, scrollt |
| Oktavband | Alle 31 Bänder sichtbar |
| Pegel | LAF/LCF Werte korrekt |
| Min/Max | Werte aktualisieren sich |

---

## 4. Watch-iPhone Integration

### 4.1 WatchConnectivity

#### TEST-INT-001: Verbindungsaufbau
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Beide Apps starten | Verbindung wird hergestellt |
| 2 | "Verbunden" Status prüfen | Grüner Indikator auf beiden |
| 3 | Watch in/aus Reichweite | Status aktualisiert sich |

#### TEST-INT-002: Datenübertragung iPhone → Watch
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | iPhone: Live-Modus starten | Audio wird verarbeitet |
| 2 | Watch: Dashboard öffnen | Spektrogramm zeigt iPhone-Daten |
| 3 | iPhone: Lautstärke ändern | Watch zeigt Änderung |
| 4 | Latenz messen | < 200ms |

#### TEST-INT-003: Datenübertragung Watch → iPhone
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Watch: Mikrofon-Quelle "Watch" wählen | Befehl wird gesendet |
| 2 | iPhone: Quelle prüfen | Zeigt "Watch Mikrofon" |
| 3 | Watch: Aufnahme starten | iPhone empfängt Audio |

#### TEST-INT-004: Dashboard-Konfiguration Sync
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | iPhone: Dashboard-Config ändern | Änderung wird gesendet |
| 2 | Watch: Config prüfen | Neue Config aktiv |
| 3 | Watch App neu starten | Config bleibt erhalten |

---

### 4.2 Stabilitäts-Tests

#### TEST-INT-010: Parallelbetrieb Stress-Test
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | iPhone: Live-Modus starten | - |
| 2 | Watch: Dashboard öffnen | - |
| 3 | iPhone: FFT-Größe 10x wechseln | Kein Absturz |
| 4 | iPhone: Fenster-Funktion 10x wechseln | Kein Absturz |
| 5 | 10 Minuten laufen lassen | Beide Apps stabil |

**Pass-Kriterien:** Keine Abstürze, keine Memory-Leaks

#### TEST-INT-011: Verbindungsabbruch
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Normale Verbindung herstellen | - |
| 2 | iPhone in Flugmodus | Watch zeigt "Nicht verbunden" |
| 3 | iPhone aus Flugmodus | Verbindung wird wiederhergestellt |
| 4 | Daten werden wieder übertragen | Keine verlorenen Nachrichten |

#### TEST-INT-012: Message Queue Test
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Watch nicht erreichbar machen | - |
| 2 | iPhone: 5 Config-Änderungen senden | Nachrichten werden gequeued |
| 3 | Watch wieder erreichbar | Alle Nachrichten zugestellt |
| 4 | Logs auf Retry-Versuche prüfen | Max 3 Retries pro Nachricht |

---

## 5. Performance-Tests

### 5.1 CPU/Memory

#### TEST-PERF-001: CPU-Auslastung iPhone
| Szenario | Max. CPU | Messmethode |
|----------|----------|-------------|
| Idle | < 5% | Instruments |
| Live-Modus (FFT 8192) | < 30% | Instruments |
| Live-Modus + Watch-Sync | < 40% | Instruments |
| Aufnahme in Datei | < 35% | Instruments |

#### TEST-PERF-002: CPU-Auslastung Watch
| Szenario | Max. CPU | Messmethode |
|----------|----------|-------------|
| Dashboard (empfangen) | < 20% | Instruments |
| Lokale Aufnahme | < 40% | Instruments |
| Lokale FFT | < 50% | Instruments |

#### TEST-PERF-003: Memory-Verbrauch
| App | Max. Memory | Messmethode |
|-----|-------------|-------------|
| iPhone | < 150 MB | Instruments |
| Watch | < 30 MB | Instruments |

#### TEST-PERF-004: Memory-Leak-Test
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | 1 Stunde kontinuierlich laufen | Memory stabil |
| 2 | Instruments Leaks-Profil | Keine Leaks |
| 3 | 100x Start/Stop-Zyklen | Memory kehrt zu Baseline zurück |

---

### 5.2 Latenz

#### TEST-PERF-010: Audio-zu-Display Latenz
| Messung | Max. Latenz | Methode |
|---------|-------------|---------|
| iPhone Spektrogramm | < 100ms | Hochgeschwindigkeitskamera |
| Watch (via iPhone) | < 300ms | Hochgeschwindigkeitskamera |
| Watch (lokal) | < 150ms | Hochgeschwindigkeitskamera |

#### TEST-PERF-011: UI-Reaktionszeit
| Aktion | Max. Reaktionszeit |
|--------|-------------------|
| Button-Tap | < 100ms |
| Slider-Bewegung | < 50ms |
| View-Wechsel | < 300ms |

---

### 5.3 Batterie

#### TEST-PERF-020: Batterie-Verbrauch iPhone
| Szenario | Max. Verbrauch/Stunde |
|----------|----------------------|
| Live-Modus | < 15% |
| Aufnahme | < 20% |
| Idle (Hintergrund) | < 2% |

#### TEST-PERF-021: Batterie-Verbrauch Watch
| Szenario | Max. Verbrauch/Stunde |
|----------|----------------------|
| Dashboard (empfangen) | < 10% |
| Lokale Aufnahme | < 20% |

---

## 6. Edge Cases & Grenzwert-Tests

### 6.1 Audio-Grenzen

#### TEST-EDGE-001: Sehr leise Signale
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Schallisolierter Raum (< 30 dB) | Rauschboden sichtbar |
| 2 | Pegel ablesen | Realistischer Wert (25-35 dB) |
| 3 | Keine falschen Peaks | Stabile Anzeige |

#### TEST-EDGE-002: Sehr laute Signale
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | 100+ dB Quelle (Vorsicht!) | Kein Clipping-Crash |
| 2 | Pegel wird limitiert | Max ~120 dB angezeigt |
| 3 | Warnung bei Übersteuerung | Visuelle Warnung |

#### TEST-EDGE-003: Frequenzgrenzen
| Frequenz | Erwartetes Verhalten |
|----------|---------------------|
| 20 Hz | Am unteren Rand sichtbar |
| 20 kHz | Am oberen Rand sichtbar |
| < 20 Hz | Wird nicht angezeigt |
| > 22 kHz | Wird nicht angezeigt (Nyquist) |

---

### 6.2 System-Events

#### TEST-EDGE-010: Unterbrechungen
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Während Aufnahme anrufen | Aufnahme pausiert |
| 2 | Anruf beenden | Aufnahme kann fortgesetzt werden |
| 3 | Siri aktivieren | Audio-Session wird unterbrochen |
| 4 | Siri beenden | Audio-Session wird wiederhergestellt |

#### TEST-EDGE-011: Hintergrund/Vordergrund
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | App in Hintergrund | Audio stoppt (oder läuft mit Berechtigung) |
| 2 | App wieder öffnen | Sofortige Wiederaufnahme |
| 3 | 5 Minuten im Hintergrund | Kein Absturz beim Zurückkehren |

#### TEST-EDGE-012: Speicher-Druck
| Schritt | Aktion | Erwartetes Ergebnis |
|---------|--------|---------------------|
| 1 | Viele Apps öffnen | Memory-Warning möglich |
| 2 | SpektoWatch reagiert | Caches werden geleert |
| 3 | App bleibt funktional | Keine Abstürze |

---

## 7. Regressions-Tests

### 7.1 Nach jedem Build

| Test-ID | Beschreibung | Kritisch |
|---------|--------------|----------|
| TEST-IE-001 | Audio Start/Stop | ✓ |
| TEST-IE-010 | Fenster-Wechsel | ✓ |
| TEST-IE-011 | Blockgröße-Wechsel | ✓ |
| TEST-WA-001 | Watch Aufnahme | ✓ |
| TEST-INT-001 | Verbindung | ✓ |
| TEST-INT-010 | Parallelbetrieb | ✓ |

### 7.2 Vor jedem Release

Alle Tests aus Abschnitten 2-6 müssen bestanden werden.

---

## 8. Test-Protokoll Vorlage

```
Test-ID: _______________
Datum: _______________
Tester: _______________
Build: _______________

iPhone Modell: _______________  iOS Version: _______________
Watch Modell: _______________   watchOS Version: _______________

Ergebnis: [ ] PASS  [ ] FAIL  [ ] BLOCKED

Beobachtungen:
_________________________________________________________________
_________________________________________________________________

Screenshots/Logs angehängt: [ ] Ja  [ ] Nein

Signatur: _______________
```

---

## 9. Bekannte Einschränkungen

1. **Apple Watch Mikrofon-Qualität**: Begrenzte Frequenzauflösung unter 100 Hz
2. **Bluetooth-Latenz**: Watch-Daten haben ~100-200ms Verzögerung
3. **Extended Runtime**: Max. 30 Minuten Hintergrund-Audio auf Watch
4. **Simulator**: Kein echtes Audio, nur Test-Generator

---

## 10. Automatisierte Tests (XCTest)

### Unit Tests (empfohlen zu implementieren)

```swift
// FFTProcessorTests.swift
func testFFTMagnitudeCalculation()
func testWindowFunctionGeneration()
func testBlockSizeReconfiguration()
func testFrequencyBinCalculation()

// FrequencyWeightingTests.swift
func testAWeightingAt1kHz()
func testAWeightingAt100Hz()
func testCWeightingCurve()

// WatchConnectivityTests.swift
func testMessageQueueing()
func testRetryLogic()
func testSpectrogramDataSerialization()
```

### UI Tests (XCUITest)

```swift
// SpektoWatchUITests.swift
func testLiveModeStartStop()
func testSettingsNavigation()
func testFFTConfigurationUI()
```

---

## Anhang A: Referenz-Frequenzen für Kalibrierung

| Frequenz | Typische Quelle |
|----------|-----------------|
| 50 Hz | Netzbrummen (Europa) |
| 60 Hz | Netzbrummen (USA) |
| 440 Hz | Kammerton A |
| 1000 Hz | Kalibrator-Standard |

## Anhang B: dB(A) Referenzwerte

| Pegel | Typische Quelle |
|-------|-----------------|
| 30 dB(A) | Flüstern |
| 50 dB(A) | Normale Unterhaltung |
| 70 dB(A) | Staubsauger |
| 85 dB(A) | Schwerlastverkehr |
| 100 dB(A) | Diskotheque |
| 120 dB(A) | Schmerzgrenze |
