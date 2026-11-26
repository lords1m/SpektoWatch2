# Task 2: Home Shell

Status: completed
Created: 2026-11-25
Milestone: `milestone-24-liquid-glass-system-adoption`
Commit: `b1671b7`

## Goal

Apply glass grouping to the Home Screen: edit bar, page indicator + dock,
undo snackbar.

## Outcome (verified on iPhone 17 / iOS 26.5 simulator)

- Edit-bar buttons in one `FerriteGlassGroup`; slide-in becomes a fade under
  Reduce Motion.
- Page indicator + dock in one `FerriteGlassGroup(spacing: 0)`; dock uses
  `ferriteEdgeGlass` (concentric corners on iOS 26); bottom stack attached via
  `ferriteBar`.
- Undo snackbar uses `ferriteGlass` (no own material, stroke or shadow). Not
  checked on screen.
- Dead `footerBarHeight` measurement removed.

## Deviations from plan

- No header pill exists on the M23 Home Screen, so there is no pill ↔ edit-bar
  morph.
- Transport stays as solid Home Screen icon tiles on the glass dock (glass
  buttons would break the M23 look).
- The top edit bar stays on `safeAreaInset`: `safeAreaBar` offset the
  conditionally inserted bar by 10–28 pt after exit → re-enter on iOS 26.5.
  `ferriteBar` is documented as persistent-bars-only.

## Known issue (pre-existing)

Tall widgets are clipped at the page indicator in edit mode.
