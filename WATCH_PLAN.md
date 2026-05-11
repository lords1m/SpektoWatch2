# SpektoWatch — watchOS Plan

A roadmap for the Apple Watch part of SpektoWatch: where it is now, what it
should become, and how to get there in phases that don't break each other.

The core insight: **the watch is not just a small phone screen — it is a
different role**. Designing it as a tiny mirror of the iPhone dashboard wastes
the platform. Designing it as a *wearable acoustic sensor* with its own
purposes opens up complications, Live Activities, and standalone use.

---

## 1 · Inventory — where we are

**Watch targets present**
- `SpektoWatch Watch App/` — the watch app
- `WatchAudioEngine` — local 2048-point FFT, sends processed spectrogram data to phone
- `WatchContentView` — `TabView` over Dashboard / Spectrogram / Level Meter
- `WatchDashboardView` — 3-column LazyVGrid of widgets, glass-style cards
- Widgets: `WatchSpectrogramWidget`, `WatchLevelMeterWidget`,
  `WatchSingleValueWidget`, `WatchLoudnessWidget`
- `Shared/WatchOperatingMode.swift` — explicit companion / wearable mic /
  standalone vocabulary shared between targets
- `Shared/WatchConnectivityManager.swift` — watch-side WCSession plumbing
- `Shared/WatchValueMapping.swift`, `Shared/WatchWidgetConfiguration.swift`,
  `Shared/SpectrogramData.swift` — shared models

**Missing entirely**
- No WidgetKit complications (Inline / Circular / Rectangular / Modular)
- No Smart Stack widget
- No Live Activity for ongoing recordings
- No standalone recording / local persistence on watch
- No hearing-safety / dose-tracking surface (the most natural watch feature)
- No notifications (threshold breach, recording reminders)
- No haptic design beyond a single `.success` tap on record

**What works**
- Dashboard widget grid with a configurable layout pushed from phone via
  `watchDashboardConfig`
- Watch can independently start its own `WKExtendedRuntimeSession` and run
  local FFT for ~1 h
- Phone-side recording is mirrored to watch via `WatchConnectivityManager`
- Watch dashboard widgets now bind to `WatchAudioEngine.liveData`, so companion
  and wearable-mic data are routed through a single stream.
- The watch hot path no longer sends raw audio; it sends processed
  `SpectrogramData` over the binary `sendMessageData` path.

---

## 2 · Problems with the current setup

The watch code works, but several rough edges become problems as soon as
we try to extend it.

### 2.1 — Two roles fighting for the same code
`WatchSpectrogramWidget`, `WatchSingleValueWidget`, `WatchLoudnessWidget` all
contain branches like:
```swift
.onReceive(audioEngine.$currentSpectrogramData) { ... isRecording ? ... : nothing }
.onReceive(connectivityManager.$spectrogramData) { ... !isRecording ? ... : nothing }
```
The widget is implicitly toggling between *companion mode* (phone is master)
and *wearable mic mode* (watch is master) based on `audioEngine.isRecording`.
This branching is duplicated, easy to get wrong, and there is no third role
("standalone recording, no phone").

**Status, May 2026 recheck:** largely fixed. `WatchAudioEngine` now owns
`operatingMode` and publishes `liveData`; the dashboard widgets consume that
stream instead of duplicating source-selection logic. Remaining work is to make
mode changes part of the protocol instead of local notification/string-message
handling.

### 2.2 — Raw audio shipped as JSON
`Shared/WatchConnectivityManager.swift:42-61` JSON-encodes raw `[Float]`
samples and sends them via `WCSession.sendMessage`. At 44.1 kHz × 4 bytes
that's ~170 KB/s of *binary* data, ballooned to ~400-500 KB/s when JSON-encoded.
WatchConnectivity simply cannot deliver that reliably; it'll throttle, drop,
or crash. The phone-side already has a binary `SpectrogramData.toBinaryData()`
path — the watch-side audio path was never upgraded.

**Status, May 2026 recheck:** fixed. `WatchAudioEngine` no longer calls
`sendAudioData`; it only sends processed `SpectrogramData` when the Apple Watch
mic is selected. The unused `sendAudioData`, `audioData`, `AudioData`, and
`0x02` audio-packet handling were removed with their old tests.

### 2.3 — Watch FFT has the same kind of issues we just fixed on phone
`WatchAudioEngine.processAudioBuffer` (line 162-219):
- per-callback `Array(repeating: 0, count: frameCount)` allocation (line 168)
- per-callback `Array(samples.prefix(fftSize))` (line 193)
- per-frame scalar loop `for magDB in magnitudes { frameEnergy += pow(10.0, magDB / 10.0) }` (line 198-200) — should be one `vDSP_dotpr` against pre-computed `pow(10, x/10)` weights
- per-frame `freqs = [Float](repeating: 0, count: binCount); for i in 0..<binCount { freqs[i] = ... }` (line 209-212) — these never change, ought to be computed once
- watch is *more* power-constrained than the phone, yet has *more* unforced inefficiencies

