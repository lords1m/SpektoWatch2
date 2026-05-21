# Task 3: Preset Rail Wiring & Preset Compositions

Status: pending
Created: 2026-05-21
Milestone: `milestone-12-liquid-glass-redesign`
Depends on: task-1

## Goal

Make the preset chip rail functional. Tapping a chip swaps the
dashboard content to a named composition; the active preset is
persisted.

## Scope

- Map `PresetCatalogue.all` (11 presets) onto `DashboardManager`
  layouts. Two options to pick between:
  - **A.** Built-in immutable layouts per preset, alongside the
    user's custom layouts. (Mockup behavior.)
  - **B.** Seed each preset id once into the layout store; treat
    layouts as fully editable thereafter.
- Build the 11 compositions per
  `design_handoff_spektowatch_redesign/README.md § 3 Presets`. Use
  existing widget types — no new types.
- Persist active preset id in `@AppStorage("dashboard.activePreset")`.
- Cross-fade content on switch.

## Non-Goals

- Adding new widget types.
- Restructuring `DashboardManager` persistence.

## Acceptance

- All 11 chips render their intended composition.
- Selection persists across relaunch.
- Edit mode still works on every preset.
