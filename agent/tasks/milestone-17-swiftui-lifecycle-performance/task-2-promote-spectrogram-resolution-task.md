# Task 2: promoteSpectrogramResolution as Tracked Task

Status: completed
Created: 2026-05-25

## Goal

Convert `promoteSpectrogramResolutionThenApply` from untracked
`DispatchQueue.global.async` to a tracked `Task.detached` that is
cancelled on view dismissal.

## Source

UI-2 (High) — `agent/reports/2026-05-24-code-review-synthesis.md`
lines ~287–293.

File: `SpektoWatch2/Views/RecordingDetailView.swift` lines ~1240–1259.

## Sub-items

- **Sub-1**: Convert the `DispatchQueue.global.async` block to
  `Task.detached(priority: .userInitiated)` (or matching priority
  of the existing export work).
- **Sub-2**: Add `@State var spectrogramLoadTask: Task<Void, Never>?`
  (or merge with an existing handle if one already covers this slot).
  Assign before launch; cancel any prior handle.
- **Sub-3**: Inside the detached task, check `Task.isCancelled` before
  each significant state mutation and bail early. Hop to `@MainActor`
  for the final UI mutation (existing pattern in this file).
- **Sub-4**: Add `spectrogramLoadTask?.cancel()` in `onDisappear`
  (the same `onDisappear` that already cancels the export task — keep
  cancellation centralized).

## Acceptance

- No `DispatchQueue.global.async` in `promoteSpectrogramResolutionThenApply`.
- iOS build green.
- Manual regression: open recording detail, trigger resolution
  promotion (e.g. select a longer time span), dismiss the view
  before it completes; no state mutation logged after dismissal.

Milestone: `milestone-17-swiftui-lifecycle-performance`
