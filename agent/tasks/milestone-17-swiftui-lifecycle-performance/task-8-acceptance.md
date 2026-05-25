# Task 8: Acceptance

Status: completed
Created: 2026-05-25

## Goal

Confirm M17 binary outcomes 1–5 are closed and write a handoff report.

## Sub-items

- **Sub-1**: Verify each UI finding has a corresponding landed task
  (UI-1→task-1, UI-2→task-2, UI-3→task-3, UI-4→task-4, UI-5→task-5,
  UI-6→task-6, UI-7→task-7).
- **Sub-2**: Negative checks via grep:
  - `grep -n "scheduleSegment" SpektoWatch2/Views/AudioPlayerManager.swift`
    — completion closures use `[weak self]`.
  - `grep -n "DispatchQueue.global.async" SpektoWatch2/Views/RecordingDetailView.swift`
    — no hits left in the three target functions (lines per UI-2/3/4).
  - `cancelActiveExport` sets `activeExportKind = nil` synchronously.
  - `PhotoPickerView` delegate sets `isPresented.wrappedValue = false`.
  - `DashboardViewModel.dashboardManager` declaration is `let` or
    non-`@Published`.
- **Sub-3**: iOS build green via `xcodebuild`.
- **Sub-4**: Write `agent/reports/<date>-milestone-17-acceptance.md`
  with per-finding verdicts and any deferred items.
- **Sub-5**: Update `agent/progress.yaml` — mark M17 completed,
  rotate `current_milestone` to the next milestone.

## Hardware acceptance

- Manual on-device: open a long recording, scrub, dismiss mid-playback,
  mid-resolution-promotion, mid-weighting-change, mid-export. Confirm
  no AVAudio warnings, no sheet assertions, no stale state mutations
  reported in console.

Milestone: `milestone-17-swiftui-lifecycle-performance`
