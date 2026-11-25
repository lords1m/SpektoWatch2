# Task 6: Acceptance, Automated Tests & Hardware Verification

Status: in_progress
Created: 2026-11-25
Milestone: `milestone-23-home-screen-dual-mode-widgets`

## Goal

Validate the Home-Screen launcher and Dual-Mode Widget system across all build
targets, unit tests, UI smoke tests, simulator screenshots, and on-device
hardware checks, then close Milestone 23 with an ACP acceptance report.

## Scope

- **Multi-Target Build & Unit Tests:**
  - Build all targets (`SpektoWatch2`, `SpektoWatch Watch App`,
    `SpektoWatch Complications`, `SpektoWatch2WidgetExtension`, `SpektoWatch2Tests`).
  - Run `WidgetDisplayStyleMigrationTests`, `WidgetSizingMigrationTests`, and
    existing `SpektoWatch2Tests` regression suites.
- **UI Smoke Tests & Screenshots:**
  - Add `HomeScreenDualModeUITests` in `SpektoWatch2UITests/` verifying:
    1. Default Home Screen renders both live widgets and `1×1` icon tiles.
    2. Tapping a `1×1` icon (e.g. `Aufnahmen` or `Einstellungen` or `Audio-Editor`)
       opens its dedicated view and closes cleanly.
    3. `WidgetPickerView` allows adding a feature explicitly as `Icon` or `Live-Widget`.
    4. `WidgetSettingsView` switches an existing tile between `Live-Widget` and `Icon`.
    5. `PresetRailView` still switches across existing Presets.
  - Refresh simulator screenshots via `./agent/scripts/capture-screenshots.py`.
- **Hardware Acceptance Checklist (On-Device):**
  1. Launch lands on the mixed Home Screen with live readings updating smoothly
     and `1×1` icons crisp in both Light and Dark Liquid Glass modes.
  2. Tapping every function icon opens its dedicated fullscreen/sheet view with
     working audio/engine handoff and clean dismissal.
  3. Idle `.icon` tiles introduce zero Metal drawable allocations or 15 Hz view
     re-renders (verified via Instruments / SwiftUI body instrumentation).
  4. Edit mode (long-press jiggle, drag-reorder, settings gear, delete `×`) works
     smoothly across mixed `Live-Widget` and `Icon` tiles.
  5. Existing saved custom layouts upgrade cleanly without losing sizes or
     converting `1×1` live widgets into icons.
- **ACP Closure:**
  - Write acceptance report at `agent/reports/YYYY-MM-DD-milestone-23-acceptance.md`.
  - Update `agent/STATE.md`, `agent/progress.yaml`, and run `./agent/scripts/acp-validate`.

## Acceptance

- All unit and UI smoke tests pass on iOS Simulator with zero compiler errors.
- All 5 hardware checklist items pass on device (or remaining hardware items are
  explicitly documented in the acceptance report if executed code-side first).
- `./agent/scripts/acp-validate` exits 0.

## Notes

- Keep UI tests deterministic using `UITestLaunchFlags` and explicit leaf
  accessibility identifiers.
