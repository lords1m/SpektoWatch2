# Task 6: Kernel math extraction (DSP out of view bodies)

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-13-architecture-hygiene`
Source finding: A4 in `2026-05-21-architecture-review.md`

## Goal

Move acoustic math out of SwiftUI view bodies. Removes the
duplicate-code class of bugs (M12 spectrum "negative offset" came
from band aggregation in two places) and improves re-render
performance.

## Landed (2026-05-21) — Spectrum band aggregation (the M12 bug site)

### New file

- `SpektoWatch2/Managers/SpectrumBandAggregator.swift` (220 LOC).
  Centralised, theme-free pure functions:
  - `thirdOctaveCenters` (31 canonical ISO third-octave centers,
    20 Hz → 20 kHz).
  - `thirdOctaveLabels` (matching display strings).
  - `octaveLabels` + `octaveAsThirdIndices` (10 octaves as
    triplets of thirds).
  - `barkEdges` (24 standard Bark band edges).
  - `thirdOctaveBands(frequencies:spectrum:)`
  - `octaveBands(frequencies:spectrum:fromThirds:)` —
    power-sum of three adjacent thirds.
  - `barkBands(frequencies:spectrum:)`
  - Private `aggregateBands` (the shared 1/6-octave-edge power-sum
    + low-band interpolation fallback).
  - Private `interpolatedMagnitude` (linear interpolation between
    neighboring FFT bins for narrow low-frequency bands).

### Duplicate sites collapsed

The M12 task-8 "negative offset" fix had to land in **two
identical implementations** of the same math:

1. `AudioEngine.computeDisplayThirdOctaveBands` (engine pre-compute
   path that drives `currentOctaveBandsA/Z/C` and the watch SLM
   packet).
2. `SpectrumBandChartView.thirdOctaveBands` (widget fallback for
   the case where the precomputed 31-band array doesn't match).

Both are now thin one-line wrappers around
`SpectrumBandAggregator.thirdOctaveBands(frequencies:spectrum:)`.
Future correctness fixes land in one file, not two.

### AudioWidgets changes

- `SpectrumBandChartView.computeBandData` is now a small mode-
  router that calls the aggregator and bundles labels into a
  `SpectrumBandData`. The body shrunk from ~70 LOC (with embedded
  band layout arrays, mapping tables, and inner loops) to ~30 LOC.
- Private `thirdOctaveBands` (47 LOC) deleted — routes to aggregator.
- Private `interpolatedMagnitude` (28 LOC) deleted — routes to
  aggregator.

### AudioEngine changes

- `computeDisplayThirdOctaveBands` is now a one-line wrapper
  around `SpectrumBandAggregator.thirdOctaveBands`. Removed ~85
  LOC of duplicate math + 30 LOC of `interpolatedMagnitudeAtFrequency`.
- The private `thirdOctaveCenters` static is gone; `emptyThirdOctaveBands`
  count now reads from the aggregator.

### LOC delta

| File | Before | After | Delta |
|---|---:|---:|---:|
| AudioEngine.swift | 1790 | 1713 | **−77** |
| AudioWidgets.swift | 619 | 515 | **−104** |
| SpectrumBandAggregator.swift | — | 220 | +220 (new) |

Net repo change: **+39 LOC** total — slightly positive because the
aggregator is well-documented (docstrings + a `thirdOctaveLabels`
table that lives in one place now). Architectural win: the M12-style
"two implementations drift" bug class is gone.

## Tests landed

`SpektoWatch2Tests/SpectrumBandAggregatorTests.swift` — 7 cases:

- Third-octave centers + labels alignment (31 entries each).
- Octave labels length (10 entries).
- Bark produces 24 bands.
- **M12 regression guard**: uniform 50 dB per-bin spectrum
  produces 1 kHz band level > 53 dB (proves sum-of-power, not
  mean-of-power; the M12 bug failed this).
- Silent (−120 dB everywhere) input keeps bands below −90 dB.
- Empty inputs return 31 bands of −120.
- Octave power-sum of 3 thirds at equal level = third + 10·log10(3)
  ≈ +4.77 dB.

## Deferred

The original task scope included:

- **Level-history clamping + axis-tick computation** in
  `LAFGraphView`. Could move into a `LevelHistoryDataModel`
  helper, but the chartRect+tick math is interleaved with the
  Canvas draw context. A clean extraction requires plumbing the
  GraphicsContext into the helper or returning a struct of
  positions for the view to draw. Deferred to a follow-up — the
  spectrum aggregation was the M12 bug site and the highest-value
  win.
- **Watch modular face mini spectrogram normalization** —
  in-Canvas math (8 LOC) that's not duplicated elsewhere; not
  worth a separate aggregator entry.

## Validation

- `xcodebuild -scheme SpektoWatch2 -destination 'generic/platform=
  iOS Simulator' build` → `** BUILD SUCCEEDED **`.
- `xcodebuild -scheme "SpektoWatch Watch App" -destination 'generic/
  platform=watchOS Simulator' build` → `** BUILD SUCCEEDED **`.
- Tests not run locally (AGENT.md: simulator broken); will run on
  Xcode Cloud / hardware.

## Acceptance status

- [x] Two duplicate `thirdOctaveBands` implementations collapsed
  to one. Both AudioEngine and the widget route through the
  aggregator.
- [x] View body for `SpectrumBandChartView` smaller by ≥ 30%
  (~70 LOC → ~30 LOC ≈ 57% reduction).
- [x] New helpers have unit-test coverage for the band aggregation
  with known inputs.
- [x] iOS + watchOS builds green.
- [ ] Level-history extraction — deferred (see above).
- [ ] Hardware acceptance — gated on M13 task-9.
