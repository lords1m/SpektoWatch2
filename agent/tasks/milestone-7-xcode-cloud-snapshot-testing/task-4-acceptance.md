# Task 4: Acceptance

Status: pending
Created: 2026-05-20
Milestone: `milestone-7-xcode-cloud-snapshot-testing`
Depends on: task-1, task-2, task-3

## Objective

Verify M7 against the milestone's Manual Acceptance steps and write the
handoff report.

## Scope

1. Walk through the five Manual Acceptance steps in
   `agent/milestones/milestone-7-xcode-cloud-snapshot-testing.md`.
2. Confirm `RECORD_SNAPSHOTS` is not set on the default Xcode Cloud
   workflow.
3. Confirm no `record: true` literals are left in `PDFReportSnapshotTests.swift`.
4. Write a handoff report at
   `agent/reports/2026-MM-DD-milestone-7-acceptance.md` covering:
   - The bundled-resources pattern, in two paragraphs, with pointers to
     `SnapshotTestSupport.swift` for future maintainers.
   - The `RECORD_SNAPSHOTS=YES` contract and the never-on-main rule.
   - The test plan pin list (device, OS, locale, region, appearance,
     dynamic type) and the rationale for each.
   - How to add the next snapshot subject in 5 steps (mkdir folder
     reference, write test, add to test plan, record under
     `RECORD_SNAPSHOTS=YES`, commit baselines).
   - Outstanding follow-ups (M8 candidates from the milestone file,
     backlog items).
5. Update `agent/progress.yaml`:
   - M7 → `completed`, with `tasks_completed: 4` and the report path in
     `notes`.
   - `current_milestone` and `current_task` updated; `next_action`
     points at M8 brainstorming or "Await next milestone or feature
     request" if no M8 is queued.

## Acceptance

- Manual Acceptance steps 1–5 documented in the handoff with run links
  or result-bundle screenshots.
- Handoff report committed.
- `agent/progress.yaml` reflects M7 completion.
- `./agent/scripts/acp-validate` is clean.

## Non-Goals

- New snapshot subjects (M8).
- Diff-HTML post-build script (backlog).
