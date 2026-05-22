# Task 3: Per-band Leq in AcousticMetricsCalculator (R3)

Status: pending
Created: 2026-05-21
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

- `SpectrumBandChartView` body has no `.onReceive` that triggers
  per-band linear EMA work.
- Live frequency-spectrum widget renders identically pre/post.
- iOS build green.
- Unit test: feed AcousticMetricsCalculator a known sequence of
  bands; verify the returned band-Leq array matches the
  closed-form EMA.
