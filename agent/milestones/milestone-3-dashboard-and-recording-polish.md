# Milestone 3: Dashboard And Recording Polish

Status: completed  
Created: 2026-05-12  
Completed: 2026-05-12  
Source design: `agent/design/spektowatch-field-engineering-design.md`

## Goal

Close the gaps between the data model and UI for dashboard layout management
and recording review. Layout naming must be user-editable. Recordings must
support editable notes and photo attachments through the detail view. The new
`WaterfallDataBuilder` must be covered by unit tests.

## Completion Criteria

- Dashboard layouts can be renamed in the UI.
- The recording detail overview tab exposes an editable notes field.
- Photos can be attached to a recording from the detail view and are displayed
  inline.
- `WaterfallDataBuilderTests` pass (build-for-testing gate at minimum).
- Existing `.spekto` compatibility and recording read/write are unbroken.

## Manual Acceptance

1. Open dashboard. Create a second layout and rename both layouts.
2. Open a saved recording. Edit the notes field. Reopen the recording and
   confirm the note persisted.
3. Attach a photo from the photo library to a recording. Confirm it appears in
   the detail view. Reopen the recording and confirm the photo is still shown.
4. Confirm waterfall tab and waterfall live widget render without crashing.

## Recommended Automated Validation

- `WaterfallDataBuilderTests` (new)
- `MeasurementDataIOTests` (regression check for recording compatibility)
- `AudioEngineTests` (smoke check — nothing should regress)

Use build-for-testing as the minimum gate if runtime execution is blocked.

## Tasks

- `agent/tasks/milestone-3-dashboard-and-recording-polish/task-1-compile-gate.md`
- `agent/tasks/milestone-3-dashboard-and-recording-polish/task-2-layout-rename.md`
- `agent/tasks/milestone-3-dashboard-and-recording-polish/task-3-recording-notes-edit.md`
- `agent/tasks/milestone-3-dashboard-and-recording-polish/task-4-recording-photo-attachment.md`
- `agent/tasks/milestone-3-dashboard-and-recording-polish/task-5-waterfall-tests.md`
- `agent/tasks/milestone-3-dashboard-and-recording-polish/task-6-acceptance.md`

## Explicit Non-Goals

- No masking feature work.
- No export/report redesign.
- No compliance or calibration workflow.
- No watch complications or standalone watch recording.
- No new measurement file format changes (new fields must be optional/versioned).

## Future Milestones

- Client-facing export/report redesign.
- External calibrated microphone and compliance workflow.
- Polished masking workflow and reusable masking profiles.
- Watch complications and standalone recording hardening.
