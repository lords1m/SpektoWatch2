# Task 4: Bark precompute upstream (R2)

Status: pending
Created: 2026-05-21
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

- AudioEngine emits Bark bands when at least one widget needs
  them. Zero-cost otherwise.
- `SpectrumBandChartView` Bark-mode Canvas does not aggregate;
  reads precomputed array.
- iOS build green; existing Bark widgets render identically.
- Estimated CPU saving with one Bark widget visible: 0.3-0.5 ms
  per Canvas redraw → 5-8% of the widget's render budget at
  15 Hz.
