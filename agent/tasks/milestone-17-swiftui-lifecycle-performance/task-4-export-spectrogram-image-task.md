# Task 4: exportSpectrogramImage as Tracked Task

Status: completed
Created: 2026-05-25

## Goal

Stop the spectrogram-image share sheet from being presented on a
dismissed view (iOS 17+ `UISheetPresentationController` assertion).

## Source

UI-4 (High) — `agent/reports/2026-05-24-code-review-synthesis.md`
lines ~303–310.

File: `SpektoWatch2/Views/RecordingDetailView.swift` lines ~1051–1064.

## Sub-items

- **Sub-1**: Add `@State var spectrogramExportTask: Task<Void, Never>?`.
- **Sub-2**: Convert the `DispatchQueue.global.async` block to
  `Task.detached(priority: .userInitiated)`. Assign to
  `spectrogramExportTask`.
- **Sub-3**: Inside the detached task, after the heavy compute, check
  `Task.isCancelled` before hopping to main. In the main hop, set
  `showShareSheet = true` only if `!Task.isCancelled`.
- **Sub-4**: Cancel `spectrogramExportTask` in `onDisappear`.

## Acceptance

- No `DispatchQueue.global.async` in `exportSpectrogramImage`.
- iOS build green.
- Manual regression: tap export, dismiss the view before share sheet
  appears; no `UISheetPresentationController` assertion in console.

Milestone: `milestone-17-swiftui-lifecycle-performance`
