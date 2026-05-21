# Task 3: Preset Rail Wiring & Preset Compositions

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-12-liquid-glass-redesign`
Depends on: task-1

## Goal

Make the preset chip rail functional. Tapping a chip swaps the
dashboard content to a named composition; the active preset is
persisted.

## Landed (2026-05-21)

- New `SpektoWatch2/PresetCompositions.swift` — maps each
  `DashboardPreset.id` to a concrete `[WidgetConfiguration]` using
  only existing widget types and staying inside each type's
  `WidgetConfiguration.sizeRange(for:)`. All 11 presets mapped:
  - `overview` → singleValue(LAF) + levelMeter + levelHistory + spectrogram
  - `spectrogram` / `waterfall` / `tone` / `lab` → full-bleed 3×4 kernel
  - `level-time` / `spectrum` / `masking` → 3×3 kernel
  - `phase` → 2×2 goniometer
  - `level-meter` → 2×3 meter
  - `single` → 4× singleValue (LAF / LAeq / LCpeak / LAFmin) at 1×1
- `DashboardManager.applyPreset(id:)` — replaces the active layout's
  widgets with the preset composition, persists immediately via
  `saveConfiguration`. Non-destructive to other layouts; preserves
  the layout name.
- `ModularDashboardView.activePresetID` switched from `@State` to
  `@AppStorage("dashboard.activePreset")` so the selected chip
  persists across launches.
- `PresetRailView.onSelect` wired with an `.easeInOut(0.25)`
  cross-fade around `applyPreset`.

## Deferred / not landed

- **`single` 2×2 cluster.** Mock shows 4 readouts as a 2×2 tile. With
  no per-tile `GridPosition` composer in place, the four 1×1
  singleValue widgets currently flow left-to-right in a 3-column
  grid, leaving one cell free on each row. Acceptable for Phase 1;
  pull-in to a cluster needs `gridPosition` plumbing.
- **`level-meter` stereo L/R.** Architecture is single-channel.
  Composition shows one full-height meter to honor the visual
  intent without faking stereo data.
- **"Preset" → "Custom" reset semantics.** Tapping a chip overwrites
  the active layout's widgets. User can save a custom layout first
  via the existing Layouts menu; preset selection does not create
  a separate "preset" layout slot.

## Validation

- `xcodebuild -scheme SpektoWatch2 -destination 'generic/platform=iOS
  Simulator' build` → `** BUILD SUCCEEDED **`.
- Local simulator broken; hardware acceptance gated on task-6.

## Acceptance status

- [x] All 11 chips invoke a composition (build green).
- [x] Selection persists across relaunch (`@AppStorage`).
- [x] Edit mode still works on every preset — `applyPreset` writes to
  `widgets` then `storeWidgetsToActiveLayout`; existing edit
  reorder/resize paths are unchanged.
- [ ] Hardware visual pass — gated on task-6.

Promotion to `completed` gated on the hardware pass.
