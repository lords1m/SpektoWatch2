# Milestone 8: Widget Sizing Refactor

Status: in_progress
Started: 2026-05-21
Priority: medium
Estimated: 0.5 weeks

## Goal

Replace the current continuous-row (Double, 0.5-step) widget sizing with
per-widget-type minimum/maximum constraints and integer-only rows.
Underlying 3-column grid stays — only sizing semantics change.

## Why

- The 0.5-row stepping creates pointless intermediate sizes ("etwas
  kleiner als 2 Reihen") without UX value. App-Store-style fixed-step
  tiling is the visual target.
- Every widget can currently shrink to 1×0.5 and grow to 4×∞ regardless
  of type. Spectrogram at 1×0.5 is unreadable; single-value widget at
  3×4 wastes screen.
- Resize handles snap to the global `(cols ∈ [1,4], rows ≥ 0.5)`
  constraint, ignoring the widget type — drag UX feels arbitrary.

## Scope

1. **`WidgetSize.rows: Double` → `Int`.** Drop `minimumRows = 0.5`.
   Decoder rounds legacy `Double` values to `Int` and clamps to the
   per-type minimum.
2. **New API:** `WidgetConfiguration.sizeRange(for type:) -> (min:
   WidgetSize, max: WidgetSize)`. Single source of truth for per-type
   constraints; `defaultSize(for:)` reads from it.
3. **Resize-Logik** in `WidgetCardView.handleResize` and
   `DashboardManager.resizeWidget` clampt gegen `sizeRange(for:)` statt
   gegen globalem `[1,4]/≥0.5`.
4. **Bugfix:** `DashboardManager.firstLaunchWidgets` setzt
   `columns: 4` — auf 3 reduzieren (Grid ist 3 Spalten breit; Wert wird
   bereits zur Laufzeit auf 3 geclampt, aber sollte konsistent sein).
5. **Migration:** Bestehende persistierte Dashboards weiterhin decodebar.
   Werte außerhalb der neuen Range werden beim Decode geclampt; kein
   Datenverlust für User.

## Size Matrix

| Widget | Default | Min | Max |
|---|---|---|---|
| spectrogram | 3×3 | 2×2 | 3×4 |
| waterfall | 3×3 | 2×2 | 3×4 |
| levelHistory | 3×2 | 2×1 | 3×3 |
| frequencyDisplay | 3×2 | 2×1 | 3×3 |
| levelMeter | 1×2 | 1×1 | 2×3 |
| octaveBands | 3×2 | 2×1 | 3×3 |
| phaseMeter | 1×2 | 1×1 | 2×2 |
| singleValue | 1×1 | 1×1 | 2×2 |
| toneGenerator | 3×3 | 2×2 | 3×4 |
| spektralanalyseLab | 3×3 | 2×2 | 3×4 |
| masking | 2×2 | 1×1 | 3×3 |

## Non-Goals

- Ändern des 3-Spalten-Grids (bleibt fest).
- Drag-and-Drop-Reorder (unverändert).
- Widget-Picker UI (Picker zeigt weiterhin alle `AudioWidgetType`s).
- watchOS-Dashboard (separates Layout-Modell, hier nicht im Scope).

## Acceptance

- `WidgetSize.rows` ist `Int`, kein `Double`-Pfad mehr im Modell.
- `sizeRange(for:)` existiert und wird sowohl von `defaultSize` als
  auch von Resize-Handlern konsumiert.
- Spectrogram-Widget kann nicht auf < 2×2 geschrumpft werden;
  Single-Value kann nicht auf > 2×2 wachsen.
- Legacy-Dashboards laden ohne Crash; Werte außerhalb der Range werden
  sichtbar geclampt (Reload nach App-Restart).
- `firstLaunchWidgets` enthält keine `columns: 4` mehr.
