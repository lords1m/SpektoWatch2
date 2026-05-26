# Task 6: Acceptance

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-12-liquid-glass-redesign`
Depends on: task-1..5

## Code-side status (2026-05-25)

Handoff report written: `agent/reports/2026-05-25-milestone-12-acceptance.md`.
All 7 tasks (1–5, 7, 8) confirmed code-complete. The 8 checklist items below
require hardware on the `redesign/liquid-glass` branch.

## Goal

Hardware acceptance of the full Liquid Glass redesign across both
color schemes and all five accents.

## Checklist

1. Cold launch on hardware (or Xcode Cloud build) under each theme:
   - Dark + Phosphor (default)
   - Dark + Amber / Cyan / Magenta / Paper
   - Light + each accent (canvas stays dark per `CanvasMode.dark`,
     light per `CanvasMode.light`)
2. All 11 presets render without overlap or clipping at the smallest
   widget sizes from `WidgetConfiguration.sizeRange(for:)`.
3. Edit mode: jiggle visible on every card; accent border + glow
   present; drag/delete circles tappable; preset rail + transport
   dim to ~35% opacity; drag-reorder still works.
4. Tweaks panel: every toggle takes effect immediately and persists
   across cold launch.
5. Transport bar: LED pulses live + recording correctly; record turns
   red-tinted; play turns accent when active.
6. Watch app: three faces selectable; three complication slots use
   new chrome.
7. Regression scan: PDF export still produces correct output;
   recording flow unchanged; masking unchanged.

## Deliverable

Write `agent/reports/YYYY-MM-DD-milestone-12-acceptance.md` with
screenshots per theme/accent, pass/fail per check, and known issues.
Mark M12 complete in `progress.yaml`.
