# Task 2: Centralize loudness (R4)

Status: pending
Created: 2026-05-21
Milestone: `milestone-14-performance-centralization`
Source: audit R4 + M9 task-3 finding #2 + M9 task-7 finding #5

## Goal

Phon + sone become standard entries in
`AcousticMetricsCalculator.updateMetrics` output, alongside LAF,
LAeq, etc. `LoudnessCalculator` stops being per-widget state.

## Why

- Four sites today (`SingleValueWidget`, `LAFGraphWidget`,
  `WatchLoudnessWidget`, `LoudnessCalculatorView`) each own a
  `@StateObject LoudnessCalculator`. Static lookup tables, no
  reason to instance.
- M9 task-3 + task-7 both flagged that the phon/sone overlay
  reads `data.levels["LAF"]` regardless of the user's explicit
  metric selection. Centralising the calc fixes this — the
  caller passes the resolved metric key and the calc picks the
  right level.

## Scope

- `AcousticMetricsCalculator.updateMetrics(...)` gains a phon
  + sone calculation step using the dominant-frequency
  spectrum + a chosen level metric. Result included in the
  returned `levels` dict under `"PHON"` and `"SONE"`.
- `LoudnessCalculator` becomes either:
  - **Option A**: a stateless `enum` with static interpolation
    methods, or
  - **Option B**: a single shared instance owned by the
    `AcousticMetricsCalculator`.
  Either works; A is simpler if the cached state isn't needed.
- Remove `@StateObject LoudnessCalculator` from all 4 widget
  sites. They read `levels["PHON"]` / `levels["SONE"]` instead.
- Update `Shared/LoudnessCalculatorView` (the standalone view) —
  it can either consume the same path or stay self-contained if
  it's used for manual SPL→loudness exploration (verify usage).

## Acceptance

- Phon + sone appear in `data.levels["PHON"]` /
  `data.levels["SONE"]` for every live frame.
- All 4 widget call sites drop their `LoudnessCalculator`
  `@StateObject`.
- Phon/sone values respect the resolved metric (M9 bug fix
  verified).
- iOS + watchOS builds green; existing loudness display
  unchanged numerically.
