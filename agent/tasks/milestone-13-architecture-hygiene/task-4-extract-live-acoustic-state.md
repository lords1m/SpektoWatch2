# Task 4: Extract LiveAcousticState from AudioEngine

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-13-architecture-hygiene`
Source finding: A1 phase 2 in `2026-05-21-architecture-review.md`
Depends on: task-3.

## Goal

Bundle the live-metric `@Published` properties into a separate
ObservableObject child so views can observe only what they need.
This is the work that fully fixes the 15 Hz re-render breadth
problem that M12 task-8 only papered over.

## Landed (2026-05-21) — Phase 1: seam in place

The full architectural seam is established. The actual re-render
breadth shrinkage requires per-widget migration to observe
`audioEngine.live` directly, which can ship incrementally (Phase 2,
below) without further engine changes.

### New file

- `SpektoWatch2/LiveAcousticState.swift` (61 LOC) —
  `final class LiveAcousticState: ObservableObject` with all 12 live
  `@Published` properties moved off AudioEngine: `currentLevel`,
  `maxLevel`, `minLevel`, `levelHistory`, `currentPeakLevel`,
  `currentSpectrogramData`, `currentSpectrum`, `currentOctaveBands`
  + Z/A/C variants, `currentStereoPhase`, `isStereoActive`.

### AudioEngine changes

- New `let live = LiveAcousticState()` — the storage now lives here.
- 12 computed forwarders replace the 12 `@Published` declarations,
  one per property:
  ```swift
  var currentLevel: Float {
      get { live.currentLevel }
      set { live.currentLevel = newValue }
  }
  ```
  Every existing read site (`audioEngine.currentLevel`, etc.) and
  every write site (the audio frame-processing path, watch ingest,
  recording snapshots) continues to compile unchanged.
- `liveBridge: AnyCancellable?` subscription in init forwards
  `live.objectWillChange` into the engine's own
  `objectWillChange.send()`. Existing `@ObservedObject var
  audioEngine: AudioEngine` consumers therefore still re-render
  on live ticks — no behavior change for the current widget set.

### Consumer migrations (3 sites)

`@Published` projections (`$currentSpectrogramData`) are not
available through computed forwarders, so the three
`.onReceive(audioEngine.$currentSpectrogramData)` call sites moved
to `.onReceive(audioEngine.live.$currentSpectrogramData)`:

- `LAFGraphView.swift:149`
- `LAFGraphWidget.swift:72`
- `SingleValueWidget.swift:106`

Pure mechanical migration. No write-side changes; the views still
receive the same data at the same cadence.

### LOC delta

| File | Before | After | Delta |
|---|---:|---:|---:|
| AudioEngine.swift | 1691 | 1753 | **+62** |
| LiveAcousticState.swift | — | 61 | +61 (new) |

Engine grew because 12 computed forwarders take more lines than 12
`@Published` declarations. This is expected for Phase 1; the
forwarders + bridge are deletable code once Phase 2 migrates the
widgets and the engine no longer needs to publish these on its own
behalf. AudioEngine drops the listed forwarders + bridge in Phase 2.

## Phase 2 — Widget migration (not landed; incremental)

To realise the re-render breadth reduction, each widget that
observes audio data via `@ObservedObject var audioEngine: AudioEngine`
needs to migrate to `@ObservedObject var live = audioEngine.live`
(or accept `live` as a separate property). At that point AudioEngine's
12 forwarders + bridge can be deleted.

Affected widgets (10):
- `SpectrogramWidget` — currently observes audioEngine for the
  whole engine state; needs to add `@ObservedObject var live`.
- `WaterfallWidget` — same.
- `LevelHistoryView` (LAFGraphView) — currently observes engine;
  its `.onReceive` already moved to `live.$...` so partial
  migration is in flight.
- `FrequencySpectrumWidget` — observes engine for spectrum reads.
- `LevelMeterWidget` — reads `audioEngine.currentLevel /
  currentPeakLevel`.
- `SingleValueWidget` — reads from `currentSpectrogramData`.
- `PhaseMeterWidget` (deactivated in M12, can be skipped).
- `MaskingEntryWidget` — does not observe live state directly.
- `ToneGeneratorWidget` — independent audio engine.
- `SpektralanalyseLaborWidget` — observes fftConfig.

Each migration is a 1-line change in the widget's `body` + a new
`@ObservedObject var live: LiveAcousticState`. Estimated 30 min
total. Recommended as a single follow-up landing once Phase 1
soaks on hardware.

## Validation

- `xcodebuild -scheme SpektoWatch2 -destination 'generic/platform=
  iOS Simulator' build` → `** BUILD SUCCEEDED **`.
