# Task 6: Acceptance

Status: completed  
Created: 2026-05-12  
Completed: 2026-05-12  
Milestone: `milestone-3-dashboard-and-recording-polish`

## Objective

Close milestone 3 with build verification, test triage, and a handoff report.

## Steps

1. Run `xcodebuild build-for-testing` and record the result.
2. Attempt targeted runtime tests where the simulator is available:
   - `WaterfallDataBuilderTests`
   - `MeasurementDataIOTests`
   - `AudioEngineTests`
3. Document any failures with file and line references.
4. Verify manual acceptance steps from the milestone file (or document that
   hardware acceptance is pending).
5. Update all task statuses to `completed`.
6. Update `agent/milestones/milestone-3-*.md` to `Status: completed`.
7. Write `agent/reports/2026-05-12-milestone-3-acceptance.md`.
8. Update `agent/progress.yaml` to point at the next milestone.

## Acceptance

- Build-for-testing gate passes.
- All milestone-3 tasks are marked `completed` in their files.
- A handoff report exists in `agent/reports/`.
- `agent/progress.yaml` `status` is `milestone_complete` or points at
  milestone 4.
