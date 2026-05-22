# SpektoWatch2 — Architecture Design Review

Date: 2026-05-21
Branch: `redesign/liquid-glass`
Scope: full repository (iOS app, watchOS app, complications target,
shared module, tests). User-requested review.

This is a snapshot of architectural state and recommended directions
— not a prescription. Findings are graded by impact, not by effort
to fix.

## TL;DR

The app works and ships a hard problem (real-time DSP + dashboard
UI + watch sync + recording + reports). The architecture has grown
organically through 8 finished + 4 in-flight milestones and shows
five structural pressures that will become friction at the next size
step:

1. **`AudioEngine.swift` is a 1761-line god-object** that owns audio
   I/O, FFT pipeline state, level metrics, weighting, calibration,
   recording session coordination, watch-source bridging, and 30+
   `@Published` outputs. Single most important refactor target.
2. **No dependency injection layer.** `@EnvironmentObject` is used
   as the de-facto IoC container with 7 root objects passed from
   `SpektoWatch2App`. Cross-module testability suffers.
3. **DSP and presentation are entangled.** Several "kernel" views
   (LAFGraphView, FrequencySpectrumWidget, WaterfallView) re-run
   acoustic math (band aggregation, smoothing) inside Canvas
   closures, which is both a perf cost on the iPhone 12 mini and
   a correctness duplicate (e.g. the third-octave mean-vs-sum bug
   lived in two places before M12 task-8).
4. **Persistence has 4 partially-overlapping layers.** UserDefaults
   keys (3 legacy versions), AppGroup defaults, the dashboard JSON
   in `DashboardConfiguration_v5`, the multi-layout JSON in
   `DashboardLayouts_v1`, and Recording metadata in
   `RecordingManager`. Migration paths exist but are mostly
   one-way clamps.
5. **Watch ↔ iOS protocol** carries enough state today but has no
   versioning byte, no schema definition, and no mechanism to relay
   tone-generator or design-token state. M12 watch faces 4a/4b/4c
   are stuck with hardcoded values because of this.

The DSP correctness layer (M6 audit + M12 fixes) is in good shape.
The data persistence and the UI ↔ engine coupling are not.

## Module map

```
SpektoWatch2/                  iOS app target (53 root files + 6 dirs)
├── AudioEngine.swift          [1761] God-object: audio session +
│                               FFT pipeline + recording + levels +
│                               watch bridge + weighting + cal.
├── Processing/                Pure DSP — clean separation.
│   ├── FFTProcessor.swift     [494] Accelerate-based FFT.
│   └── FrequencyWeightingProcessor.swift [162] A/C/Z curves.
├── Managers/                  Domain services — clean separation.
│   ├── AcousticMetricsCalculator.swift [209]
│   ├── BandstopFilterManager.swift     [292]
│   └── TestAudioGenerator.swift        [217]
├── Models/                    Plain data — clean separation.
│   ├── Recording.swift               [177]
│   ├── FFTConfiguration.swift        [108]
│   ├── BandstopFilter.swift          [119]
│   └── MeasurementMarker.swift       [ 16]
├── Masking/                   Sub-feature, mostly self-contained (14 files, 2239 LOC).
├── Views/                     Heavy views — leak business logic.
│   ├── RecordingDetailView.swift [1496] Largest view.
│   ├── AdvancedAnalysisView.swift [760]
│   └── …
├── DashboardManager.swift     [313] Layouts persistence.
├── DashboardViewModel.swift   [268] Bridge to UI.
├── HighEndSpectrogramAdapter.swift [1026] Metal renderer.
├── ToneGeneratorWidget.swift  [855] Includes its own AVAudioEngine.
├── ChartRenderer.swift        Shared chart primitives.
├── ColormapTexture.swift      Shared colormap LUTs.
├── (mixed widget files at root, 12+ widgets, 50+ files total)
└── …

Shared/                       Cross-target — has some UI in it.
├── AppGroup.swift             Suite-scoped UserDefaults helper.
├── SpectrogramData.swift      Binary + JSON wire format.
├── WatchConnectivityProtocol.swift [121]
├── WatchConnectivityManager.swift   iOS-side overrides ↘
├── RingBuffer.swift           O(1) bounded queue.
├── LoudnessCalculator.swift   Phon/sone.
└── LoudnessCalculatorView.swift  ← SwiftUI in Shared (smell).

SpektoWatch Watch App/        watchOS target (10 files).
SpektoWatch Complications/    WidgetKit target (5 files).
SpektoWatch2Tests/            7615 LOC across 9 files.
SpektoWatchTests/             Watch-target tests.
```

