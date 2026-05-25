# Task 6: PDF Energy-Correct dB Averaging

Status: completed
Created: 2026-05-23
Completed: 2026-05-24

## Outcome

`PDFReportGenerator.loadAverageThirdOctaves` now averages per-band
levels in the linear-power domain. Accumulators are
`[Double]`-precision (per-band dB values span ~10 orders of magnitude
linearly; single-precision drops the floor across thousands of
frames). Sentinel/floor frames (`-120` dB ≈ `1e-12` linear) stay a
meaningful floor. Two static helpers:
- `PDFReportGenerator.energyMeanDB(sum:divider:floorDB:)` — converts
  a running linear-power sum into a dB mean, clamping to `floorDB`
  on zero / non-positive inputs.
- `PDFReportGenerator.energyAverageDB(_:floorDB:)` — convenience
  one-shot for dB-domain arrays; used by tests.

New tests in `SpektoWatch2Tests/PDFReportGeneratorTests.swift`:
- `testEnergyAverageDB_asymmetricFixtureMatchesEnergyMeanNotArithmetic`
  — the spec's `-20 / -80` asymmetric fixture rounds to ≈ `-23.01`
  dB. The pre-fix arithmetic mean of `-50` dB would fail this.
- `testEnergyAverageDB_equalValuesAreIdempotent` — identical-input
  guard (energy mean = arithmetic mean).
- `testEnergyAverageDB_emptyInputReturnsFloor` /
  `testEnergyAverageDB_allFloorFramesStayAtFloor` — floor handling.
- `testEnergyMeanDB_zeroDividerReturnsFloor` /
  `testEnergyMeanDB_zeroSumReturnsFloor` — division/log guards.

## Notes

Audit of other dB-averaging sites (sub-3):

- `PDFReportGenerator.loadBroadbandValues` — returns per-frame
  values, not averages. No change needed.
- `Views/RecordingDetailView.swift` — surfaces stored
  `recording.laeqFast` directly (no view-side averaging) and has
  no "average over selection" feature today. Clean.
- `AudioEngine` LAF / LAeq pipeline — `metricsCalculator` already
  accumulates linear energy and converts via 10·log10 on read
  (matches Leq semantics). Confirmed energy-correct.
- `WatchAudioEngine.lafEnergy` — EMA on linear power, converted
  via 10·log10 to broadband level. Energy-correct.
- `Masking/MaskerSuggestionEngine.averageGains` and
  `Masking/TriggerSpectrumAccumulator.computeGlobalMean` — masking
  is the future-feature scope and out of M15 (per AGENT.md
  known_constraints). Flagged here for the eventual masking
  milestone.

No additional sites required a fix.

## Hardware acceptance pending

Snapshot baselines under `SpektoWatch2Tests/__Snapshots__/` may
need a refresh on the next Xcode Cloud RECORD_SNAPSHOTS=YES run —
the third-octave bar chart numerics will change wherever existing
fixtures had dynamic range. Layout stays byte-identical.


Milestone: `milestone-15-critical-stability-correctness`
Source: 2026-05-23 code review — Persistence #8

## Goal

`PDFReportGenerator.loadAverageThirdOctaves` accumulates per-band
dB values arithmetically and divides by frame count (lines ~269–
287). This is physically wrong: averaging dB in the log domain
underestimates the time-average level of a signal with dynamic
range. Any printed PDF report's third-octave bar chart shows
incorrect numbers; the magnitude of the error grows with the
signal's variance.

After this task, the PDF's average third-octave levels match what a
class-1 SLM would report for `Leq` per band.

## Scope

### Sub-1: Replace arithmetic dB averaging

Current:
```swift
for frame in frames {
    for (band, dB) in frame.thirdOctaveBands {
        accumulator[band] += dB
    }
}
let averageDB = accumulator.mapValues { $0 / Float(frames.count) }
```

Correct:
```swift
for frame in frames {
    for (band, dB) in frame.thirdOctaveBands {
        accumulator[band] += pow(10, dB / 10)  // dB → linear power
    }
}
let averageDB = accumulator.mapValues {
    10 * log10($0 / Float(frames.count))     // mean power → dB
}
```

### Sub-2: Unit test with asymmetric input

A two-frame fixture with `dB1 = -20`, `dB2 = -80`:
- Arithmetic mean: `(-20 + -80) / 2 = -50 dB` (wrong)
- Energy mean: `10 · log10((0.01 + 1e-8) / 2) ≈ -23 dB` (correct)

The test fails on the old code, passes on the new code, and serves
as a regression guard.

### Sub-3: Audit other averaging sites

Search the codebase for any other dB-domain averaging:
- `loadBroadbandValues` in `PDFReportGenerator` — currently returns
  per-frame values, not averages, so probably OK.
- `LAFGraphView` rolling average display — verify whether the EMA
  is applied to linear power or to dB.
- Any "average over selection" feature in `RecordingDetailView`.

Fix any additional sites found; document the audit's negative
results in the task notes.

## Acceptance

- [ ] `loadAverageThirdOctaves` computes time-averaged levels in
  linear power, converts back to dB at the end.
- [ ] `PDFReportGeneratorTests` includes the asymmetric-fixture
  test that fails on the old behavior, passes on the new.
- [ ] Audit results for other averaging sites documented in this
  task file's "Notes" section after completion.
- [ ] No regression on existing `PDFReportSnapshotTests` (the
  output PDF is allowed to change — record fresh baselines if the
  visual numbers shift, which they should).

## Files

- `SpektoWatch2/PDFReportGenerator.swift`
- New tests in `SpektoWatch2Tests/PDFReportGeneratorTests.swift`
- Possibly: snapshot baselines under
  `SpektoWatch2Tests/__Snapshots__/` regenerated.

## Verification

- iOS build green.
- New asymmetric-fixture test passes.
- Snapshot baselines regenerated and reviewed for correctness (the
  numerical change is intentional, but the PDF layout should
  otherwise be byte-identical).

## Notes

> Filled in during implementation: list of any other dB-averaging
> sites discovered during the audit, with disposition (fixed /
> intentionally arithmetic / not actually averaging).

## Out of scope

- Adding per-band Leq to live widgets (M14 task-3 territory).
- Changing the PDF report's layout, font, or chart styling.
