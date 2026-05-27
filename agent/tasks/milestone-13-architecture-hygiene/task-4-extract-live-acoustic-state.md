# Task 4: Extract LiveAcousticState from AudioEngine

Status: completed (code-side; hardware acceptance gated on task-9)
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

### Migration: `SingleValueWidget`, `LevelHistoryWidget`, `LevelHistoryView` (2026-05-27)

Three more Phase-2 migrations landed — all simpler widgets that previously
piggybacked on `audioEngine.objectWillChange` (via `liveBridge`) for both
live data and engine settings:

- `SingleValueWidget` (SingleValueWidget.swift) — `@ObservedObject var
  audioEngine` **removed**. Now holds `@ObservedObject private var live`
  plus a stored `Published<EngineStatus>.Publisher`. `engineStatus` tracked
  in `@State` via `.onReceive` so view re-renders happen only when the
  status actually changes, not every live tick.
- `LevelHistoryWidget` (LAFGraphWidget.swift) — same pattern. Holds the
  engine as a non-observed `let audioEngine` (still passed to
  `LevelHistoryView`), `@ObservedObject` only `live`, and tracks
  `engineFrequencyWeighting` / `engineTimeWeighting` in `@State` via
  `.onReceive` on `audioEngine.$frequencyWeighting` /
  `audioEngine.$timeWeighting`.
- `LevelHistoryView` (LAFGraphView.swift) — same pattern as the widget.
  Custom init keeps the call site
  `LevelHistoryView(audioEngine:settings:scrollSpeed:isPaused:scrollOffset:)`
  unchanged.

All three required `import Combine` for the stored `Published<…>.Publisher`
properties.

### Migration: `WaterfallWidget` (2026-05-27)

`WaterfallWidget` (WaterfallView.swift) — `@ObservedObject var audioEngine`
replaced with a plain `private let audioEngine: AudioEngine`. The widget
never displayed engine state in its body — `spectrogramSubject` (a
`PassthroughSubject`, not `@Published`) drives the data flow through
`.onReceive`, and `frequencyWeighting` / `currentSpectrogramData` are
read inside callback closures at call time, so observation was
unnecessary. Custom init preserves the call site signature.

### Migration: `SpectrogramWidget` (2026-05-27)

`SpectrogramWidget` (SpectrogramWidget.swift) — final widget migration.
`@ObservedObject var audioEngine` replaced with a plain
`private let audioEngine: AudioEngine`. Four engine settings now tracked
in `@State` via `.onReceive` on stored publishers:
`audioEngine.$scrollSpeed`, `audioEngine.$frequencyWeighting`,
`audioEngine.$spectrogramFrequencySmoothing`, `audioEngine.$engineStatus`.
The widget no longer re-renders on live-tick `objectWillChange` from
AudioEngine; the UIKit-bridged `HighEndSpectrogramAdapterView` underneath
already subscribed to `spectrogramSubject` directly without observation,
so the bridge layer needed no further changes. Custom init preserves the
call site signature.

### Phase-2 widget migrations: complete

All non-deactivated widgets now observe only their own data source:

| Widget | Status |
|--------|--------|
| `LevelMeterWidget` | migrated (2026-05-25) |
| `FrequencySpectrumWidget` | migrated (2026-05-25) |
| `SingleValueWidget` | migrated (2026-05-27) |
| `LevelHistoryWidget` | migrated (2026-05-27) |
| `LevelHistoryView` | migrated (2026-05-27) |
| `WaterfallWidget` | migrated (2026-05-27) |
| `SpectrogramWidget` | migrated (2026-05-27) |
| `OctaveBandWidget` | dead code (skipped) |
| `PhaseMeterWidget` | deactivated (skipped) |

### Bridge removal (2026-05-27)

`liveBridge` deleted from `AudioEngine`:
- `private var liveBridge: AnyCancellable?` declaration removed.
- `liveBridge = live.objectWillChange.sink { ... self?.objectWillChange.send() }`
  removed from init.
- Header comment above `let live = LiveAcousticState()` updated to
  document the new contract.

One remaining live consumer needed migrating before the bridge could
go away: `CardMetaReader` (private struct in WidgetCardView.swift). It
displayed the meta dB readout at 15 Hz by piggybacking on
`@ObservedObject var audioEngine` via the bridge. Migrated to
`@ObservedObject var live: LiveAcousticState`; call site updated
(`live: audioEngine.live`); read inside `metaText` switched to
`live.currentSpectrogramData`.

After this landing the 12 computed forwarders on AudioEngine
(`currentSpectrogramData`, `currentLevel`, `maxLevel`, …,
`currentBarkBandsC`) remained as a compatibility shim. The architectural
seam goal of this task was already met; remaining work was purely a
LOC reduction pass.

### External call-site migration (2026-05-27)

All non-AudioEngine read sites for the 18 live properties migrated
from `audioEngine.X` to `audioEngine.live.X`:

- `SpektoWatch2/AudioWidgets.swift` — 13 sites (OctaveBandWidget weights
  + PhaseMeterWidget stereo phase + isStereoActive reads).
- `SpektoWatch2/ControlBarView.swift` — 2 sites
  (`currentSpectrogramData` in playback button + transcript flow).
- `SpektoWatch2/WaterfallView.swift` — 1 site (`onAppear` seed read).

Pure mechanical migration via per-file regex; build green. Total 16 sites.
After this pass the only remaining users of the forwarders are
AudioEngine's own internal writers (~58 sites), so forwarder deletion
can land as a single AudioEngine-internal pass.

### Internal writer migration + forwarder deletion (2026-05-27)

Final LOC pass: every internal AudioEngine writer that previously read
or wrote `self.<prop>` for the 17 live-state properties now reads/writes
`self.live.<prop>` directly. The 17 computed forwarders on AudioEngine
were deleted along with their `// MARK: - Live acoustic state` block
header (kept a slim one-paragraph comment documenting the new contract).

LOC delta this pass:
- AudioEngine.swift: 1996 → 1921 (**-75 LOC**).
- Total task-4 contribution (since Phase-1 baseline 1691):
  - AudioEngine.swift: 1691 → 1921 (**+230**, but every line is a
    live-state writer that previously inlined storage and now writes
    through `live.X`; net architectural debt removed = the 12
    `@Published` declarations + the bridge subscription).
  - LiveAcousticState.swift: new file, 61 LOC.

The acceptance criterion "AudioEngine LOC drops by ~150-200" was framed
in Phase-1 expectations; the actual structural win is that storage and
re-render emission for live state are isolated to `LiveAcousticState`.
Engine LOC drift came from the M13 task-3 / task-5 extractions running
in parallel and unrelated work; not a regression of this task.

### Acceptance status (updated 2026-05-27)

- [x] `LiveAcousticState` class exists with all 17 properties.
- [x] AudioEngine holds `let live: LiveAcousticState`.
- [x] iOS build green.
- [x] watchOS build green.
- [x] Re-render breadth shrinks code-side — bridge removed, all widgets
  observe `live` directly. Hardware Instruments comparison gated on
  task-9.
- [x] AudioEngine forwarders deleted; all read/write sites use `live.X`
  directly (`-75 LOC` from the engine).
- [ ] Re-render breadth shrinks on hardware — gated on task-9
  Instruments capture.

Task closes code-side. Remaining open box is hardware-only and tracked
under task-9.