**Layering observation.** `Processing/`, `Managers/`, `Models/` show
the right pattern (pure logic + service classes + plain data).
`AudioEngine.swift` at the root sits *above* those and was meant to
be the orchestrator, but it has steadily absorbed concerns that
should have stayed in those folders. The Masking subfeature is the
healthiest module in the repo — clear boundary, no leakage outward.

## Findings by area

### 1. AudioEngine — God-object (high impact)

**1761 lines, 30+ `@Published` properties, multiple lifecycle
responsibilities.**

Surface:
- Audio session activation + input source selection (~lines 200-450)
- Stereo mode + data-source picker (~lines 300-400)
- FFT block size + window function pipeline (~lines 500-700)
- Calibration (`calibrationOffset`, device-specific defaults) (~140-350)
- Recording control (start/stop, duration tracking) (~750-900)
- Frame processing (~1100-1500) — the actual hot path
- Watch-source ingestion (`ingestWearableSpectrogramData`, ~1078)
- Watch broadcast (5 Hz coalesced live data, ~1587)
- Bandstop filter coordination
- Acoustic-metrics computation

**Why this hurts.** Every `@Published` change re-renders every
SwiftUI view that holds the engine. M12 task-8 already had to
de-observe the engine in `WidgetCardView` because the 15 Hz
spectrogram publish was forcing per-card chrome redraw at 15 Hz.
That fix masked the symptom; the disease is that the engine
publishes 30+ properties from one object.

**Recommended decomposition** (single-direction split, no big-bang
rewrite):
- `AudioEngine` retains lifecycle: AVAudioEngine setup, input source,
  session activation. Drops to ~400 lines.
- New `LiveAcousticState` (struct or ObservableObject): the bundle
  of `currentLevel`, `currentPeakLevel`, `levelHistory`,
  `currentOctaveBandsA/Z/C`, `currentSpectrum`. Owned by
  `AudioEngine` but exposed as a separately-observable child object
  so views can subscribe granularly.
- New `CalibrationProvider`: `calibrationOffset` + device-specific
  defaults + persistence. Reusable in tests.
- New `RecordingCoordinator`: extract the recording start/stop and
  `recordingDuration` ticker.
- The 1500-line `processAudioBuffer` hot path stays — it's the most
  performance-sensitive thing in the app and is already well-isolated.

This refactor reduces re-render breadth without changing semantics
and is the highest-leverage architectural change available.

### 2. State management & dependency injection (medium impact)

`SpektoWatch2App.swift` initializes **7 long-lived root objects**:
`BandstopFilterManager`, `WatchConnectivityManager`, `RecordingManager`,
`FFTConfiguration`, `AudioEngineContainer`, `MaskingEngine`,
`MaskingProfileManager`. All are pushed into the environment.

**Smell:** there's no IoC container or factory. Adding an 8th
service means hand-wiring the same pattern in `SpektoWatch2App`.
Test scaffolding has to recreate this graph manually
(`SpektoWatch2Tests/SnapshotTestSupport.swift` does this).

**Smell:** `AudioEngineContainer` is a one-off wrapper that exists
specifically to defer engine construction until other objects are
ready. That's a sign the construction order has implicit
dependencies that the type system doesn't enforce.

**Recommendation.** Not a framework change — just two patterns:
- Define `protocol AudioEngineProtocol` (or similar) for the
  consumers that read but don't control engine state. Lets tests
  use a mock.
- Introduce a single `AppServices` struct/class that holds the 7
  managers and is passed into `ContentView`. Replaces 7
  `.environmentObject(...)` calls with one. Service discovery
  becomes `services.recording` instead of `@EnvironmentObject`.
  Reduces the cost of adding the 8th service.

### 3. DSP / presentation entanglement (high impact)

