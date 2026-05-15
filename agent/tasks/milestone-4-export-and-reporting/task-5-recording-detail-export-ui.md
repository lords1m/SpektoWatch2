# Task 5: Recording Detail Export UI

Status: completed  
Created: 2026-05-12  
Completed: 2026-05-13  
Milestone: `milestone-4-export-and-reporting`

## Objective

Make the recording detail export controls complete and predictable for the
milestone artifacts: PDF report, CSV data, raw measurement file, and
spectrogram image.

## Scope

- Update `RecordingDetailView` export controls and actions.
- Keep sharing local-first through existing share-sheet behavior.
- Add clear availability handling when a recording lacks measurement data,
  audio, or a renderable spectrogram.
- Preserve playback, notes, photos, and widget review behavior.

## Acceptance

- Export controls cover PDF, CSV, raw measurement sharing, and spectrogram
  image export.
- Actions disable or fail gracefully when required source files are missing.
- Existing recording detail workflows remain usable.
- UI tests or focused unit coverage are added where the codebase supports them.

## Non-Goals

- No new navigation model for recording detail.
- No cloud destination picker.
- No report template customization.