- All existing `audioEngine.X` read sites unchanged.
- All audio-thread writers unchanged.
- Local simulator broken; functional acceptance gated on M13 task-9.

## Acceptance status

- [x] `LiveAcousticState` class exists with all 12 properties.
- [x] AudioEngine holds `let live: LiveAcousticState`.
- [x] iOS build green.
- [x] watchOS build green (verified — watch target shares
  `Shared/SpectrogramData.swift` only; no LiveAcousticState touch).
- [ ] AudioEngine LOC drops by ~150-200 — **not met in Phase 1**
  (+62 LOC because of the forwarders). Will hit the drop in Phase
  2 when forwarders + bridge are deleted.
- [ ] Re-render breadth shrinks on hardware — **gated on Phase 2**
  (widget migration) + hardware Instruments capture (task-9).

Task stays in_progress until Phase 2 + hardware verification close
the remaining checkboxes.

## Phase 2 progress (2026-05-25)

### Pilot migration: `LevelMeterWidget`

`LevelMeterWidget` (AudioWidgets.swift) is the first full Phase-2 migration:
- `@ObservedObject var audioEngine: AudioEngine` **removed** entirely.
- `@ObservedObject private var live: LiveAcousticState` added.
- Custom `init(audioEngine:settings:)` initialises `_live` from `audioEngine.live`
  so the call site `LevelMeterWidget(audioEngine: audioEngine, settings: ...)` is
  unchanged.
- `audioEngine.currentLevel` → `live.currentLevel`;
  `audioEngine.currentPeakLevel` → `live.currentPeakLevel`.

### Migration: `FrequencySpectrumWidget` (2026-05-25)

`FrequencySpectrumWidget` (AudioWidgets.swift) — second Phase-2 migration:
- `@ObservedObject var audioEngine: AudioEngine` **kept** (needed for
  `audioEngine.frequencyWeighting.rawValue`, a non-live setting).
- `@ObservedObject private var live: LiveAcousticState` added.
- Custom `init(audioEngine:settings:)` initialises `_live` from `audioEngine.live`;
  call site `FrequencySpectrumWidget(audioEngine: audioEngine, settings: ...)` unchanged.
- Live reads migrated: `audioEngine.currentSpectrogramData` → `live.currentSpectrogramData`;
  `audioEngine.currentOctaveBandsA/C/Z` → `live.currentOctaveBandsA/C/Z`;
  `audioEngine.bandLeqA/C/Z` → `live.bandLeqA/C/Z`;
  `audioEngine.currentBarkBandsA/C/Z` → `live.currentBarkBandsA/C/Z`.

Note: `OctaveBandWidget` (also in AudioWidgets.swift) is dead code — both
`.frequencyDisplay` and `.octaveBands` widget types route to `FrequencySpectrumWidget`
in WidgetCardView. Skipped.

### Remaining Phase-2 widget migrations (not yet landed)

| Widget | Live reads | Complexity |
|--------|-----------|------------|
| `LAFGraphView` / `LAFGraphWidget` | currentSpectrogramData (via onReceive on `live.$`) | Already correct — no change needed |
| `SingleValueWidget` | currentSpectrogramData (via onReceive on `live.$`) | Already correct — no change needed |
| `WaterfallView` | currentSpectrogramData via spectrogramSubject | Medium |
| `SpectrogramWidget` → `HighEndSpectrogramAdapterView` | spectrogramSubject (UIKit bridge) | High — deferred |
| `PhaseMeterWidget` | currentStereoPhase, isStereoActive | N/A — deactivated |

Bridge deletion milestone: once WaterfallView + SpectrogramWidget are migrated (or
LAFGraph/SingleValue confirmed needing no change), remove `liveBridge` from
`AudioEngine` and delete the 12 computed forwarders (~74 LOC). AudioEngine
drops to its target ≤ 1680 LOC.
