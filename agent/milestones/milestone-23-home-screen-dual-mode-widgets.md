# Milestone 23: Home-Screen Launcher & Dual-Mode Widgets

Status: in_progress
Created: 2026-11-25
Priority: medium
Estimated: 2 weeks

## Goal

Transform the app's main screen (`ModularDashboardView`) into an iOS-Home-Screen-style
hub where users can both view live measurement widgets directly on the Home
Screen and launch any app feature or measurement option from compact `1×1` icons.
**Every** active function and measurement option supports two explicit display
modes: **Icon** (`1×1` launcher tile opening a dedicated fullscreen/sheet view)
or **Live-Widget** (embedded live tile directly on the Home Screen).

## Confirmed UX & Design Decisions

- **Explicit Mode Switcher (No Auto-Collapse on Resize):**
  Users choose `Icon` vs. `Live-Widget` explicitly in `WidgetPickerView` when
  adding an item and in `WidgetSettingsView` when editing an existing tile.
  Resizing a live widget never accidentally collapses it into an icon—preserving
  legitimate `1×1` live widgets such as `Einzelwert` and `Pegel-Meter`.
- **Home-Bildschirm as Default Start Page + Presets Preserved:**
  The default landing page (first slot in `PresetCatalogue`) renders a balanced
  **Home-Bildschirm** combining live hero widgets (`Einzelwert LAF`, `Pegel-Meter`,
  `Pegelverlauf` / `Spektrogramm`) with `1×1` quick-launch function icons
  (`Audio-Editor`, `Aufnahmen`, `Tongenerator`, `Spektralanalyse-Labor`,
  `Einstellungen`). All existing Presets (`Spektrogramm`, `Pegelverlauf`,
  `Frequenz-Spektrum`, `Pegel-Meter`, `Einzelwert`, `Tongenerator`,
  `Spektralanalyse-Labor`) remain swipeable pages in `PresetRailView` and
  customizable via `LayoutsManagementView`.
- **Zero Idle Overhead for Icons:**
  `.icon` tiles do **not** mount Metal drawables, `HighEndSpectrogramAdapter`,
  or 15 Hz `AudioEngine` live subscriptions (unless rendering a lightweight static
  or low-frequency badge), keeping Home-Screen CPU and battery usage minimal.

## Complete Dual-Mode Function Matrix

Every active `AudioWidgetType` supports both **Icon (`1×1`)** and **Live-Widget (Mainscreen)**:

| Function / Measurement (`AudioWidgetType`) | Icon (`1×1`) Target View | Live-Widget (Mainscreen) |
|---|---|---|
| `spectrogram` (`Spektrogramm`) | Fullscreen `InteractiveLiveSpectrogramView` | `SpectrogramWidget` |
| `levelHistory` (`Pegelverlauf`) | Fullscreen `LevelHistoryView` | `LevelHistoryWidget` |
| `frequencyDisplay` (`Frequenz-Spektrum`) | Fullscreen `FrequencySpectrumWidget` | `FrequencySpectrumWidget` |
| `octaveBands` (`1/3 Oktavbänder`) | Fullscreen `OctaveBandWidget` | `FrequencySpectrumWidget` (Terz) |
| `levelMeter` (`Pegel-Meter`) | Fullscreen `LevelMeterWidget` | `LevelMeterWidget` |
| `singleValue` (`Einzelwert`) | Fullscreen `SingleValueWidget` | `SingleValueWidget` |
| `toneGenerator` (`Tongenerator`) | Fullscreen `ToneGeneratorWidget` | `ToneGeneratorWidget` |
| `spektralanalyseLab` (`Spektralanalyse-Labor`) | Fullscreen `SpektralanalyseLaborWidget` | `SpektralanalyseLaborWidget` |
| `audioEditor` (`Audio-Editor`, M22) | `AudioEditorView` | `AudioEditorHomeWidget` |
| `recordings` (`Aufnahmen`) | `RecordingsListView` (with count badge) | `RecordingsHomeWidget` |
| `settings` (`Einstellungen & Kalibrierung`) | `SettingsRootView` | `SettingsQuickWidget` |

## Current State (2026-11-25 Baseline)

- `ModularDashboardView.swift` renders a 3-column grid backed by `DashboardManager`
  and `PresetCatalogue` (`DesignTokens.swift`) + `PresetCompositions.swift`.
