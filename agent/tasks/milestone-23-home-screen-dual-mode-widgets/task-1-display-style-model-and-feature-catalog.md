# Task 1: Display Style Model & Feature Catalog

Status: pending
Created: 2026-11-25
Milestone: `milestone-23-home-screen-dual-mode-widgets`

## Goal

Extend `WidgetConfiguration`, `AudioWidgetType`, and `DashboardManager` so every
app feature and measurement option can be represented explicitly as either a
`.liveWidget` or a `1×1` `.icon` launcher without breaking existing saved layouts.

## Scope

- **`WidgetDisplayStyle` (`WidgetConfiguration.swift`):**
  - Add `enum WidgetDisplayStyle: String, Codable, CaseIterable, Equatable { case liveWidget, icon }`.
  - Add `var displayStyle: WidgetDisplayStyle = .liveWidget` and
    `var preferredLiveSize: WidgetSize?` to `WidgetConfiguration` so switching
    `.liveWidget` → `.icon` → `.liveWidget` restores the previous live size.
  - Ensure `WidgetConfiguration.init(from:)` decodes legacy JSON lacking
    `displayStyle` or `preferredLiveSize` safely as `.liveWidget`.
- **Feature Catalog (`AudioWidgetType` & `DesignTokens.swift`):**
  - Add `.audioEditor` (`"Audio-Editor"`), `.recordings` (`"Aufnahmen"`), and
    `.settings` (`"Einstellungen"`) to `AudioWidgetType` and `allCases` (keeping
    `.waterfall`, `.phaseMeter`, `.masking` in `deactivated`).
  - Add SF Symbols in `DesignTokens.swift` (`AudioWidgetType.sfSymbol`) and
    per-type `sizeRange` / `baseRowHeight` entries for the new live widgets.
  - Update `WidgetConfiguration.normalizedSize` and `sizeRange(for:displayStyle:)`
    so `.icon` configurations always normalize to `1×1` (base row height ~96 pt)
    while `.liveWidget` uses each type's existing sizing matrix.
- **`DashboardManager` Helpers:**
  - Add `addWidget(type:displayStyle:)` and `setDisplayStyle(_:for:)` (saving
    `preferredLiveSize` when switching to `.icon` and restoring it when
    switching back to `.liveWidget`).
- **Unit Tests (`SpektoWatch2Tests/WidgetDisplayStyleMigrationTests.swift`):**
  - Verify legacy `WidgetConfiguration` JSON decodes as `.liveWidget` with
    unchanged `WidgetSize`.
  - Verify `.liveWidget` → `.icon` → `.liveWidget` round-trip restores
    `preferredLiveSize`.
  - Verify `.icon` always normalizes to `1×1` and `1×1` `.liveWidget`
    (`singleValue`, `levelMeter`) stays `.liveWidget`.

## Acceptance

- Existing custom layouts migrate with zero data loss or unintended mode changes.
- All active `AudioWidgetType` cases have valid SF Symbols, live size ranges,
  and `1×1` icon normalization.
- `WidgetDisplayStyleMigrationTests` compile and pass.

## Notes

- Keep `WidgetSize` unaware of `WidgetDisplayStyle`; enforce mode-specific sizing
  at the `WidgetConfiguration` / `DashboardManager` layer.
