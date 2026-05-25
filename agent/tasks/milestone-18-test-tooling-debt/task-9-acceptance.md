# Task 9: Acceptance

Status: pending
Created: 2026-05-25

## Goal

Confirm the eight binary outcomes from
`milestone-18-test-tooling-debt.md` and write a handoff report.

## Sub-items

- **Sub-1**: Verify each TT finding maps to a landed task (TT-2→task-1,
  TT-3→task-1, TT-4→task-2, TT-5→task-4, TT-6→task-5, TT-7→task-2,
  TT-8→task-2, TT-9→task-3). Coverage gaps 1→task-4, 2→task-5, 3→task-2,
  4→task-2, 5→task-3.
- **Sub-2**: Negative checks:
  - `grep -rn "Thread.sleep" SpektoWatch2Tests/` → 0 hits.
  - `grep -rn "try!" SpektoWatch2Tests/` → 0 hits in fixture helpers.
  - `grep -rn "Float.random" SpektoWatch2Tests/` → 0 hits in
    decimal-precision tests.
  - `./agent/scripts/acp-validate` covers M6–M17 (sanity: rename one
    milestone file temporarily — must fail; restore).
  - `python3 -m unittest agent/scripts/test_capture_screenshots.py`
    passes locally.
  - UI-test target compiles with the shared `capture()` helper; one
    representative UI test produces ≥ 1 attachment in its xcresult.
- **Sub-3**: iOS build green via `xcodebuild build -scheme SpektoWatch2
  -destination 'generic/platform=iOS Simulator'`.
- **Sub-4**: Write `agent/reports/<date>-milestone-18-acceptance.md`
  with per-task verdicts, screenshot inventory (count per device /
  per test), and any deferred items.
- **Sub-5**: Update `agent/progress.yaml` — mark M18 completed.

## Hardware / Cloud acceptance

- Trigger one Xcode Cloud run with the UI-test bundle enabled.
  Confirm screenshots appear as downloadable artifacts. Gated on
  user action.

Milestone: `milestone-18-test-tooling-debt`
