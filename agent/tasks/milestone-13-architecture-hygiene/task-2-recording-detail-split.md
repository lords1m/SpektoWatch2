# Task 2: Split RecordingDetailView

Status: pending
Created: 2026-05-21
Milestone: `milestone-13-architecture-hygiene`
Source finding: A6 in `2026-05-21-architecture-review.md`
Depends on: task-1 (recommended; isolates service surface).

## Goal

Split `SpektoWatch2/Views/RecordingDetailView.swift` (1496 LOC,
5 features in one file) into a coordinator + per-feature subviews.

## Scope

Target structure under `SpektoWatch2/Views/RecordingDetail/`:

- `RecordingDetailView.swift` — coordinator + top-level layout
  (≤ 300 LOC).
- `RecordingPlaybackSection.swift` — waveform + transport.
- `RecordingMarkersSection.swift` — marker list + add/edit/delete.
- `RecordingExportSection.swift` — CSV / PDF / image export sheet.
- `RecordingNotesSection.swift` — notes editing + photo attachment.
- `RecordingMetadataSection.swift` — date / duration / device info.

Each file ≤ 300 LOC. Pure mechanical refactor — no behavior
changes.

## Non-Goals

- Changing the export flows, PDF generation, or marker model.
- Touching `RecordingManager` itself.
- Rewriting the waveform renderer.

## Acceptance

- All six files exist; each ≤ 300 LOC.
- `RecordingDetailView` body is unchanged in semantics — opens
  the same sheet, presents the same data, fires the same callbacks.
- iOS build green.
- Existing snapshot tests for the PDF report still pass (the PDF
  generation path is not touched).
- Existing `Recording` decode in the detail view still works for
  legacy recordings.