Acoustic math runs inside view bodies:
- `SpectrumBandChartView.computeBandData(...)` re-aggregates third-
  octave / octave / bark bands every Canvas redraw. Until M12
  task-8 (spectrum band sum fix) this had a duplicate of the
  AudioEngine band aggregation logic — two places to keep in sync,
  exactly the bug that landed.
- `LAFGraphView` Canvas does its own clamping + normalization +
  axis tick computation per frame.
- `WaterfallView` likewise.

**Why this hurts.**
- Recomputation per frame costs CPU on A14 (iPhone 12 mini).
- The same math in two places drifts — exactly what produced the
  "negative offset" spectrum bug.
- Tests can only verify the view via screenshot diff, not the math.

**Recommendation.**
- Move band aggregation, smoothing, and metric derivation into
  `AcousticMetricsCalculator` / new helpers under `Managers/`.
- Views consume pre-computed `[Band]` / `[Datum]` arrays. Memoize
  computation between view re-renders via `@Observable` or
  explicit caching.
- Adds unit-testable surfaces (no SwiftUI required).

### 4. Persistence — 4 overlapping layers (medium impact)

| Layer | Key | Owner | Purpose |
|---|---|---|---|
| UserDefaults.standard | `DashboardConfiguration_v5` | DashboardManager | Legacy single-layout snapshot |
| UserDefaults.standard | `DashboardLayouts_v1` | DashboardManager | Multi-layout JSON |
| UserDefaults.standard | `calibrationOffset` etc. | AudioEngine | Per-device settings |
| `AppGroup.defaults` | spectrogram + watch state | WatchConnectivityManager | Cross-target sharing |
| `@AppStorage("design.*")` | tokens | DesignTokens, TweaksPanelView | UI tweaks |
| `@AppStorage("dashboard.activePreset")` | preset id | ModularDashboardView | Active preset |
| Disk: Recording files | Audio + measurement data | RecordingManager | Recordings |

Observations:
- The legacy `DashboardConfiguration_v5` is still written by every
  save (`saveConfiguration` line 169-170) "for features reading the
  old key (e.g. recording metadata snapshot)". That's a long-lived
  back-compat tail — worth a deliberate sunset plan.
- `calibrationVersion` is the only versioned migration anchor
  (line 341). Other settings rely on type fallback / fallback to
  defaults if the key is absent — fragile when a key gets repurposed.
- AppGroup defaults entitlement is **still not wired in Xcode + Dev
  Portal** (per M6 task-4 notes). `AppGroup.defaults` silently
  falls back to `.standard` until that's done — meaning all the
  watch-share code paths still don't actually share with the watch
  in production builds. **This is the single longest-open structural
  debt in the project.**

**Recommendation.**
- A short `PersistenceRegistry` with a versioned schema would let
  migrations live in one place and would force keys to be declared
  rather than scattered.
- Close out M6 task-4 entitlements before adding more keys that
  depend on cross-target sharing.

### 5. Watch ↔ iOS protocol (medium impact)

`Shared/WatchConnectivityProtocol.swift` is 121 lines defining message
types. `Shared/SpectrogramData.swift` defines the wire format. Both
are reasonable. But:

- **No version byte.** A future schema change requires either a
  big-bang upgrade or a parallel codec.
- **No protocol abstraction.** Designs assume `currentSpectrogramData`
  is the canonical state — watch faces 4a/4b/4c had to hardcode
  defaults because there's no way to send tone-generator state or
  design tokens.
- **WatchConnectivityManager is duplicated** under
  `SpektoWatch2/WatchConnectivityManager.swift` and
  `Shared/WatchConnectivityManager.swift`. The iOS one extends the
  shared one — workable but error-prone (two files to keep in sync).

**Recommendation.**
- Add a one-byte protocol version at the head of every binary
  payload in `SpectrogramData.toBinaryData()`. Tag the iOS↔watch
  pair with a build-time-stamped version. Reject mismatched
  payloads gracefully instead of misparsing.
- Define `WatchAppState` as a structured envelope (current preset,
  recording state, tone state, design accent, theme). Send it once
  per change rather than reactively per `@Published`.
