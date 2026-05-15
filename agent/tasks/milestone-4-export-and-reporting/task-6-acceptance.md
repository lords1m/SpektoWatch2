# Task 6: Acceptance

Status: completed  
Created: 2026-05-12  
Completed: 2026-05-13  
Milestone: `milestone-4-export-and-reporting`

## Objective

Close milestone 4 with build verification, targeted export tests, manual
acceptance notes, and a handoff report.

## Steps

1. Run `xcodebuild build-for-testing` and record the result.
2. Attempt targeted runtime tests where the simulator is available:
   - `PDFReportGeneratorTests`
   - `CSVExporterTests`
   - spectrogram image export tests
   - `MeasurementDataIOTests`
3. Document any failures with file and line references.
4. Verify manual acceptance steps from the milestone file or document hardware
   and simulator limitations.
5. Update all milestone-4 task statuses to `completed`.
6. Update `agent/milestones/milestone-4-*.md` to `Status: completed`.
7. Write `agent/reports/2026-05-12-milestone-4-acceptance.md`.
8. Update `agent/progress.yaml` to the next milestone or milestone-complete
   state.

## Acceptance

- Build-for-testing gate passes or failures are triaged.
- Export tests pass where runtime execution is available.
- All milestone-4 tasks are marked `completed` in their files.
- A handoff report exists in `agent/reports/`.
- `agent/progress.yaml` no longer points to an incomplete task after closure.
