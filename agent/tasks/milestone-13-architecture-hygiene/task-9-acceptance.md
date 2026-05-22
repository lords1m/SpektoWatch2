# Task 9: Acceptance

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-13-architecture-hygiene`
Depends on: task-1 … task-8

## Goal

Verify every refactor preserved behavior. Write handoff report.
No new features in M13 — purely structural.

## Checklist

### Build + tests
- [ ] iOS build green on iPhone 12 mini (target hardware) and
  generic iOS simulator.
- [ ] watchOS build green on a recent Apple Watch + generic
  watchOS simulator.
- [ ] All existing SpektoWatch2Tests pass.
- [ ] All existing SpektoWatchTests pass.
- [ ] New unit tests landed under M13 pass (CalibrationProvider,
  SpectrumBandAggregator, WatchConnectivity versioning).

### Behavior parity
- [ ] Cold launch from a pre-M13 build state loads dashboards,
  layouts, calibration, design tokens, active preset.
- [ ] LAF / LAeq / LCpeak values at a known reference signal
  match pre-M13 within the expected calibration tolerance.
- [ ] All 11 widget types render correctly across their allowed
  size ranges.
- [ ] Recording start / stop / file save / playback all work end-
  to-end.
- [ ] Watch app receives spectrogram data; faces 4a/4b/4c reflect
  the iOS accent (new in task-7).
- [ ] Complications still update.

### Architecture pressures (from architecture review)
- [ ] Pressure 1 (AudioEngine god-object): LOC reduced from 1761
  to ≤ 1300; ≥ 12 of the 30+ `@Published` props moved to child
  state objects.
- [ ] Pressure 2 (no DI): SpektoWatch2App constructs one
  AppServices instead of seven managers.
- [ ] Pressure 3 (DSP in view bodies): spectrum band aggregation
  no longer duplicated; lives in one place.
- [ ] Pressure 4 (persistence layers): every key declared in the
  registry; migration runner covers known legacy formats.
- [ ] Pressure 5 (watch protocol): version byte + AppAttate
  envelope shipping; old watches degrade gracefully.

### Deferred / explicitly out of scope (recorded)
- [ ] Backlog items A9-A14 (architecture review) re-confirmed as
  backlog with rationale; no scope creep.
- [ ] M6 task-4 entitlements still routed there (manual Xcode).
- [ ] M11 task-1 NSLock still routed there.

## Deliverable

`agent/reports/<date>-milestone-13-acceptance.md` documenting:
- What landed per task.
- LOC deltas for AudioEngine, RecordingDetailView.
- Re-render measurements before/after (Instruments).
- Any behavior regressions caught + resolved.
- What's next architecturally (likely: tests for
  AudioEngine via the new boundaries — A14 — and ToneGenerator
  module extract as part of M11).

Mark M13 complete in `progress.yaml` after the report is written.

## Landed (2026-05-21) — Code-side acceptance

Handoff report:
`agent/reports/2026-05-21-milestone-13-acceptance.md`.

Summary:
- All 8 refactor tasks shipped Phase 1.
- 10 new files (1,224 LOC), 4 existing files reduced by a net
  ~477 LOC across the refactor.
- 19 new tests added (CalibrationProvider, SpectrumBandAggregator,
  WatchProtocolVersioning).
- iOS + watchOS targets build green at HEAD.
- 6 hardware-only verification items documented in the report
  (cold-launch parity, audio correctness, widget render parity,
  recording flow, watch pairing, Instruments re-render
  comparison).

Routing reminders captured in the report:
- A2 / M6 task-4 entitlements still pending (manual Xcode work).
- A3 / M11 task-1 ToneGenerator NSLock still pending.
- Phase 2 of tasks 1/4/5/7/8 each have a deletable-code path
  that drops further LOC and finishes acceptance criteria.

Task stays in_progress until a hardware session closes the
verification checklist above.