**Status, May 2026 recheck:** fixed for the current Phase 1 scope. The watch now reuses
`monoSampleScratch`, `fftInputScratch`, `linearPowerScratch`, and precomputed
`binFrequencies`; the LAF energy loop is vectorized, `performFFT` no longer
returns `Array(fftMagnitudes)` each frame, and debug min/max/sum uses vDSP.

### 2.4 — `WatchConnectivityManager` is a kitchen sink
The same class on the watch handles: spectrogram receive, audio send, dashboard
config sync, mic-source selection, recording start/stop, gain, frequency
weighting, application context fallback. It's 325 lines and tightly couples
state, encoding, and transport. Hard to test, hard to extend.

### 2.5 — No watchOS-native surfaces
A measurement instrument that lives on your wrist should at minimum surface a
**current dB value as a complication**. We have none. That means the only way
to see what's happening is to open the app — which defeats most of the point
of having a watch app at all.

---

## 3 · The proposed architecture

### 3.1 — Three explicit operating modes

Make the implicit role-switching explicit. A single `WatchOperatingMode` enum,
owned by `WatchAudioEngine`, with clean transitions and a documented data
contract per mode:

| Mode | Source | Storage | Use case |
|---|---|---|---|
| `.companion` | Phone records, watch displays | Phone | Phone-led measurement; watch is a secondary screen |
| `.wearableMic` | Watch mic, watch processes locally + streams metrics to phone | Phone (merges as a track) | User wants ear-level reading even though phone is in pocket |
| `.standalone` | Watch mic, watch stores locally, sync later | Watch (until sync) | Phone too far / out of reach; watch is on its own |

Widgets stop branching on `isRecording`; they observe a single
`@Published var liveData: SpectrogramData?` exposed by `WatchAudioEngine` that
internally selects based on the active mode.

### 3.2 — A typed data contract

Replace the stringly-typed `["type": "...", "value": ...]` dictionaries with
a `Codable` enum:

```swift
enum WatchControlMessage: Codable {
    case startRecording(mode: WatchOperatingMode)
    case stopRecording
    case setGain(Float)
    case setFrequencyWeighting(FrequencyWeighting)
    case setMicrophoneSource(MicrophoneSource)
    case dashboardConfig(WatchDashboardConfig)
    case markEvent(timestamp: Date, label: String?)   // NEW — see §3.5
}
```

Encode once with the binary `PropertyListEncoder` and ship via
`sendMessageData` (already used for spectrogram payloads). Eliminates
ad-hoc `["type": "..."]` parsing on both sides and makes the protocol
self-documenting.

For the high-rate spectrogram path, keep the existing binary
`SpectrogramData.toBinaryData()`. **Stop sending raw audio entirely**
(see §3.4).

### 3.3 — Split `WatchConnectivityManager` into transport + state

```
Shared/Watch/
├── WatchTransport.swift          // WCSession plumbing only (send / receive bytes)
├── WatchProtocol.swift           // typed messages, packet headers, encoders
└── WatchSessionCoordinator.swift // observable state: reachability, mode, last metrics
```

Transport is a thin wrapper. State holds `@Published` properties for SwiftUI.
Tests for the protocol can be pure unit tests with no WCSession dependency.

### 3.4 — Watch never sends raw audio — only processed metrics

The phone has a much better processing pipeline. The watch should not try to
ship its raw audio to the phone for "high-quality re-processing"; the cost
(bandwidth, battery, latency) is wildly out of proportion to the benefit.

Instead, in `.wearableMic` mode the watch sends:
- Broadband level (LAeq, LAFmax) at ~10 Hz
- Coarse spectrogram (32 log-spaced bands × 10 Hz) — same shape as today
- Recording markers and timestamps

The phone records this stream as a *secondary track* in the measurement file
(alongside its own mic, when both are running). This is far more useful than
a delayed raw-audio re-FFT, and the file format already supports multiple
tracks (`MeasurementDataFormat.thirdOctaveBandCount * 3` is the precedent).

### 3.5 — New surfaces (the actual point of having a watch app)

**WidgetKit complications** — the highest-impact addition. Four families:

