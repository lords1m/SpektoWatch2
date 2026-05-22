# Task 4: Extract LiveAcousticState from AudioEngine

Status: pending
Created: 2026-05-21
Milestone: `milestone-13-architecture-hygiene`
Source finding: A1 phase 2 in `2026-05-21-architecture-review.md`
Depends on: task-3.

## Goal

Bundle the live-metric `@Published` properties into a separate
ObservableObject child so views can observe only what they need —
the second phase of the AudioEngine decomposition. This is the
work that fully fixes the 15 Hz re-render breadth problem that
M12 task-8 only papered over.

## Scope

- New `SpektoWatch2/LiveAcousticState.swift` —
  `final class LiveAcousticState: ObservableObject` exposing:
  - `currentLevel`, `currentPeakLevel`, `minLevel`, `maxLevel`
  - `levelHistory: [Float]`
  - `currentSpectrogramData: SpectrogramData?`
  - `currentOctaveBands*` (Z/A/C + active)
  - `currentSpectrum`
  - `currentStereoPhase`, `isStereoActive`
- AudioEngine owns one `LiveAcousticState` instance and publishes
  it as `@Published private(set) var live: LiveAcousticState`.
  AudioEngine writes into `live.*` on the main thread in the
  existing dispatch points (`emitSpectrogramData` etc.).
- Existing consumers that previously read e.g.
  `audioEngine.currentLevel` are migrated to
  `audioEngine.live.currentLevel` (or hold
  `@ObservedObject var live = audioEngine.live` directly).
- AudioEngine keeps forwarding stub computed properties for one
  release cycle to avoid touching every consumer in this task.

## Non-Goals

- Changing how levels are computed.
- Splitting the live state by widget type (one bag is sufficient
  for now; per-feature subsets are a future optimisation).
- Touching `AcousticMetricsCalculator`.

## Acceptance

- AudioEngine.swift LOC drops by ~150-200 (the @Published live
  block).
- Views can subscribe to `audioEngine.live` instead of the engine
  itself; chrome doesn't re-render when only live state changes.
- iOS build green; LAF reads on hardware look unchanged.
- Existing tests pass.
- Spot-check on hardware: WidgetCardView re-render count under
  live audio drops measurably (Instruments).
