# Task 3: Recording Notes Edit

Status: completed  
Created: 2026-05-12  
Completed: 2026-05-12  
Milestone: `milestone-3-dashboard-and-recording-polish`

## Objective

Make the recording `description` field editable in the recording detail view.

## Context

- `Recording.description: String` already exists in the model.
- `RecordingDetailView` displays it read-only at line ~450 in the overview tab.
- `RecordingManager` is the persistence layer; changes should go through it.

## Scope

### `SpektoWatch2/Views/RecordingDetailView.swift`

Replace the static `Text(recording.description)` display in the overview tab
with an editable `TextField` (or `TextEditor` for multi-line) that:

1. Shows the current description.
2. Persists changes via `recordingManager.updateRecording(_:)` (or equivalent)
   when the user commits (on focus loss or explicit save button).
3. Shows a placeholder ("Notizen hinzufügen…") when empty.

### `SpektoWatch2/RecordingManager.swift`

If an `updateRecording(_:)` or equivalent mutating method does not exist, add
one that updates the matching entry and saves to disk.

## Acceptance

- The notes field is editable in the overview tab of `RecordingDetailView`.
- Changes persist after dismissing and reopening the detail view.
- The field shows a placeholder when empty.
- Existing recordings with an empty description are handled without crash.

## Non-Goals

- Do not add rich text, markdown, or formatting support.
- Do not add a separate "notes" tab; use the existing overview tab.
