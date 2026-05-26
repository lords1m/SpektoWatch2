# Task 3: Per-band Leq in AcousticMetricsCalculator (R3)

Status: completed
Created: 2026-05-21
Completed: 2026-05-25
Milestone: `milestone-14-performance-centralization`
Source: audit R3 + M9 task-4 finding #4 (hardcoded leqAlpha)

## Goal

Move the per-band Leq EMA out of
`SpectrumBandChartView.updateLeq(...)` into the central metrics
layer. Widgets read pre-computed band-Leq arrays.

## Why

- Today each `SpectrumBandChartView` instance maintains its own
  `leqValues: [Float]` EMA at `leqAlpha = 0.02`. Two Spectrum
  widgets on the same dashboard = double the EMA work.
- Hardcoded constant; M9 task-4 finding #4 flagged it as a
  per-widget tunable that should either be exposed or documented.
- Math is identical to what's needed for any future "per-band
  Leq" feature elsewhere (recording detail view, watch
  complications). Centralising unblocks that.

## Scope

- `AcousticMetricsCalculator` gains an internal
  `bandLeqLinear: [Float]` buffer (31 entries per active
  weighting). Initialised on first frame.
- `updateMetrics(...)` accepts the third-octave band array and
  exponentially smooths in linear power, returning the smoothed
  band-Leq array.
- `LiveAcousticState` gains `bandLeq: [Float]` (active
  weighting) or `bandLeqZ/A/C` (per-weighting, mirroring
  `currentOctaveBands*`).
- `SpectrumBandChartView.updateLeq` deleted; the orange overlay
  line reads `live.bandLeq` directly.
- `leqAlpha` becomes a configurable parameter on the metrics
  calculator (default 0.02). Exposed as a widget setting in a
  follow-up if M9 task-4's product decision favors it.

## Acceptance

- [x] `SpectrumBandChartView` has no `@State leqValues` / `updateLeq` /
  `resetLeq` / `.onChange` EMA work.
- [x] Live frequency-spectrum widget reads pre-computed band Leq from
  `audioEngine.bandLeqZ/A/C` via `leqThirds` parameter.
- [x] iOS `** BUILD SUCCEEDED **`.
- [x] watchOS `** BUILD SUCCEEDED **`.
- [x] 4 new unit tests: seed behaviour, closed-form EMA match, reset
  clears buffers, empty-input skips update.

## What landed

### `MetricsResult` struct (`AcousticMetricsCalculator.swift`)

New top-level struct returned by `updateMetrics`:
```swift
struct MetricsResult {
    var levels: [String: Float]
    var bandLeqZ: [Float]
    var bandLeqA: [Float]
    var bandLeqC: [Float]
}
```

### `AcousticMetricsCalculator` additions

- `let leqBandAlpha: Float = 0.02` — exposed so tests can read
  the coefficient without an extra accessor.
- `private var bandLeqLinearZ/A/C: [Float] = []` — lazy-initialised
  on the first frame that carries band data; no allocation on class
  init.
- `updateMetrics` gains `bandsZ/A/C: [Float] = []` parameters.
  Inside the lock, for each non-empty bands array the buffer is
  seeded on the first call (count mismatch) and EMA'd on subsequent
  calls (linear power domain, same formula as the old per-widget
  code). Returned as part of `MetricsResult`.
- `reset()` also clears the three band buffers so `bandLeqZ/A/C`
  re-seed cleanly after session restart.

### `LiveAcousticState`

Added:
```swift
@Published var bandLeqZ: [Float] = Array(repeating: -120.0, count: 31)
@Published var bandLeqA: [Float] = Array(repeating: -120.0, count: 31)
@Published var bandLeqC: [Float] = Array(repeating: -120.0, count: 31)
```

### `AudioEngine`

- Three forwarding computed properties (`bandLeqZ/A/C`) alongside
  `currentOctaveBandsZ/A/C`.
- `processFFTFrame` unpacks `MetricsResult`; passes
  `bandsZ: displayOctaveBandsZ`, `bandsA: processedA != nil ? ... : []`,
  `bandsC: processedC != nil ? ... : []`.
- `updateUI` signature gains `bandLeqZ/A/C: [Float]`; assigns
  `self.bandLeqZ/A/C` on the main thread (guarded by `!isEmpty`).

### `AudioWidgets.swift`

- `FrequencySpectrumWidget` gains `bandLeqForWeighting: [Float]`
  (picks Z/A/C based on active weighting).
- `SpectrumBandChartView` adds `let leqThirds: [Float]`; removes
  `@State leqValues`, `@State sampleCount`, `leqAlpha`;
  removes `updateLeq(with:)`, `resetLeq()`, `.onChange(of: mode)`
  reset, and `.onAppear { resetLeq(); updateLeq(...) }` calls.
- New pure helper `computeLeqBandData(mode:leqThirds:)`:
  - `.thirdOctave` → pass through 31 values
  - `.octave` → `SpectrumBandAggregator.octaveBands(fromThirds:)`
  - `.bark` → `[]` (no Leq overlay)
- `OctaveBandWidget` also wired with `bandLeqForWeighting`.

### Tests (`AcousticMetricsCalculatorTests.swift`)

8 existing tests updated: `levels["LAF"]` → `result.levels["LAF"]`
etc. to match `MetricsResult` return type.

4 new tests:
- `testBandLeqSeedsOnFirstFrameAndStaysConstant`: constant input
  → EMA seeded at target and stays there.
- `testBandLeqEMAMatchesClosedForm`: step from 70 dB → 50 dB,
  N=150 frames; closed-form `x0·(1−α)^N + x1·(1−(1−α)^N)` ±0.5 dB.
- `testBandLeqClearsOnReset`: warm up at 80 dB, reset, re-seed
  at 40 dB — must not carry pre-reset value.
- `testBandLeqSkippedWhenBandsNotProvided`: `bandsZ` only →
  `bandLeqA/C` are empty.
