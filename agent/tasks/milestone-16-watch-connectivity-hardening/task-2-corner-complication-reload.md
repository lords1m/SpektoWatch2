# Task 2: Corner Complication Reload

Status: completed
Created: 2026-05-25
Completed: 2026-05-25

## Outcome

- **Sub-1**: `"SpektoWatchLevelCorner"` added to both `complicationWidgetKinds`
  arrays — `Shared/WatchConnectivityManager.swift` line 19 and
  `SpektoWatch2/WatchConnectivityManager.swift` line 17.
- **Sub-2**: Both `WidgetCenter.shared.reloadTimelines(ofKind:)` call sites
  iterate `complicationWidgetKinds` via `forEach` — no per-kind hardcoded
  calls exist anywhere in the project. The corner kind is now covered by
  both reload paths automatically.
- **Sub-3**: `LevelCornerWidget.kind` in
  `SpektoWatch Complications/WatchComplicationWidget.swift` line 33 is
  `"SpektoWatchLevelCorner"` — exact match with the added string.

iOS build: `BUILD SUCCEEDED`.

## Hardware acceptance pending

Paired-device test: set the corner complication on a watch face, trigger
a level update, confirm the complication refreshes its display.

Milestone: `milestone-16-watch-connectivity-hardening`
Source: WA-2 High — `agent/reports/2026-05-24-code-review-synthesis.md`