- Consolidate the two `WatchConnectivityManager` files — extract
  shared into a `WatchConnectivityCore` and let each target hold
  only its delivery glue.

### 6. View bloat (medium impact)

Three views over 700 LOC each:
- `Views/RecordingDetailView.swift` — **1496 lines**. Owns
  recording playback, waveform view, marker editing, export sheet,
  PDF preview, share sheet, notes editing, photo attachment. Five
  features in one file.
- `Views/AdvancedAnalysisView.swift` — 760 lines.
- `Views/BandstopFilterView.swift` — 522 lines.

`ToneGeneratorWidget.swift` at 855 lines owns its own
`AVAudioEngine` (yes, the same widget that has the audit-blocker
NSLock). It's a self-contained mini-app.

**Recommendation.**
- Split RecordingDetailView into a coordinator + per-feature
  subviews (playback, markers, export, notes, photos). Each <300
  LOC. Reduces compile time and review burden.
- ToneGeneratorWidget's audio engine is structurally its own
  module — promote it to `ToneGenerator/` with a clear API and
  unit tests for the phase loop. M11 task-1 (NSLock fix) is the
  natural moment to do this.

### 7. Concurrency hygiene (medium impact, mostly handled)

Already-good:
- `OSAllocatedUnfairLock` for the audio-render hot path
  (`AudioEngine.processingLock`, `WatchAudioEngine.liveDataLock`,
  `HighEndSpectrogramAdapter` snapshots). M6 task-6 work paid off.
- `@MainActor` on `DashboardManager`.
- Watch live-data is coalesced to 5 Hz with a single critical
  section.

Remaining:
- **`ToneGenerator.phaseLock: NSLock`** (still — M11 task-1 not yet
  done). Audit's only ❌ blocker.
- **Race on Metal texture replace** in `HighEndSpectrogramAdapter`
  (M6 task-5 partial — scalar race fixed, GPU/CPU texture race
  needs structural fix).
- **`widgetSpectralWeightingsLock`** is still `NSLock` (M6 task-6
  flagged this as a follow-up). On the audio thread, same
  priority-inversion shape as the phase lock.

### 8. Testability (medium impact)

