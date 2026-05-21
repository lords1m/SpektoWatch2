# Task 5: Density & Numerals Application

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-12-liquid-glass-redesign`
Depends on: task-1, task-2

## Goal

Propagate the `Density` and `NumeralStyle` design tokens (already
persisted via `@AppStorage` in task-1) into actual layout padding and
per-widget number rendering.

## Landed (2026-05-21)

### Density

- `ModularDashboardView.dashboardGrid` now reads
  `@Environment(\.designDensity)`. `horizontalPadding`, `topPadding`,
  `bottomPadding`, `gridSpacing`, `stackSpacing` derive from
  `density.cardPadding` / `density.cardGap` instead of being
  hardcoded by width class. Compact-width (≤390pt) tightens by 2pt
  to preserve the pre-token small-screen feel.
- Density mapping (per redesign spec):
  - compact = 10pt padding / 8pt gap
  - standard = 14 / 12 (default)
  - airy = 18 / 16

### Numerals

- New `Font.numerals(_ style:, size:, weight:)` helper in
  `DesignTokens.swift` switches between `.monospaced` (mono) and
  `.default` (sans, SF Pro).
- Wired into:
  - `WidgetCardView.cardHeader` meta pill (value + unit).
  - `ControlBarView` recording-duration readout.
  - `SingleValueWidget` hero readout (was `.rounded`; now respects
    the token, with `monospacedDigit()` to prevent digit reflow).
- Axis ticks, eyebrow caps, and other always-mono surfaces keep
  `Font.eyebrow` / `Font.readout` (per task non-goal).

## Validation

- `xcodebuild -scheme SpektoWatch2 -destination 'generic/platform=iOS
  Simulator' build` → `** BUILD SUCCEEDED **`.
- Local simulator broken; visual acceptance gated on hardware
  (task-6).

## Acceptance status

- [x] Toggling Density in the Tweaks sheet visibly reflows the grid
  (code-side wired; visual gated on hardware).
- [x] Toggling Numerals switches the readouts that exist in the new
  redesign chrome (card meta, control bar time, hero number).
- [ ] Hardware visual pass — gated on task-6.

Promotion to `completed` gated on the hardware pass.