- `WidgetConfiguration.swift` defines `AudioWidgetType`, integer `WidgetSize`,
  and `sizeRange(for:)` without a `displayStyle` (`liveWidget` vs. `icon`) or
  types for `.audioEditor`, `.recordings`, and `.settings`.
- `WidgetCardView.swift` supports long-press jiggle edit mode, drag reorder,
  edge resize handles, settings gear, and delete button, and always renders the
  inline live widget view.
- `WidgetPickerView.swift` and `WidgetSettingsView.swift` have no display-mode
  selector.

## Scope & Non-Goals

In scope:
- `WidgetDisplayStyle` (`liveWidget` / `icon`) + backward-compatible `Codable`
  migration + `preferredLiveSize` round-trip preservation.
- `FeatureIconTileView` (`1×1` Liquid Glass Home-Screen icon tile) and unified
  `FeatureFullScreenHostView` launcher mounted at `ModularDashboardView`.
- Inline live widgets for `recordings` (`RecordingsHomeWidget`), `settings`
  (`SettingsQuickWidget`), and wiring `M22`'s `AudioEditorHomeWidget`.
- Explicit mode switching in `WidgetPickerView` and `WidgetSettingsView`, plus
  resize-handle suppression on `.icon` tiles in `WidgetCardView`.
- New default **Home-Bildschirm** composition while preserving all existing
  Presets in `PresetRailView`.
- Unit tests, UI smoke tests, screenshots, and hardware acceptance checklist.

Non-goals:
- Re-enabling deactivated legacy widgets (`.waterfall`, `.phaseMeter`,
  `.masking`) unless separately requested.
- Automatic resize-to-icon collapse (explicitly excluded by UX decision).
- watchOS Home Screen changes.

## Acceptance Criteria

1. **Backward-compatible model migration:** All existing saved custom layouts
   decode cleanly as `.liveWidget` with unchanged sizes.
2. **Dual-mode completeness:** Every active function and measurement option can
   be added as either `Icon` or `Live-Widget` from `WidgetPickerView` and
   explicitly switched in `WidgetSettingsView` (restoring `preferredLiveSize` on
   `.liveWidget` → `.icon` → `.liveWidget` round-trip).
3. **Unified launcher & edit mode:** Tapping any `.icon` tile opens its
   dedicated fullscreen/sheet view; edit-mode jiggle, drag-reorder, settings
   gear, and delete `×` work uniformly for both Icons and Live-Widgets without
   resize handles on `.icon` tiles.
4. **Home-Screen default + Presets preserved:** App launch lands on the mixed
   Home Screen (live hero widgets + `1×1` function icons) while all Presets
   remain swipeable in `PresetRailView`.
5. **Zero idle overhead for Icons:** `.icon` tiles mount no Metal drawables or
   15 Hz audio subscriptions while idle on the Home Screen.
6. **Accessibility & tests:** ≥44 pt tap targets, clear German VoiceOver labels/hints
   distinguishing Icon launcher vs. Live-Widget, and passing unit/UI tests.

## Tasks

1. `task-1-display-style-model-and-feature-catalog` — `WidgetDisplayStyle`, `preferredLiveSize`, `AudioWidgetType` additions (`.audioEditor`, `.recordings`, `.settings`), `DashboardManager` helpers, and migration unit tests.
2. `task-2-icon-tile-and-fullscreen-launcher` — `FeatureIconTileView` (`1×1` Liquid Glass icon), `FeatureLauncherDestination`, and unified `FeatureFullScreenHostView` presenter.
3. `task-3-live-widgets-for-all-app-functions` — `RecordingsHomeWidget`, `SettingsQuickWidget`, and `AudioEditorHomeWidget` wiring into `WidgetCardView`.
4. `task-4-explicit-mode-switching-picker-and-settings` — Explicit `Live-Widget` | `Icon` switchers in `WidgetPickerView` and `WidgetSettingsView`, plus `.icon` handling in `WidgetCardView`.
5. `task-5-home-screen-default-landing-page` — Default mixed Home-Screen landing composition, preserved `PresetRailView` pages, `DashboardHeaderView` polish, and `Localizable.xcstrings`.
6. `task-6-acceptance-and-ui-tests` — Multi-target build, unit + `HomeScreenDualModeUITests`, screenshots, hardware checklist, and ACP acceptance report.
