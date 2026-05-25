# Task 5: Export Overlay Clears Immediately on Cancel

Status: completed
Created: 2026-05-25

## Goal

Hide the export overlay synchronously when the user taps Abbrechen,
instead of waiting seconds for `CancellationError` to propagate
through the PDF renderer.

## Source

UI-5 (Medium) — `agent/reports/2026-05-24-code-review-synthesis.md`
lines ~312–317.

File: `SpektoWatch2/Views/RecordingDetailView.swift` lines ~1017–1019.

## Sub-items

- **Sub-1**: In `cancelActiveExport()`, set `activeExportKind = nil`
  immediately after `exportTask?.cancel()`.
- **Sub-2**: Verify the in-flight task's eventual completion does not
  reset `activeExportKind` back to its prior value. If it does, guard
  on `Task.isCancelled` or use a separate state cell.
- **Sub-3**: If a final cleanup step (temp-file removal — M15 task-10
  PE-2 added `defer` removeItem) only runs after the task settles,
  confirm the overlay disappearing doesn't leave the user with a
  half-written file. (The task-10 `defer` already handles this on
  cancellation; flag any gap.)

## Acceptance

- Tapping Abbrechen makes the overlay disappear within one frame.
- No orphan temp files (verified by M15 task-10 regression tests —
  should still pass).
- iOS build green.

Milestone: `milestone-17-swiftui-lifecycle-performance`