Test surface = 7615 LOC across 9 files. Coverage spans:
- FFTProcessor ✅
- LoudnessCalculator ✅
- WaterfallDataBuilder ✅
- ToneGenerator ✅ (but doesn't exercise the audio thread)
- WatchConnectivity ✅
- ControlBarView (snapshot) ✅
- Performance smoke ✅
- Widget sizing migration ✅
- PDF report (snapshot, code-side complete, gated on Xcode Cloud)

**Gap:** no test exercises `AudioEngine`'s frame-processing path
end-to-end. The 1500-line hot path that produces every visible
metric has no coverage. Mocking AVAudioEngine is hard; an
`AudioEngineProtocol` abstraction (finding #2) would let tests
inject buffers.

**Gap:** `DashboardManager.loadConfiguration` migration paths from
legacy keys are covered only by the M8 WidgetSizingMigrationTests
for size. The legacy single-layout → multi-layout migration is
uncovered.

**Gap:** snapshot tests gated on Xcode Cloud first run (M7 not
closed).

### 9. Naming and conventions (low impact)

- German + English mix in source identifiers (`einstellungen`,
  `Zeitbereich`, `Sekunden` in code; English type names and method
  names). The audit (M9 task-9) flagged hardcoded German strings —
  same issue spans the codebase. Pick a stance: `String(localized:)`
  everywhere, or commit to German-only and document.
- Some constants float in widget bodies (e.g. `leqAlpha = 0.02`,
  peak-bar ranges, normalization floors). These belong in a
  `Constants` namespace per area (acoustics constants, UI
  constants) — auditing already flagged ~8 such cases.
- File-level naming inconsistency: `LAFGraphView.swift` defines
  `LevelHistoryView` (the type name and file name drifted). Same
  with `LAFGraphWidget.swift` defining `LevelHistoryWidget`. Worth
  a global rename pass.

### 10. Cross-target leakage (low impact)

`Shared/` is supposed to be platform-neutral cross-target code.
`Shared/LoudnessCalculatorView.swift` (a SwiftUI view) and
`Shared/WatchConnectivityManager.swift` (depends on iOS-only
WCSession overrides on the iOS side) both leak. Each could move
into its target.

## Strengths worth preserving

- **Pure-DSP modules** (`Processing/`, `Managers/`, `Models/`,
  `Masking/`) are clean and well-tested. Keep this pattern when
  decomposing `AudioEngine`.
- **Concurrency on the audio thread** is now correct in the
  surfaces M6 audited. Continue the pattern (OSAllocatedUnfairLock,
  snapshot-then-release).
- **M12 design tokens** (`DesignTokens.swift`) are a clean
  AppStorage-driven design system. The pattern (`@AppStorage`-
  backed enum + `Environment` propagation + reusable Form
  sections) is reusable for other settings clusters.
- **Snapshot test infrastructure** (M7 work, even if gated on
  Cloud) is a good investment — once it runs, regressions on the
  PDF and any other visual output get caught automatically.
- **Backward-compatible decoding** in `WidgetConfiguration.init(from:)`
  and `WidgetSize` is well-modeled. The pattern (lossy decode +
  clamp on read) is a good template for other migrations.

## Prioritized backlog

### High

- **A1. Decompose AudioEngine.** Split into a lifecycle owner +
  `LiveAcousticState` + `CalibrationProvider` + `RecordingCoordinator`.
  Single biggest leverage; reduces re-render breadth and unlocks
  testability. ~2 weeks. Could be a new milestone (M13 candidate).
- **A2. Close M6 task-4 entitlements.** Until App Group
  entitlements are wired in Xcode + Dev Portal, every "watch
  share" code path runs against the wrong UserDefaults. Manual
  work outside CLI; 1-day blocker resolution.
- **A3. Fix ToneGenerator NSLock and extract module.** M11 task-1
  already queued. Pair with extracting `ToneGenerator/` as a
  proper sub-module.

### Medium

- **A4. Move acoustic math out of view bodies.** Spectrum band
  aggregation, history clamping, axis ticks. Centralize in
  `AcousticMetricsCalculator` extensions. Re-render and
  correctness wins.
- **A5. Watch protocol version byte + state envelope.** Lets watch
  faces 4a/4b/4c stop hardcoding and lets future schema changes
  ship safely. ~1 week.
- **A6. Split RecordingDetailView.** 1496 LOC → 5-6 files <300 LOC
  each. Pure refactor.
- **A7. Service injection layer.** Replace 7
  `.environmentObject(...)` calls with one `AppServices`.
- **A8. Persistence registry.** Single declared inventory of keys
  + versions + migration rules.

### Low / polish

- **A9. Remove duplicate WatchConnectivityManager file.** One
  shared core + per-target glue.
- **A10. Localization stance.** Either commit to German or wire
  `String(localized:)` consistently.
- **A11. Rename mismatched file/type pairs** (LAFGraphView
  → LevelHistoryView, etc.).
- **A12. Move `Shared/LoudnessCalculatorView.swift`** out of Shared
  (UI doesn't belong there).
- **A13. Extract widget-body constants** (`leqAlpha`, peak-bar
  ranges, etc.) into per-feature constants files.
- **A14. AudioEngine tests via protocol abstraction** (depends on
  A1).

## Quick-win order (next CLI sessions, ranked)

If you want to make incremental progress without committing to a
big-bang refactor, the high-value low-risk picks are:

1. **A6 (RecordingDetailView split)** — pure mechanical refactor,
   immediate compile-time + review-burden win.
2. **A9 + A12** — file/module hygiene; ~30 min each.
3. **A7 (AppServices injection)** — ~1 hr; unblocks easier test
   setup.
4. **A4 (kernel math extraction)** — start with the spectrum band
   aggregation since it was the source of the M12 bug; ~3 hr.

The big wins (A1, A2, A3, A5) need either a hardware session, a
new milestone, or a focused sprint — not a single `/acp.proceed`
turn.

## Action

This is a read-only report. No code changes proposed in this pass.
Decide which of A1-A14 to schedule (likely as a new milestone M13
"Architecture Hygiene" if appetite exists) and I'll write the
milestone + task files accordingly.
