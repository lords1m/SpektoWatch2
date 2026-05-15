# Task 4: Spectrogram Image Export

Status: completed  
Created: 2026-05-12  
Completed: 2026-05-13  
Milestone: `milestone-4-export-and-reporting`

## Objective

Expose a standalone spectrogram image export for saved recordings.

## Scope

- Review `SpectrogramImageRenderer` and saved-recording playback data paths.
- Add an export path that writes a shareable image file for the recording.
- Ensure image generation handles missing or unreadable audio gracefully.
- Add focused tests for renderer output dimensions, non-empty pixel data where
  practical, and error behavior.

## Acceptance

- A saved recording can produce a PNG or other standard image artifact.
- The export file is written outside the audio callback path.
- Failures are user-visible or logged without crashing the recording detail
  view.
- Automated coverage exists for successful and failure paths where practical.

## Non-Goals

- No animated spectrogram/video export.
- No custom color-map editor.
- No report template customization.
