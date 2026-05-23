# Milestone 14: Performance & Centralization

Status: in_progress
Started: 2026-05-21
Priority: medium
Estimated: 2 weeks

## Goal

Close the 11 redundancies catalogued in
`agent/reports/2026-05-21-performance-centralization-audit.md`.
Single binary outcome for acceptance:

1. **One `AudioEngine` instance per app lifetime.**
2. **Zero per-bin/per-band aggregation inside SwiftUI `Canvas`
   closures.**
3. **All acoustic metrics — broadband, per-band Leq, loudness
   (phon, sone) — computed in `AcousticMetricsCalculator`.**
4. **MeasurementDataWriter is the only recording-time output
   path; recording playback reads back via
   `MeasurementDataReader`, never re-runs DSP.**

Source design: the audit report. Routing: depends on M13 closing
its hardware acceptance pass; the seams from M13 (LiveAcousticState,
SpectrumBandAggregator, AppServices) are prerequisites for the
work here. M13 task-4 Phase 2 (widget migration to observe
`audioEngine.live`) is part of this milestone — folded into
task-8 (kill vizAudioEngine) since both touch the same surface.

## Why now

The audit traces every per-frame number from input buffer to
display. After M12 + M13, the live path is **mostly already
centralized**:
- Single FFT per frame.
- A/C weightings gated.
- All 14 broadband levels in one `AcousticMetricsCalculator`
  call.
- Band aggregation in one `SpectrumBandAggregator`.

The remaining 11 redundancies are concentrated in three places:
- **R1 high impact**: a second `AudioEngine` instance runs during
  recording playback (`vizAudioEngine`). Whole pipeline duplicated.
- **R2/R3 high impact**: per-widget `Canvas` recompute on every
  redraw — Bark band aggregation + per-band Leq EMA.
- **R4 medium**: `LoudnessCalculator` instantiated 4× as
  `@StateObject` with redundant lookup-table state.

Plus 7 low/out-of-band items (R5–R11) for the cleanup pass.

Net estimated DSP cost reduction: 30–50% during recording
playback, 5–15% during normal live operation depending on widget
mix. Battery / thermal impact tracked separately on hardware.

## Scope (tasks)

1. **Quick wins (R6 + R7 + R8 + R9).** Calibration-offset
   snapshot per frame; bandstop filter list cache; delete
   `currentOctaveBands` alias + `currentSpectrum` duplicate. Pure
   refactor; no behavior change.
2. **Centralize loudness (R4).** Phon + sone become regular
   entries in `AcousticMetricsCalculator.updateMetrics` output.
   `LoudnessCalculator` becomes a stateless helper or a single
   shared instance. Per-widget `@StateObject` removed across 4
   sites. Bonus: fixes the M9-flagged "phon/sone reads LAF
   regardless of metric" bug class.
3. **Per-band Leq in metrics (R3).** Move the band-EMA out of
   `SpectrumBandChartView.updateLeq` into a new
   `AcousticMetricsCalculator.bandLeqState` published alongside
   `levels`. Widgets read `live.bandLeq` instead of maintaining
   local EMA. Exposes `leqAlpha` as a settable parameter (M9
   task-4 follow-up).
4. **Bark precompute upstream (R2).** Add a Bark-bands output to
   the AudioEngine pipeline, gated by widget overrides like A/C.
   `SpectrumBandChartView` reads the precomputed array; Bark
   aggregation leaves the `Canvas` closure.
5. **Masking weighting fix (R11).** `MaskingEngine` receives
   active-weighting bands today via `onBandsUpdated`; should
   always receive Z. One-line change in the callback + masking
   test.
6. **Tighten weighting contract (R5).** Make
   `requiredSpectralWeightingsForCurrentFrame()` the only place
   that decides which weightings are computed. Widget reads
   become guaranteed-present or `nil`, not a silent fallback to
   Z.
7. **Verify double smoothing (R10).** Investigation: confirm
   whether `SpectrogramProcessor.temporalSmoothing` stacks with
   the Metal-shader smoothing. Either document the intent or
   remove the duplicate.
8. **PlaybackAnalyzer extract — kill `vizAudioEngine` (R1).**
   Highest-leverage perf fix. Extract a focused analyzer that
   reuses `FFTProcessor` + `SpectrogramProcessor` +
   `SpectrumBandAggregator` + `AcousticMetricsCalculator`
   without owning a full `AudioEngine`. `RecordingDetailView`
   consumes the analyzer output. Pair with M13 task-4 Phase 2
   (widget migration to `audioEngine.live`) since both touch the
   same surface and need a single hardware verification pass.
9. **Acceptance.** Behavior parity verification, Instruments
   re-render and CPU comparison before/after, write handoff
   report.
10. **DCT visual path, FFT measurement path.** Completed
   2026-05-22 as an opportunistic visual-pipeline improvement:
   spectrogram/waterfall/watch/export surfaces prefer visual-only
   DCT payloads, while all acoustic measurements remain FFT-based.

## Non-Goals

- Changing any DSP math (M12 task-8 + M13 task-6 already fixed
  the M12 negative-offset class).
- New widget types or new measurement metrics.
- Replacing FFT as the measurement source of truth. DCT is visual-only.
- Watch-side performance work beyond what naturally falls out of
  the iOS centralization (watch has its own
  `WatchAudioEngine`).
- M11 task-1 (ToneGenerator NSLock) stays routed there.
- M6 task-4 entitlements stay routed there.

## Acceptance

- All four binary outcomes above hold true on hardware.
- iOS + watchOS builds green.
- Instruments capture shows measurable CPU reduction (≥ 20%
  during recording playback; ≥ 5% during live live live mode
  with a 4-widget dashboard).
- WidgetCardView re-render count under live audio drops
  measurably from the M13 baseline (the deletable forwarders
  removed; widgets observe `audioEngine.live` directly).
- Handoff report `agent/reports/<date>-milestone-14-acceptance.md`
  with before/after Instruments traces.

## Risk register

- **R1 / vizAudioEngine extract** touches the recording detail
  view's most complex surface. Regression risk on playback
  scrubbing + measurement-data display. Must ship with a
  hardware acceptance pass.
- **R3 / band-Leq centralisation** introduces 31×3 floats of new
  published state. Audit shows no thermal concerns at 15 Hz
  publish rate, but verify.
- **R11 / Mask Z bands fix** is a correctness change visible on
  hardware (masking calibration shouldn't drift on weighting
  toggle). Re-run M9 masking audit's hardware items after the
  fix.

## Files in this bundle

- This milestone file.
- 10 task files under `agent/tasks/milestone-14-performance-centralization/`.
- Source design: `agent/reports/2026-05-21-performance-centralization-audit.md`.
