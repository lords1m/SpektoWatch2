# Task 9: Acceptance

Status: completed
Created: 2026-05-23
Completed: 2026-05-24
Milestone: `milestone-15-critical-stability-correctness`

## Outcome

Source synthesis already lives at
`agent/reports/2026-05-24-code-review-synthesis.md` (5-subagent
review, 37 findings, routing into M15 / M16 / M17 / M18). Acceptance
handoff written to
`agent/reports/2026-05-24-milestone-15-acceptance.md` with per-task
verdicts, binary-outcome coverage, hardware smoke-test checklist,
manual action items (TT-1 target membership), and deferred items
(AE-4, PE-1–PE-4 → task-10). Milestone NOT marked complete: task-10
(PE-1…PE-4) still pending.

## Goal

Close M15 with a verified handoff report covering all six binary
outcomes from the milestone goal. Capture the source review as a
durable artifact so future agents have an authoritative reference
to the 2026-05-23 findings (this is also the source attribution for
M16/M17/M18).

## Scope

### Sub-1: Write the source review report

Create `agent/reports/2026-05-23-code-review-synthesis.md` containing:
- Methodology (5 subagents, file scope per agent, what was excluded
  from review).
- Findings table by severity (Critical / High / Medium / Low) with
  file:line refs.
- Cross-cutting themes (calibration parity, audio-thread safety,
  data-loss paths, main-thread blocking, SwiftUI lifecycle).
- Routing decisions: which findings landed in M15 vs deferred to
  M16, M17, M18, backlog.

This serves as the canonical source-of-truth that M15's task files
cite. It also gives M16/M17/M18 a clean handoff when they're opened.

### Sub-2: Verify each binary outcome

Walk through M15's acceptance checklist:

1. **Soft-delete kill-window data preservation.** Manual test
   documented: delete → force-quit during snackbar → relaunch →
   recording restored.
2. **Audio-thread real-time safety.** Negative-grep results
   captured: `NSLock`, `FileManager`, `UserDefaults` calls reachable
   from the audio tap return empty.
3. **Watch / iOS calibration parity.** Side-by-side hardware
   reading with a reference 1 kHz tone, both devices within ±0.5 dB.
   Screenshot or photo in the report.
4. **Long-recording export without freeze / OOM.** Wall-clock for a
   30-minute PDF export with main-thread responsiveness verified;
   resident memory for opening a 1-hour recording stays under
   200 MB.
5. **PDF energy-correct averaging.** Asymmetric-fixture test passes;
   manual visual review of a sample PDF confirms the bar chart
   matches expected energy-average values.
6. **`LCpeak` from C-weighted spectrum.** Low-frequency tone fixture
   shows the expected ~3 dB attenuation vs broadband peak.

### Sub-3: Write the handoff report

Create `agent/reports/<date>-milestone-15-acceptance.md` summarizing:
- Per-task verdict (✅ landed code-side / ⏸ gated on hardware /
  ⚠ partial / ❌ reverted).
- New files, modified files, net LOC delta.
- New unit tests added (per task).
- Hardware-only verification items still open.
- Routing reminders for deferred tracks (M16/M17/M18).

### Sub-4: Update ACP files

- `agent/progress.yaml`: mark M15 complete, set `current_milestone`
  to next active.
- `agent/manifest.yaml`: add the new milestone + reports to the
  index if the manifest tracks them.
- Run `./agent/scripts/acp-validate` and ensure it returns clean.

## Acceptance

- [ ] Source review report written
  (`2026-05-23-code-review-synthesis.md`).
- [ ] All six M15 binary outcomes verified, with evidence in the
  acceptance report.
- [ ] Handoff report written
  (`<date>-milestone-15-acceptance.md`).
- [ ] All M15 task statuses in `progress.yaml` updated to `completed`
  or `partial` with notes.
- [ ] `acp-validate` returns clean.
- [ ] No new lint / build warnings introduced.

## Files

- New: `agent/reports/2026-05-23-code-review-synthesis.md`
- New: `agent/reports/<date>-milestone-15-acceptance.md`
- Updated: `agent/progress.yaml`
- Possibly: `agent/manifest.yaml`

## Verification

- iOS + watchOS builds green at HEAD.
- All unit tests added during M15 pass.
- `acp-validate` exits 0.

## Out of scope

- Promoting any of M16/M17/M18 to active (those open in their own
  planning passes).
- Hardware acceptance for items that explicitly require a physical
  device the operator may not have on hand (documented as open
  follow-ups, not blockers for M15 closure).
