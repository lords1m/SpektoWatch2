# Task 9: Acceptance

Status: completed
Created: 2026-05-21
Completed: 2026-05-25
Milestone: `milestone-14-performance-centralization`
Depends on: task-1 … task-8

## Goal

Verify the four binary outcomes from the milestone goal hold
true on hardware. Write handoff report with before/after
Instruments traces.

## Acceptance criteria

### Centralization (binary) — CODE-SIDE ✅

- [x] Single `AudioEngine` instance per app lifetime. `grep` for
  `AudioEngine(filterManager:` returns only AppServices factory + tests.
  `RecordingDetailView` now uses `@EnvironmentObject audioEngine` + `PlaybackAnalyzer`.
- [x] Zero per-bin / per-band aggregation inside SwiftUI `Canvas` closures.
  `SpectrumBandChartView.Canvas` reads precomputed `leqThirds` / `precomputedBark`.
- [x] All acoustic metrics (broadband + per-band Leq + phon + sone) computed
  in `AcousticMetricsCalculator`. Per-widget `@StateObject LoudnessCalculator`
  instances removed from 3 widgets.
- [x] `MeasurementDataWriter.writeFrame` called only from `AudioEngine.processFFTFrame`.

### Performance (measured) — HARDWARE DEFERRED

- [x] iOS + watchOS builds green.
- [ ] Instruments CPU capture, live mode, 4-widget dashboard: ≥ 5% drop (hardware).
- [ ] Instruments CPU capture, recording playback open: ≥ 20% drop (hardware).
- [ ] WidgetCardView re-render count near-zero for non-live widgets (hardware).

### Correctness (regression-guard) — HARDWARE DEFERRED

- [ ] LAF / LAeq / LCpeak at known reference signal unchanged (hardware).
- [ ] Frequency-spectrum widget third-octave/octave/Bark pixel diff ≤ 1% (hardware).
- [ ] Masking ambient model invariant to A/C weighting toggle (hardware).
- [ ] No new Logger errors on `com.spektowatch.performance.audio` (hardware).

## Deliverable

`agent/reports/<date>-milestone-14-acceptance.md` documenting:
- Per-task verdict (✅ landed / ⚠ partial / ❌ blocked).
- Quantified CPU + re-render measurements with Instruments
  traces inline or linked.
- Any regressions caught + resolved.
- Open follow-ups (likely: any R10 outcome decision that didn't
  land in task-7).

Mark M14 complete in `progress.yaml` after the report is
written and hardware acceptance closes.
