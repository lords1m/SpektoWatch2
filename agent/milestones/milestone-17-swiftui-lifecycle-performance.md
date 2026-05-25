# Milestone 17: SwiftUI Lifecycle & Performance

Status: in_progress
Created: 2026-05-25
Priority: medium
Estimated: 2 weeks

## Goal

Close the SwiftUI lifecycle and performance findings from the
2026-05-24 multi-agent code-review synthesis
(`agent/reports/2026-05-24-code-review-synthesis.md`). Binary
acceptance:

1. **No strong-`self` captures in `AVAudioPlayerNode` completion
   closures.** `AudioPlayerManager` deallocates cleanly on view
   dismissal mid-playback; no double-`stop()`.
2. **All async work spawned from `RecordingDetailView` is tracked in
   a `Task` and cancelled on `onDisappear`.** No completion callbacks
   mutate state on a dismissed view. Specifically:
   `promoteSpectrogramResolutionThenApply`, `applyPlaybackWeighting`,
   and `exportSpectrogramImage` are all `Task.detached` with
   `@State` task handles, `Task.isCancelled` guards before mutation,
   and `onDisappear` cancellation.
3. **`cancelActiveExport()` clears `activeExportKind` synchronously.**
   The export overlay disappears immediately on cancel.
4. **`PhotoPickerView` `isPresented` binding resets on dismiss.**
   Re-presentation works after the first selection.
5. **`DashboardViewModel.dashboardManager` is no longer a
   `@Published` nested `ObservableObject`.** Bindings to dashboard
   state propagate without manual `objectWillChange` forwarding.

## Why now

M15 closed iOS-side critical fixes (audio thread, export off main,
calibration parity, persistence). M16 closed watch-side findings
(extended-runtime delegate, complication reload, send-with-retry).
M17 carries the remaining iOS-side Critical / High items from the
same review — all view-lifecycle and async-work-tracking issues that
cause user-visible crashes (UI-4 sheet assertion on iOS 17+) or
silent regressions (UI-1 leak + double-stop, UI-2/3 stale state
mutations).

UI-7 (`DashboardViewModel` nested ObservableObject) is grouped here
because its symptom (binding propagation gaps) is a SwiftUI dependency
tracking concern of the same family.

## Non-goals

- M18 (test & tooling debt — TT-2…TT-9 + 5 coverage gaps). Tasks not
  yet generated; plan separately via `@acp.plan`.
- Backlog: PE-5…PE-8.
- App Group entitlement wiring (M6 task-4 remainder).
- Hardware acceptance items still gated under M15 outcomes 3 and 4.

## Tasks

1. task-1-audio-player-weak-self — UI-1 (Critical)
2. task-2-promote-spectrogram-resolution-task — UI-2 (High)
3. task-3-apply-playback-weighting-task — UI-3 (High)
4. task-4-export-spectrogram-image-task — UI-4 (High)
5. task-5-export-overlay-immediate-clear — UI-5 (Medium)
6. task-6-photo-picker-binding-reset — UI-6 (Medium)
7. task-7-dashboard-view-model-flatten — UI-7 (Medium)
8. task-8-acceptance — verdicts + cross-cut checks

Source: `agent/reports/2026-05-24-code-review-synthesis.md`
