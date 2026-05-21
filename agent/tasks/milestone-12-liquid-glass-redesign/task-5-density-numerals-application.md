# Task 5: Density & Numerals Application

Status: pending
Created: 2026-05-21
Milestone: `milestone-12-liquid-glass-redesign`
Depends on: task-1, task-2

## Goal

Propagate the `Density` and `NumeralStyle` design tokens (already
persisted via `@AppStorage` in task-1) into actual layout padding and
per-widget number rendering.

## Scope

- `Density` → `ModularDashboardView.dashboardGrid` grid spacing,
  card padding, vertical insets. Map: `compact = 10pt padding /
  8pt gap`, `standard = 14 / 12`, `airy = 18 / 16`.
- `NumeralStyle` → all readouts that currently use `.system(.body,
  design: .monospaced)` or `.monospacedDigit()`. Switch between
  `.monospaced` (mono) and `.default` (sans) based on
  `Environment(\.designNumerals)`.
- Hero number font (SingleValueWidget) and meta values
  (task-2 header) read from the same environment.

## Non-Goals

- Adding a third density preset.
- Changing axis tick fonts (always mono).

## Acceptance

- Toggling Density in the Tweaks sheet visibly reflows the grid.
- Toggling Numerals in the Tweaks sheet switches all readouts.
