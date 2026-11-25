# Task 4: Explicit Mode Switching in Picker, Settings & Card Chrome

Status: pending
Created: 2026-11-25
Milestone: `milestone-23-home-screen-dual-mode-widgets`

## Goal

Implement the explicit `Live-Widget` vs. `Icon` mode controls in
`WidgetPickerView` and `WidgetSettingsView`, and update `WidgetCardView` so
`.icon` tiles suppress resize handles and card headers cleanly while keeping
full edit-mode reorder/delete/settings support.

## Scope

- **`WidgetPickerView.swift`:**
  - Add a prominent top segmented picker (`Live-Widget` | `Icon`) with a brief
    helper caption explaining the selected representation.
  - Organize entries into clear sections: `Visualisierung`, `Pegel & Metriken`,
    and `Werkzeuge & Funktionen` (including `Audio-Editor`, `Aufnahmen`, and
    `Einstellungen`).
  - Pass the chosen `WidgetDisplayStyle` to `dashboardManager.addWidget(type:displayStyle:)`.
- **`WidgetSettingsView.swift`:**
  - Add a top `Darstellung` section with an explicit segmented picker
    (`Live-Widget` | `Icon`) bound to the widget's `displayStyle`.
  - When `Icon` is selected, hide live-widget-only configuration sections
    (Y-axis bounds, colormap, noise floor, orientation, etc.) and display a
    short explanation that tapping the icon opens the full view.
  - Saving a mode switch calls `dashboardManager.setDisplayStyle(_:for:)` (or
    propagates the updated `WidgetDisplayStyle` via `onSave`) so `preferredLiveSize`
    is preserved and restored.
- **`WidgetCardView.swift`:**
  - When `widget.displayStyle == .icon`:
    - Render `FeatureIconTileView` edge-to-edge (no card header strip).
    - **Suppress resize handles** (`resizeHandles` omitted when `.icon`) so
      users cannot drag-resize a `1×1` icon or confuse resizing with mode
      switching.
    - Keep long-press jiggle edit mode, drag handle, settings gear button (to
      switch back to `Live-Widget`), and delete `×` button.

## Acceptance

- Users can add any function directly as an `Icon` or as a `Live-Widget` from
  `WidgetPickerView`.
- Switching an existing tile between `Live-Widget` and `Icon` in
  `WidgetSettingsView` works cleanly and restores `preferredLiveSize`.
- Drag-resizing a live widget never automatically turns it into an icon.

## Notes

- Preserve all existing iOS 26 accessibility identifiers (`widgetSettingsButton`,
  `widgetDeleteButton`, `widgetPickerView`) on leaf views.
