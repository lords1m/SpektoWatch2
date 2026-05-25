# Task 3: applyPlaybackWeighting as Tracked Task

Status: completed
Created: 2026-05-25

## Goal

Stop competing GCD weighting computations from racing each other and
from mutating `weightedSpectrogramCache` after view dismissal.

## Source

UI-3 (High) — `agent/reports/2026-05-24-code-review-synthesis.md`
lines ~295–301.

File: `SpektoWatch2/Views/RecordingDetailView.swift` lines ~1212–1226.

## Sub-items

- **Sub-1**: Add `@State var weightingTask: Task<Void, Never>?`.
- **Sub-2**: Convert the `DispatchQueue.global.async` block to
  `Task.detached(priority: .userInitiated)`. Before launching the
  new task, call `weightingTask?.cancel()` so rapid picker changes
  collapse to one in-flight computation.
- **Sub-3**: Inside the detached task, check `Task.isCancelled` after
  the heavy compute and before assigning to `weightedSpectrogramCache`.
- **Sub-4**: Cancel `weightingTask` in `onDisappear` alongside the
  existing cancellations.

## Acceptance

- No `DispatchQueue.global.async` in `applyPlaybackWeighting`.
- Rapid weighting-picker switching results in only the last selection
  populating the cache; intermediate computations are cancelled.
- iOS build green.

Milestone: `milestone-17-swiftui-lifecycle-performance`