| Family | Content | Tap action |
|---|---|---|
| `accessoryInline` | "82 dB(A)" current LAeq | Open app |
| `accessoryCircular` | Ring + current dB number | Open app |
| `accessoryRectangular` | LAeq · Peak · Recording elapsed | Open app |
| `accessoryCorner` | Ring + dB | Open app |

These are powered by a small `WatchMetricSnapshot` model written to
`UserDefaults` (App Group) by the watch app every ~30 s, plus a `TimelineProvider`
that reads it. When recording is active, complications also get push-style
updates via WidgetKit's `reloadTimelines(ofKind:)`.

**Live Activity** — when a recording is in progress (any mode), present a
Live Activity on the iPhone Lock Screen + Dynamic Island showing:
- elapsed time, current LAeq, peak
- a Stop button (interactive widget)

The watch reflects the same Live Activity natively (watchOS 11+ shows iPhone
Live Activities in the Smart Stack automatically — free win).

**Smart Stack widget** — a single `accessoryRectangular` widget on watchOS 10+
showing the most recent measurement summary (last LAeq, peak, time since
recording ended, label). Lives in the Smart Stack so the user pulls it up
with a wrist turn.

**Threshold notification** — local notification when the watch detects
sustained dB(A) above a threshold (default 85 dB SPL for 1 min) — a hearing
safety nudge. Implemented entirely on watch; no phone roundtrip needed.

### 3.6 — Standalone recording

Add a small per-recording binary file format on watch:

```
{watch-recording-uuid}.swr     // SpektoWatch Recording, watch flavour
  header (magic, version, fps, fftBands)
  frames [ timestamp:Float, laeq:Float, lafmax:Float, bands:[Float] ]
```

On `.standalone` mode end (or when phone reachability returns), transfer via
`WCSession.transferFile`. The phone-side `RecordingManager` learns to ingest
these and merge them into the recordings list with a "watch" badge.

---

## 4 · Phased rollout

Each phase is a self-contained improvement that ships independently. Earlier
phases unblock later ones; later phases never depend on speculative work.

### Phase 1 — Foundation (1-2 days)
*Goal: clean up the worst current issues without changing behaviour.*

1. **Stop sending raw audio over WCSession.** Remove `sendAudioData` from
   the watch hot path. Phone-side `WatchConnectivityManager.didReceiveMessage`
   handler for `audioData` becomes dead code; mark and remove.
   **Status:** done.
2. **Apply the same vDSP cleanup we did on phone** (cf. PERFORMANCE_REVIEW.md):
   - precompute `freqs`, `bandWeights`, `linearGains`
   - `vDSP_dotpr` for the LAF energy loop
   - reuse a `monoSampleScratch` buffer
   - `OSAllocatedUnfairLock` for the FFT (or remove the lock entirely if
     the audio thread is the only writer)
   **Status:** done for the current Phase 1 scope.
3. **Introduce `WatchOperatingMode`** enum and route the existing branching
   through it. No new behaviour — just remove the `if isRecording { ... } else { ... }`
   duplication.
   **Status:** done for the watch UI/data stream. Protocol-level mode commands
   remain Phase 2 work.

### Phase 2 — Typed protocol & split coordinator (2-3 days)
*Goal: make the watch protocol something we can extend without breaking.*

1. New `Shared/Watch/` directory. Move WCSession plumbing to `WatchTransport`,
   typed messages to `WatchProtocol`, observable state to `WatchSessionCoordinator`.
2. Migrate phone-side `WatchConnectivityManager` to the same protocol — both
   sides speak the same `WatchControlMessage` Codable.
3. Add unit tests for `WatchProtocol` round-trip encoding.

### Phase 3 — Complications (2-3 days)
*Goal: give the watch app a presence on the watch face.*

1. Add a WidgetKit extension target, share App Group with watch app.
2. `WatchMetricSnapshot` (UserDefaults-backed) + 5-second rolling average
   writer in `WatchAudioEngine`.
3. Implement four complication families. `TimelineProvider` returns the
   latest snapshot; `reloadTimelines(ofKind:)` on every recording start/stop.
4. Smart Stack `accessoryRectangular` widget for "last measurement summary".

This is the highest *user-visible value per line of code* in the whole plan.

### Phase 4 — Standalone mode + Live Activity (3-5 days)
*Goal: the watch can do useful work alone, and the phone shows ongoing
recordings in modern surfaces.*

1. `.swr` file format + `WatchRecordingStore` (write while recording, no I/O
   on the audio thread — same async-queue + bounded ring pattern we used in
   `MeasurementDataWriter`).
2. `WCSession.transferFile` on phone reachability, with progress reporting.
3. Phone-side `RecordingManager` ingest path; recordings list shows watch
   recordings with a small "watch" SF Symbol badge.
