# Task 8: Verification & Acceptance

Status: pending
Created: 2026-11-24
Milestone: `milestone-22-code-review-remediation`

## Goal

Prove the fixes on macOS/Xcode and real hardware; close out the review report.

## Per-task gate (macOS)

For each of tasks 1–7 before marking complete:
- `./run_tests.sh` green for `SpektoWatch2Tests` and `SpektoWatchTests`.
- All 7 targets build (iOS app, watch app, complications, widget extension,
  test targets).
- New TSan configuration (task-5) green.
- Append `→ fixed <sha>` to each owned ID in
  `agent/reports/2026-11-24-full-code-review.md`.

## Hardware matrix

| Area | Scenario | Pass criteria | IDs |
|---|---|---|---|
| iPhone session | Phone call, Siri, alarm during live + recording | Banner shown, capture resumes, recording intact with gap marker | AS-1 |
| iPhone session | Wired + Bluetooth headset plug/unplug while recording | Resumes or finalizes cleanly; status truthful | AS-1 |
| iPhone session | Tone generator during live measurement | Levels unchanged (measurement mode kept), tone audible | AS-3 |
| iPhone flows | Open recording / masking preview while idle, while on Watch source | Previous capture state restored exactly | AS-5, AS-6 |
| iPhone flows | Start recording → open recordings list → tap item | Detail opens with "Aufnahme läuft – Wiedergabe ist gesperrt", play disabled; recording continues and is saved | DL-1 |
| iPhone flows | Delete → open other recording → back → undo | Undo restores | DL-7 |
| iPhone crash | Kill during undo window; kill mid-recording | Files kept / recording recovered | DL-2, DL-4 |
| Watch | 30-min wrist-down background recording | Runs to completion | WL-1, WL-5 |
| Watch | Force-quit mid-recording, relaunch | Recording recovered and listed | WL-2 |
| Watch | Tone on watch while monitoring | Capture continues after tone | AS-4 |
| Watch sync | Toggle airplane mode repeatedly during sync | Each recording arrives exactly once on phone; no tmp leaks | WC-1…4 |
| Watch | Complication without phone | Shows recent value, stale after 5 min | WL-3 |
| Metrics | Calibrator 94 dB/1 kHz across all window × hop settings | ±0.5 dB phone; watch within ±1.0 dB of phone | MC-1…7 |
| Perf | Instruments System Trace, live + recording 10 min | No allocations/locks on render thread; budget per `PERFORMANCE_BUDGET.md` | RT-1…6 |
| Live Activity | Kill app mid-recording, relaunch, start new | Single activity | UI-14 |

## Code-side handoff (2026-11-25)

Tasks 1–7 are code-complete on branch `claude/quirky-heisenberg-incxzy`
(no Xcode in the authoring container — nothing below has been compiled or
run yet; only a tree-sitter Swift syntax pass):

| Task | Commit | New tests |
|---|---|---|
| 1 Data loss | `5ac6df0` | `M22DataLossRegressionTests` |
| 2 WC transfers | `c939c05` | `M22WatchTransferRegressionTests` |
| 3 Watch lifecycle | `b925453` | `SpektoWatchTests/M22WatchLifecycleRegressionTests` |
| 4 Audio session | `9507e99` | `M22AudioSessionRegressionTests` |
| 5 RT/threading | `5f8c684` | `M22RealtimeThreadingRegressionTests` (+ TSan config) |
| 6 Measurement | `daf5726` | `MeasurementReferenceTests` (+ updated `AcousticMetricsCalculatorTests`) |
| 7 UI polish | `8584146` | `M22UIPolishRegressionTests` |

First things to check when building on macOS (most likely compile issues):
- `PlaybackAnalyzer`: `nonisolated let` `OSAllocatedUnfairLock(uncheckedState:)` in a `@MainActor` class.
- `WaterfallView.TwoFingerPanGesture` (`UIGestureRecognizerRepresentable`, iOS 18 API shape).
- `MainActor.assumeIsolated` inside `DispatchWorkItem` / `Timer` closures (`DashboardViewModel`, `MaskingEngine`, `MaskingPreviewPlayer`).
- New Shared files join both app targets automatically (synchronized `Shared/` group): `AudioSessionCoordinator`, `RealtimeSlotQueue`, `RealtimeAudioFileWriter` (moved from `SpektoWatch2/`), `TimeDomainLevelMeter`.
- Pre-existing build break fixed in task-5: `HighEndSpectrogramAdapter` referenced an undefined `BinMapping` type (introduced in `118601f`).

Decisions applied: **Q2 = (a)** (`Recording.metricsVersion`, legacy label),
**Q3 = debug-flag only** (`SPEKTO_SYNTHETIC_FALLBACK=1` or UI-test runtime).
**Q1 still open:** WL-3 was implemented independently of it (watch engine is
the primary complication writer). Note: the watch target's wired
`INFOPLIST_FILE` is the root `SpektoWatch-Watch-App-Info.plist` + generated
keys (`WKCompanionAppBundleIdentifier`, `WKRunsIndependentlyOfCompanionApp =
YES`); `SpektoWatch Watch App/Watch-Info.plist` (with `WKWatchOnly`) is not the
built Info.plist, so shipped builds currently behave as a companion app.

Behaviour changes to expect: levels with non-Hann windows move by up to
±4 dB (now window-independent); LAF Fast reacts faster (per-sample time
weighting), LCpeak now ≥ LCF (true sample peak, ~+3 dB vs old for tones);
band Leq is a true integral (slower to converge than the old EMA); PHON uses
the Z level.

## Close-out

- Update `agent/STATE.md` §1 with a "2026-xx Code Review Remediation" entry and
  remove resolved items from §3.
- Mark M22 completed in `agent/progress.yaml`.
- Write `agent/reports/<date>-m22-acceptance.md` with the matrix results.
