# Task 6: Kernel math extraction (DSP out of view bodies)

Status: pending
Created: 2026-05-21
Milestone: `milestone-13-architecture-hygiene`
Source finding: A4 in `2026-05-21-architecture-review.md`

## Goal

Move acoustic math out of SwiftUI view bodies. Removes the
duplicate-code class of bugs (the M12 spectrum "negative offset"
came from band aggregation living in two places) and improves
re-render performance.

## Scope

- **Spectrum band aggregation.** Move
  `SpectrumBandChartView.computeBandData(...)` (and its helper
  `thirdOctaveBands(...)`) into
  `SpektoWatch2/Managers/AcousticMetricsCalculator.swift` or a
  new `Managers/SpectrumBandAggregator.swift`. View consumes a
  pre-computed `[Band]` array.
- **Level-history normalization.** Move clamping + axis-tick
  computation in `LAFGraphView` into a `LevelHistoryDataModel`
  helper that the view consumes.
- **Watch modular face mini spectrogram.** Move the in-line
  Canvas mag→cell normalization into a helper so the iOS modular
  face (if added later) can share it.
- View bodies render data, never recompute it.

## Non-Goals

- Touching the Metal-backed spectrogram (`HighEndSpectrogramAdapter`
  is already a separated kernel).
- Changing band-aggregation math (M12 task-8 fixed correctness).
- Changing the WaterfallDataBuilder (already separated).

## Acceptance

- The two duplicated `thirdOctaveBands` functions
  (AudioEngine.computeDisplayThirdOctaveBands + the widget's
  fallback) become one. The widget loses its fallback or routes
  through the same helper.
- View bodies for the three migrated views are ≥ 30% smaller.
- New helpers have unit-test coverage for the band aggregation
  with known inputs (LAF=80 dB pink noise → expected per-band
  values).
- iOS build green; spectrum, level history, and watch modular
  face render unchanged on hardware.
