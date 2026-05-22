# Task 11: Acceptance

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-9-widget-audit`
Depends on: task-1 … task-10

## Objective

Collate per-widget findings into a single handoff report and cross-check
for inconsistencies between widgets that share patterns (level metering,
settings sheets, dB scaling, color zones).

## Landed (2026-05-21) — Code-side acceptance

Handoff report written: `agent/reports/2026-05-21-milestone-9-widget-audit.md`.

Contents:
- Per-widget verdict (✅ / ⚠ / ❌ / Deactivated) for all 10 widgets.
- 12 cross-cut findings spanning empty settings sheets, override-toggle
  UX, hardcoded color literals, loudness metric coherence, dead
  `scrollOffset` knob, O(n) history pruning, audio-session-category
  mutation, NSLock blocker, missing confirmations, accessibility
  identifiers, and localization.
- Prioritized backlog split High/Blocker (NSLock + empty settings),
  Medium (loudness coherence, peak-hold consistency, override
  decision), Low/Polish (≈ 25 items, each linked to its source
  task).

### Per-widget verdicts at a glance

| # | Widget | Verdict |
|---|---|---|
| 1 | Spectrogram | ✅ (3 code fixes landed) |
| 2 | Waterfall | ⚠ (4 findings) |
| 3 | Level History | ⚠ (4 findings) |
| 4 | Frequency Spectrum | ⚠ (4 remaining; 1 resolved by M12 Y-bounds) |
| 5 | Level Meter | ⚠ (5 remaining; 2 resolved by M12 Y-bounds) |
| 6 | Phase Meter | Deactivated (M12 removed from picker + load filter) |
| 7 | Single Value | ⚠ (7 findings) |
| 8 | Tone Generator | ❌ blocker: NSLock on audio render thread |
| 9 | Spektralanalyse Lab | ⚠ (10 findings) |
| 10 | Masking | ⚠ (6 findings) |

### Outcomes recorded in M11/M12 already

- **Tone Generator NSLock** is the blocker for M11 task-1 (Render
  Thread Safety Precheck) — already queued.
- **Hardcoded dB ranges** for chart widgets — resolved in M12 task-8
  via shared `chartYMinDB`/`chartYMaxDB`.
- **Phase Meter** — deactivated in M12.

## Remaining work (hardware)

Each per-widget task has a "Pending (hardware)" checklist for screenshot
grids + stress scenarios. M9 promotion to `completed` is gated on that
work; no new code findings expected — purely verification.

## Acceptance

- [x] Report exists and is reviewable.
- [x] Every per-widget task has a verdict (10/10).
- [x] Open backlog items are either routed (NSLock → M11, dB ranges
  → M12 task-8 (done), phase meter → M12 (done)) or explicitly
  deferred with rationale.
- [ ] Hardware screenshot pass — gated on a hardware session.

Code-side acceptance complete; status stays `in_progress` until the
hardware verification step closes the per-widget checklists.
