# Milestone 22: Code Review Remediation

Status: pending
Created: 2026-11-24
Priority: high

## Goal

Resolve every finding of the
[2026-11-24 full code review](../reports/2026-11-24-full-code-review.md)
(71 findings, IDs `DL-*`, `WC-*`, `WL-*`, `AS-*`, `RT-*`, `MC-*`, `UI-*`).
Each finding is owned by exactly one task below; a task is done only when every
ID it owns is fixed **and** covered by a regression test or an explicit
hardware-acceptance item in task-8.

## Root causes being addressed

1. **No owner of the audio session** and no interruption/route/config-change
   handling on either platform (task-4).
2. **Lifecycle ordering** — cleanup before restore, async before copy, ack
   before persist, catalog only at stop (tasks 1–3).
3. **Measurement maths depends on display settings** (window, hop, smoothing)
   (task-6).
4. **Unsynchronised geometry/scratch state** shared between render/background
   threads and main (task-5).

## Tasks & ordering

| # | Task | Owns | Depends on |
|---|---|---|---|
| 1 | [Data-loss & persistence fixes](../tasks/milestone-22-code-review-remediation/task-1-data-loss-persistence.md) | DL-1…14 | — |
| 2 | [WatchConnectivity transfer pipeline](../tasks/milestone-22-code-review-remediation/task-2-watch-connectivity-transfers.md) | WC-1…6 | — |
| 3 | [Watch lifecycle & configuration](../tasks/milestone-22-code-review-remediation/task-3-watch-lifecycle.md) | WL-1…7 | decision Q1 |
| 4 | [Audio session coordinator](../tasks/milestone-22-code-review-remediation/task-4-audio-session-coordinator.md) | AS-1…9 | 1 (DL-1 touches same path) |
| 5 | [Real-time & threading safety](../tasks/milestone-22-code-review-remediation/task-5-realtime-threading.md) | RT-1…8 | 4 (engine restart path) |
| 6 | [Measurement correctness](../tasks/milestone-22-code-review-remediation/task-6-measurement-correctness.md) | MC-1…11 | 5 (pipeline rework), decision Q2 |
| 7 | [Rendering, UI & feature polish](../tasks/milestone-22-code-review-remediation/task-7-rendering-ui-polish.md) | UI-1…16 | 5 for UI-7 only; otherwise parallel |
| 8 | [Verification & acceptance](../tasks/milestone-22-code-review-remediation/task-8-verification-acceptance.md) | — | all |

Recommended sequence: **1 → 2 → 3** (stop losing user data first, each is
small and independent) → **4 → 5 → 6** (each reshapes the engine the next one
builds on) with **7** interleaved as filler work. Ship after 1–3 as a hotfix
build if a release is pending.

## Open decisions (need product owner)

- **Q1 — `WKWatchOnly`:** keep the watch app watch-only (then the complication
  must be fed from the watch's own engine and phone mirroring code is dead),
  or make it a companion app (remove the key)? Blocks WL-3.
- **Q2 — Re-baselining measurements:** MC-1…MC-6 change reported LAF/LAeq/
  LCpeak/band values by several dB for non-default settings. Options:
  (a) bump `.spekto` metric version and label old recordings "legacy maths";
  (b) silently apply to new recordings only. Recommendation: (a).
- **Q3 — Dummy-data fallback (AS-2):** remove from release builds entirely
  (show an error instead) or keep behind a debug flag? Recommendation: debug
  flag only.

## Constraints

- No Xcode in the cloud container: every task must be built and unit-tested on
  macOS (`run_tests.sh`) before it is marked complete; hardware items go to
  task-8.
- Respect `STATE.md` §2 (stay native; don't split `AudioEngine` further unless
  required — the coordinator in task-4 is a new type, not a split).
- Keep WatchConnectivity bandwidth-conscious; no raw audio streaming.
- Update `agent/STATE.md` and `agent/progress.yaml` in the same commit as each
  completed task.

## Acceptance

- All 71 IDs marked fixed in the review report (append `→ fixed <sha>`).
- New regression tests listed per task pass on iOS + watchOS simulators.
- task-8 hardware matrix passes (interruptions, background recording on watch,
  sync exactly-once, ±1 dB parity across window/hop settings).
