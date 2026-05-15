# Task 1: Complication Source Files

Status: in_progress  
Created: 2026-05-14  
Milestone: `milestone-5-watch-complications`

## Objective

Create all Swift source files for the `SpektoWatch Complications` Widget
Extension. These files are placed in the `SpektoWatch Complications/` folder
which will be picked up by the `fileSystemSynchronizedGroups` entry added in
task 2.

## Scope

- `SpektoWatch Complications/SpektoWatchComplications.swift` — `@main`
  `WidgetBundle` entry point declaring all three complication widgets.
- `SpektoWatch Complications/WatchComplicationEntry.swift` — `TimelineEntry`
  carrying the dBSPL value (or nil for placeholder).
- `SpektoWatch Complications/WatchComplicationProvider.swift` —
  `TimelineProvider` returning a single-entry timeline; placeholder and snapshot
  use sensible defaults.
- `SpektoWatch Complications/WatchComplicationViews.swift` — SwiftUI views for
  `.accessoryCircular`, `.accessoryRectangular`, and `.accessoryInline`.
- `SpektoWatch Complications/WatchComplicationWidget.swift` — three `Widget`
  structs (one per family) and their configuration.

## Acceptance

- All files compile cleanly as part of the extension target added in task 2.
- `.accessoryCircular` view shows a `Gauge` or `Text` with dBSPL value and
  "SPL" label.
- `.accessoryRectangular` shows value + a `ProgressView` scaled 0–120 dB.
- `.accessoryInline` shows a compact text line like "74 dB".
- Placeholder states display "–" instead of a numeric value.
- No `import UIKit` — watchOS complications use SwiftUI only.

## Non-Goals

- No App Intent for complication interaction.
- No animation or live activity integration.
