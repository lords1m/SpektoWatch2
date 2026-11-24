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
| iPhone flows | Start recording → open recordings list → tap item | Blocked with toast; recording continues | DL-1 |
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

## Close-out

- Update `agent/STATE.md` §1 with a "2026-xx Code Review Remediation" entry and
  remove resolved items from §3.
- Mark M22 completed in `agent/progress.yaml`.
- Write `agent/reports/<date>-m22-acceptance.md` with the matrix results.
