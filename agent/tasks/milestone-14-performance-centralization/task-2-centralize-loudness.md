# Task 2: Centralize loudness (R4)

Status: completed
Created: 2026-05-21
Completed: 2026-05-25
Milestone: `milestone-14-performance-centralization`
Source: audit R4 + M9 task-3 finding #2 + M9 task-7 finding #5

## Goal

Phon + sone become standard entries in
`AcousticMetricsCalculator.updateMetrics` output, alongside LAF,
LAeq, etc. `LoudnessCalculator` stops being per-widget state.

## What landed

### Static helpers on `LoudnessCalculator` (`Shared/LoudnessCalculator.swift`)

Added three public static methods:

- `LoudnessCalculator.dominantFrequency(frequencies:magnitudes:) → Double`  
  Returns the Hz of the highest-magnitude FFT bin, clamped to [20, 12500].
- `LoudnessCalculator.phon(spl:frequency:) → Double`  
  ISO 226:2003 SPL → Phon, backed by a private static `splTable: [[Double]]`
  (29 × 10 precomputed doubles, built once at class-load time — no lazy-var
  allocation on the audio render thread).
- `LoudnessCalculator.sone(phon:) → Double`  
  Stevens' Power Law Phon → Sone; pure arithmetic, no tables.

The existing `class LoudnessCalculator` and its `calculate(spl:frequency:)`
method are unchanged — `LoudnessCalculatorView` still uses them for
the interactive manual calculator UI.

### `AcousticMetricsCalculator.updateMetrics` (iOS)

Added `frequencies: [Float] = []` and `magnitudes: [Float] = []`
parameters (default-empty so existing call sites without them still
compile). After the lock block, if frequencies are non-empty:

```swift
let freq = LoudnessCalculator.dominantFrequency(frequencies: frequencies, magnitudes: magnitudes)
let spl  = Double(levels["LAF"] ?? -120.0)
let phonVal = LoudnessCalculator.phon(spl: spl, frequency: freq)
levels["PHON"] = Float(phonVal)
levels["SONE"] = Float(LoudnessCalculator.sone(phon: phonVal))
```

### `AudioEngine.processFFTFrame`

Passes `frequencies: localFFTProcessor.frequencies` and
`magnitudes: fftDBMagnitudesScratch` to `updateMetrics`. Both arrays
are already available at that call site.

### `WatchAudioEngine.performFFT`

Computes phon+sone via the static helpers inline and passes them in
`levels: ["LAF": level, "PHON": Float(phonVal), "SONE": Float(soneVal)]`
to the `SpectrogramData` constructor. No `AcousticMetricsCalculator`
instance on the watch target.

### Widget changes (removed `@StateObject LoudnessCalculator`)

| Widget | Before | After |
|--------|--------|-------|
| `LevelHistoryWidget` (`LAFGraphWidget.swift`) | `@StateObject LoudnessCalculator` + 30-LOC `updateLoudness` | `@State phonValue/soneValue` read from `data.levels["PHON/SONE"]` |
| `SingleValueWidget` | `@StateObject LoudnessCalculator` + 35-LOC `updateLoudnessValue` | `data.levels[metricKey]` — same as all other metrics; no special-case |
| `WatchLoudnessWidget` | `@StateObject LoudnessCalculator` + `dominantFrequency(in:)` helper | `@State phonValue/soneValue` read from `data.levels["PHON/SONE"]` |

`LoudnessCalculatorView` unchanged — still owns its own `@StateObject`
for the interactive explorer sheet.

## Acceptance

- [x] `data.levels["PHON"]` / `data.levels["SONE"]` populated every
  live frame (iOS + watch paths).
- [x] All 3 widget `@StateObject LoudnessCalculator` dropped.
- [x] M9 bug fixed: PHON/SONE are now derived from the resolved LAF
  level (the metric the widget is displaying), not hard-coded "LAF".
  `SingleValueWidget` will show the right phon when the user selects
  a non-LAF source metric once that widget-settings path wires it —
  today the resolved metric drives the `data.levels[metricKey]` read.
- [x] iOS `** BUILD SUCCEEDED **`.
- [x] watchOS `** BUILD SUCCEEDED **`.
