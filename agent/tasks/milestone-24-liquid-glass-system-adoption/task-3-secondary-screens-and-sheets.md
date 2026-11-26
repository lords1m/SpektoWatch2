# Task 3: Secondary Screens & Sheets

Status: completed
Created: 2026-11-25
Milestone: `milestone-24-liquid-glass-system-adoption`
Commit: `615c1a3`

## Goal

System glass toolbars on pushed screens, a sheet audit, and removal of ad-hoc
materials from the content layer.

## Outcome (iPhone 17 / iOS 26.5 simulator)

- Cancel buttons (audio editor, masking suggestion, trigger acquisition ×2,
  feature full-screen close) use `.cancellationAction`; close glyph `xmark`.
- `RecordingDetailView`: `.navigationBarTrailing` → `.topBarTrailing`.
- Sheets stay opaque by design (`polishedFormChrome` behind dense forms);
  `FerriteGlassSheet` retired.
- Watch settings sync bar → floating `ferriteGlass` panel via `ferriteBar`.
- Spectrum legend capsule → solid `surfaceSunken`. Removed
  `canvasControlButton`, `transportGlassButton`, `CanvasReadoutPill`.
- The iOS target has no `Material` left outside `DesignSystem/`.

## Not checked on screen

Feature full-screen close button, spectrum legend, iOS 18 fallback. Covered by
task-5.
