# Task 5: Performance, Accessibility & Acceptance

Status: pending
Created: 2026-11-26
Milestone: `milestone-24-liquid-glass-system-adoption`
Absorbs: M12 task-6 (hardware acceptance)

## Scope

- **GPU budget:** Instruments (Hitches + Metal System Trace) on iOS 26 with the
  dock over a live spectrogram + waterfall, against the M19 baseline. Budget:
  no new hitches, ≤ 1 ms added frame time (see `docs/performance.md`).
- **Accessibility matrix:** Reduce Transparency, Increase Contrast, Reduce
  Motion, Dynamic Type AX5, VoiceOver labels/identifiers unchanged, 44 pt
  targets.
- **Snapshots:** iOS 18 fallback, iOS 26 glass, Reduce Transparency, dark — for
  dock, edit bar, a sheet, and the Gallery.
- **Resizability:** iPad split view; dock width capped on regular width.
- **M12 task-6 checklist:** themes/accents, presets, edit mode, tweaks
  persistence, transport LED, watch faces, regression scan.
- Write an acceptance report under `agent/reports/`.

## Done when

All six checks in section 6 of `agent/design/liquid-glass-system-adoption.md`
pass, and M12 is closed together with this milestone.
