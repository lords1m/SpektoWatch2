# Task 9: Acceptance

Status: pending
Created: 2026-05-21
Milestone: `milestone-14-performance-centralization`
Depends on: task-1 … task-8

## Goal

Verify the four binary outcomes from the milestone goal hold
true on hardware. Write handoff report with before/after
Instruments traces.

## Acceptance criteria

### Centralization (binary)

- [ ] Single `AudioEngine` instance per app lifetime. `grep` for
  `AudioEngine(filterManager:` returns only the AppServices
  factory site + tests.
- [ ] Zero per-bin / per-band aggregation inside SwiftUI
  `Canvas` closures. All widget bodies read pre-computed
  arrays from `LiveAcousticState`.
- [ ] All acoustic metrics (broadband + per-band Leq + phon +
  sone) computed in `AcousticMetricsCalculator`. Per-widget
  loudness `@StateObject`s removed.
- [ ] `MeasurementDataWriter` is the only recording-time output
  path; recording playback reads back via
  `MeasurementDataReader`, never re-runs DSP.

### Performance (measured)

- [ ] iOS + watchOS builds green.
- [ ] Instruments CPU capture, live mode, 4-widget dashboard:
  total CPU drops ≥ 5% vs. M13 baseline.
- [ ] Instruments CPU capture, recording playback open: total
  CPU drops ≥ 20% vs. M13 baseline.
- [ ] WidgetCardView re-render count under live audio drops to
  near-zero for widgets that don't display live data.

### Correctness (regression-guard)

- [ ] LAF / LAeq / LCpeak at known reference signal unchanged
  vs. M13 baseline.
- [ ] Frequency-spectrum widget renders identically in
  third-octave, octave, Bark modes (pixel diff ≤ 1% per
  band).
- [ ] Masking ambient model invariant to user weighting toggle
  (R11 fix verified).
- [ ] No new Logger errors / warnings on
  `com.spektowatch.performance.audio` subsystem.

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
