# Task 2: Layout Rename

Status: completed  
Created: 2026-05-12  
Completed: 2026-05-12  
Milestone: `milestone-3-dashboard-and-recording-polish`

## Objective

Allow users to rename dashboard layouts from the layout management UI.

## Scope

### `SpektoWatch2/DashboardManager.swift`

Add:

```swift
func renameLayout(at index: Int, name: String) {
    guard index >= 0, index < layouts.count else { return }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    layouts[index].name = trimmed
    saveConfiguration()
}
```

### `SpektoWatch2/ModularDashboardView.swift`

In the layout picker / layout management sheet, add an inline rename control
(e.g. long-press on a layout row, or an edit button that presents a
`TextField` in an alert or sheet) that calls `dashboardManager.renameLayout`.

The rename entry point should be visible and reachable within 2 taps from the
main dashboard.

## Acceptance

- `DashboardManager.renameLayout(at:name:)` exists and persists the new name.
- The UI exposes rename for the active layout without requiring a separate
  settings screen.
- Empty or whitespace-only names are rejected silently (no crash, no save).
- Existing layouts survive an app restart with the new name.

## Non-Goals

- Do not change layout ordering or add drag-to-reorder in this task.