4. `ActivityKit` Live Activity for ongoing recordings (iPhone-side; watch
   gets it for free via Smart Stack).

### Phase 5 — Hearing safety & polish (2-3 days)
*Goal: features that justify why you'd want this on a watch in the first
place.*

1. **Daily dose tracking** — running OSHA 8-hour 85 dB(A) TWA. Persisted in
   App Group `UserDefaults` with daily reset. Surfaced as a complication
   ("dose: 47 %") and a notification when crossing 50 / 80 / 100 %.
2. **Marker button on the dashboard** — one tap to stamp a `markEvent`
   into the active recording. Useful for noting "this is the loud thing"
   without taking the phone out.
3. **Haptic vocabulary** — distinct haptics for: recording start (`.start`),
   recording stop (`.stop`), threshold breach (`.notification`), marker
   added (`.click`). Today everything is `.success`.
4. **Accessibility** — VoiceOver labels on every widget; Dynamic Type
   support for the value displays; reduce-motion respect on the spectrogram
   waterfall.

---

## 5 · Proposed file layout

```
SpektoWatch Watch App/
├── App/
│   ├── SpektoWatchApp.swift
│   └── WatchContentView.swift
├── Audio/
│   ├── WatchAudioEngine.swift
│   ├── WatchOperatingMode.swift          // NEW
│   └── WatchRecordingStore.swift         // NEW (Phase 4)
├── Views/
│   ├── WatchDashboardView.swift
│   ├── WatchSpectrogramView.swift
│   └── WatchLevelMeterView.swift
├── Widgets/                              // dashboard widgets (existing)
│   └── ...
└── HearingSafety/                        // NEW (Phase 5)
    └── DoseTracker.swift

SpektoWatch Watch Widgets/                // NEW WidgetKit extension target
├── SpektoWatchWidgets.swift              // bundle root
├── Complications/
│   ├── InlineComplication.swift
│   ├── CircularComplication.swift
│   ├── RectangularComplication.swift
│   └── CornerComplication.swift
├── SmartStackWidget.swift
└── WatchSnapshotProvider.swift

Shared/Watch/                             // moved out of Shared/
├── WatchProtocol.swift                   // typed Codable messages
├── WatchTransport.swift                  // WCSession plumbing
├── WatchSessionCoordinator.swift         // observable state
├── WatchMetricSnapshot.swift             // UserDefaults-backed
└── WatchValueMapping.swift               // existing
```

---

## 6 · Risks & open questions

- **Battery during `.wearableMic`** — `WKExtendedRuntimeSession` is
  ~1 hour. For longer recordings we either accept the cap or move to
  HealthKit-based foreground sessions. Phase 4 will need to surface a
  remaining-time indicator regardless.
- **Watch ↔ phone transport reliability** — `sendMessage` is bursty; the
  current adaptive throttle (100-500 ms based on thermals) is roughly right
  but worth re-measuring after the protocol cleanup.
- **App Group entitlement** — required for the WidgetKit extension to read
  watch-app state. Trivial but a real configuration step.
- **Complication update frequency** — WidgetKit caps reload rates; the
  `reloadTimelines` call needs to be intelligent (every ~30 s during
  recording, not per FFT frame) to avoid hitting the budget.
- **iOS / watchOS minimum** — currently targeting 26.2. Live Activities,
  interactive widgets, and Smart Stack rectangular complications all
  require watchOS 10+, which we have. Verify the full feature set is
  available on the deployment target before Phase 3.

---

## 7 · What this plan deliberately does **not** do

- **No SwiftUI rewrite.** The current `WatchDashboardView` widget grid is
  good. We're refactoring the *engine and protocol*, not replacing the UI.
- **No SwiftData migration.** Persistence on watch is a single binary file
  per recording — SwiftData would be overkill and adds memory pressure.
- **No on-device CoreML / sound classification.** Tempting (e.g. "is this
  speech vs traffic vs music?"), but a separate, larger initiative that
  should be evaluated on its own merits, not bundled here.

---

## 8 · The single most-recommended next step

If only one thing gets done from this plan, do **Phase 3 (complications)**.
Reason: an acoustic instrument on the wrist with no presence on the watch
face is barely worth installing. Once a current-dB complication exists,
the whole product feels different — and Phase 3 is independent of every
other phase, so it can land in isolation.

If a *second* thing is possible, do **Phase 2 (typed protocol & split
coordinator)**. Phase 1's watch hot-path cleanup is now complete enough that
the next risk is protocol shape: string dictionaries and WCSession plumbing are
still coupled to observable state.

---

*Plan written May 2026 against the current `main` branch. Rechecked against the
workspace on May 10, 2026.*
