# Task 4: Bark precompute upstream (R2)

Status: completed
Created: 2026-05-21
Completed: 2026-05-25
Milestone: `milestone-14-performance-centralization`
Source: audit R2

## Goal

`SpectrumBandChartView`'s `Canvas` closure no longer walks the
full FFT spectrum to aggregate 24 Bark bands on every redraw.
Bark precomputed in the AudioEngine pipeline like third-octave.

## Why

- Third-octave mode in `SpectrumBandChartView` already uses the
  precomputed 31-band array (cheap).
- Octave mode derives from precomputed thirds (cheap, 10 power
  sums).
- **Bark mode** is the outlier: walks ~1024 bins on every Canvas
  redraw. M13 task-6 left the path centralised but still
  per-redraw, not per-frame.

## Scope

- AudioEngine gains a `currentBarkBands` (or `bark{Z,A,C}`)
  publish on `LiveAcousticState`, gated by the same
  `widgetSpectralWeightingRequirements` mechanism as octaves so
  Bark only computes when a Spectrum widget in Bark mode is
  visible.
- `SpectrumBandAggregator.barkBands` becomes the single
  implementation; AudioEngine calls it once per active
  weighting per frame.
- `SpectrumBandChartView.computeBandData(.bark)` reads
  `live.currentBarkBands` (or routes via `precomputedBark`
  param, mirroring `precomputedThirdOctave`). Falls back to the
  in-aggregator path only if precompute is missing (matches the
  existing third-octave fallback pattern).
- Update the `widgetSpectralWeightingRequirements` registration
  so a widget in Bark mode signals its need.

## Acceptance

- [x] `AudioEngine` emits Bark bands when at least one widget needs them;
  `widgetBarkBandsRequiredLock` is `false` by default → zero-cost.
- [x] `SpectrumBandChartView` Bark-mode `computeBandData` reads
  `precomputedBark` when non-empty; falls back to inline only on the
  first frame before `DashboardViewModel` registers the requirement.
- [x] `DashboardViewModel.updateWidgetSpectralWeightingRequirements`
  scans `settings["frequencyBands"]` and calls
  `setWidgetBarkBandsRequired(true)` when any Bark-mode widget is active.
- [x] iOS `** BUILD SUCCEEDED **`.
- [x] watchOS `** BUILD SUCCEEDED **`.

## What landed

### `LiveAcousticState`
`@Published var currentBarkBandsZ/A/C: [Float] = []` — empty by default;
populated only when `widgetBarkBandsRequired == true`.

### `AudioEngine`
- `private let widgetBarkBandsRequiredLock = OSAllocatedUnfairLock<Bool>(initialState: false)`
- `func setWidgetBarkBandsRequired(_ required: Bool)` — main-thread setter.
- Forwarding computed properties `currentBarkBandsZ/A/C`.
- In `processFFTFrame`: reads `needsBark` via lock; if `true`, calls
  `SpectrumBandAggregator.barkBands(frequencies:spectrum:)` for Z and
  optionally A/C (empty when weighting not active); otherwise emits
  three empty arrays.
- `updateUI` signature gains `barkBandsZ/A/C: [Float]`; assigns on main
  thread (guarded by `!isEmpty`).

### `DashboardViewModel`
`updateWidgetSpectralWeightingRequirements` now also scans
`settings["frequencyBands"]` for each spectral widget. Calls
`audioEngine.setWidgetBarkBandsRequired(needsBark)` after the existing
weighting call.

### `AudioWidgets.swift`
- `FrequencySpectrumWidget` gains `barkBandsForWeighting: [Float]`
  (picks Z/A/C); passes as `precomputedBark:` to `SpectrumBandChartView`.
- `SpectrumBandChartView` adds `let precomputedBark: [Float]`; `.bark`
  case in `computeBandData` uses it when non-empty, falls back inline
  otherwise.
- `OctaveBandWidget` passes `precomputedBark: []` (always `.thirdOctave`).
