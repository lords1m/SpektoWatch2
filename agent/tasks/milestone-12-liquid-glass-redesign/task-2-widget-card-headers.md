# Task 2: Widget Card Headers

Status: pending
Created: 2026-05-21
Milestone: `milestone-12-liquid-glass-redesign`
Depends on: task-1

## Goal

Add the eyebrow + meta-value row at the top of every widget card per
the redesign spec (`design_handoff_spektowatch_redesign/README.md §
2 Widget Card`). Wrap each kernel's render output in a dark
`innerCanvas` so the perceptually-uniform colormaps render against the
calibrated dark substrate regardless of theme.

## Scope

- Header: 12pt SF Symbol + 10pt SF Mono uppercase label
  (`tracking 0.18em`, `tertiaryLabel`). Right-aligned meta: main
  metric value in bold, units in `tertiaryLabel`.
- Inner canvas: apply `.innerCanvas()` (defined in
  `DesignTokens.swift`) to each kernel's body. Some kernels
  (SpectrogramWidget, WaterfallView) already render dark; verify they
  don't double up.
- Meta-value source: per widget type. Spectrogram = current cursor
  freq/dB; LevelHistory = current LAF; SingleValue = primary metric;
  Tone = current Hz.

## Non-Goals

- Adding settings or new metrics.
- Changing kernel rendering.

## Acceptance

- Every widget card shows the eyebrow strip.
- Meta values update live where applicable.
- No regressions in widget content layout under any size in
  `WidgetConfiguration.sizeRange(for:)`.
