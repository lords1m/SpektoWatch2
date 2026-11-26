# Task 4: watchOS

Status: pending
Created: 2026-11-26
Milestone: `milestone-24-liquid-glass-system-adoption`

## Goal

Bring the watch app onto the same layer model.

## Scope

Files: `SpektoWatch Watch App/WatchGlassStyle.swift`,
`WatchDashboardView.swift`, `WatchRecordButton.swift`, watch faces.

- `WatchGlassBar` → `ferriteGlass` (gated `watchOS 26`, material fallback
  below).
- `WatchGlassCard` is content → solid card, no material, no shadow.
- Record button → prominent tinted glass; other controls → `.glass`.
- No glass over live spectrogram/level canvases on the faces. Under
  `isLuminanceReduced` (Always-On), glass becomes a solid dim fill.

## Done when

- watchOS build green.
- `grep Material "SpektoWatch Watch App"` finds only the gated fallback.
- Faces render correctly in Always-On (simulator).
