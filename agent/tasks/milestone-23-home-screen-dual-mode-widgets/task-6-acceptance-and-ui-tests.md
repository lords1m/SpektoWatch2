# Task 6: Acceptance, Automated Tests & Hardware Verification

Status: in_progress
Created: 2026-11-25
Updated: 2026-11-27
Milestone: `milestone-23-home-screen-dual-mode-widgets`

## Goal

Validate the Home-Screen launcher and Dual-Mode Widget system across all build
targets, unit tests, UI smoke tests, simulator screenshots, and on-device
hardware checks, then close Milestone 23 with an ACP acceptance report.

## Scope

Since tasks 1–5, the Home Screen was rebuilt after the iOS Home Screen
(see `agent/STATE.md` §1, 2026-11-25 to 2026-11-27): swipeable preset pages
on a 4-column grid, jiggle edit mode with long-press entry, Liquid Glass
depth, and free drag-resize of widgets (`HomeSpan`). The old header pill and
`PresetRailView` are no longer mounted. This acceptance covers that state.

- **Multi-Target Build & Unit Tests:**
  - Build all targets (`SpektoWatch2`, `SpektoWatch Watch App`,
    `SpektoWatch Complications`, `SpektoWatch2WidgetExtension`, `SpektoWatch2Tests`).
  - Run `WidgetDisplayStyleMigrationTests`, `WidgetSizingMigrationTests`,
    `HomeSpanLayoutTests` and the existing `SpektoWatch2Tests` regression suites.
- **Repair UI tests broken by the Home Screen rebuild:**
  - `editDashboardButton` now exists only inside jiggle mode (`HomeEditBar`
    "Fertig"). Tests that tap it to *enter* edit mode
    (`ScreenshotCatalogTests`, `WidgetGridScreenshotTests`) must long-press the
    wallpaper or a tile instead, or use a `UITestLaunchFlags` flag that starts in
    edit mode.
  - Identifiers the tests query but the app no longer sets: `keineWidgetsLabel`
    (`ScreenshotCatalogTests`), `exportPDFButton`, `exportCSVButton`,
    `exportSpectrogramButton` (`ExportFlowScreenshotTests`). Re-add them in the
    app or update the tests.
- **UI Smoke Tests & Screenshots:**
  - Add `HomeScreenDualModeUITests` in `SpektoWatch2UITests/` verifying:
    1. Default Home Screen renders both live widgets and `1×1` icon tiles.
    2. Tapping a `1×1` icon (e.g. `Aufnahmen`, `Einstellungen` or `Editor`)
       opens its dedicated view (zoom transition) and closes cleanly.
    3. `WidgetPickerView` (edit bar "+") adds a feature as `Icon` or `Live-Widget`.
    4. `WidgetSettingsView` and the context menu switch an existing tile between
       `Live-Widget` and `Icon`.
    5. Swiping the pager and tapping the page dots switch presets; the active
       preset is committed after the page settles.
    6. Long-press enters jiggle mode; "−" removes a tile; "Fertig" and a tap on
       the wallpaper leave it.
    7. Drag-resize: dragging the `homeResizeHandle` grips (right edge, bottom
       edge, corner) changes the span cell by cell; the VoiceOver actions
       Breiter / Schmaler / Höher / Niedriger do the same; the context-menu
       "Größe" presets apply.
  - Refresh simulator screenshots via `./agent/scripts/capture-screenshots.py`.
- **Hardware Acceptance Checklist (On-Device):**
  1. Launch lands on the Home Screen with live readings updating smoothly and
     `1×1` icons crisp in Light and Dark mode, with and without Reduce
     Transparency (depth effects off).
  2. Tapping every function icon opens its dedicated fullscreen/sheet view with
     working audio/engine handoff and clean dismissal.
  3. Idle `.icon` tiles introduce zero Metal drawable allocations or 15 Hz view
     re-renders (verified via Instruments / SwiftUI body instrumentation);
     off-screen pages beyond the swipe neighbours stay unmounted.
  4. Page swipes run without stutter or jump-back, also while the engine is live.
  5. Edit mode (long-press jiggle, drag-reorder, "−", settings sheet on tap)
     works smoothly across mixed `Live-Widget` and `Icon` tiles.
  6. Drag-resize: grips are hittable (44 pt) without starting a reorder drag or
     page scroll; the grid re-flows live; sizes respect per-type limits
     (single value / icon 1×1, spectrogram ≥ 2×2, max 4×7) and the right page
     edge; a 1×1 single value stays readable; the size survives relaunch.
  7. Existing saved layouts upgrade cleanly: no lost widgets, legacy sizes map
     to the expected spans (3×2 → 4×2, 1×1 → 1×1), `1×1` live widgets do not
     turn into icons.
- **ACP Closure:**
  - Write acceptance report at `agent/reports/YYYY-MM-DD-milestone-23-acceptance.md`.
  - Update `agent/STATE.md`, `agent/progress.yaml`, and run `./agent/scripts/acp-validate`.

## Acceptance

- All unit and UI smoke tests pass on iOS Simulator with zero compiler errors.
- All 7 hardware checklist items pass on device (or remaining hardware items are
  explicitly documented in the acceptance report if executed code-side first).
- `./agent/scripts/acp-validate` exits 0.

## Notes

- Keep UI tests deterministic using `UITestLaunchFlags` and explicit leaf
  accessibility identifiers.
