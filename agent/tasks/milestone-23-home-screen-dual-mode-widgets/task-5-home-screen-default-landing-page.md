# Task 5: Home-Screen Default Landing Page & Presets Integration

Status: pending
Created: 2026-11-25
Milestone: `milestone-23-home-screen-dual-mode-widgets`

## Goal

Make the app's default landing page a true **Home-Bildschirm** combining live
measurement widgets with `1×1` quick-launch function icons, while preserving all
existing Presets in `PresetRailView` and custom layouts in
`LayoutsManagementView`.

## Scope

- **`PresetCatalogue` (`DesignTokens.swift`) & `PresetCompositions.swift`:**
  - Update the first/default preset (`"overview"` labeled `"Home"` or a new
    `"home"` first page with safe migration for saved `@AppStorage("dashboard.activePreset")`)
    to compose a balanced Home Screen:
    - Top live hero area: `Einzelwert (LAF)` (`2×2`) + vertical `Pegel-Meter`
      (`1×2`) + compact live `Pegelverlauf` or `Spektrogramm` (`3×2`).
    - Bottom quick-launch icon row (`1×1` `.icon` tiles): `Audio-Editor`,
      `Aufnahmen`, `Tongenerator`, `Spektralanalyse-Labor`, `Einstellungen`
      (and/or `Frequenz-Spektrum`).
  - Keep all dedicated Presets (`Spektrogramm`, `Pegelverlauf`,
    `Frequenz-Spektrum`, `Pegel-Meter`, `Einzelwert`, `Tongenerator`,
    `Spektralanalyse-Labor`) as swipeable pages in `PresetRailView`.
- **Header & Localization:**
  - Update `DashboardHeaderView` eyebrow (`HOME · LIVE` on the Home Screen,
    `DASHBOARD · LIVE` on other presets, `BENUTZERDEFINIERT · LIVE` on custom
    layouts).
  - Add all new German/English strings (`Live-Widget`, `Icon`, `Darstellung`,
    `Audio-Editor`, `Aufnahmen`, `Einstellungen`, `Home`, etc.) to
    `SpektoWatch2/Localizable.xcstrings`.

## Acceptance

- Cold launch opens directly on the new mixed Home Screen showing live values
  plus clickable `1×1` feature icons.
- Swiping left/right or tapping chips in `PresetRailView` still navigates across
  all existing full-page Presets.
- Custom layouts created in `LayoutsManagementView` can freely mix `.liveWidget`
  and `.icon` tiles.

## Notes

- Verify grid row wrapping on compact iPhone widths (`<= 390 pt`) so 3-column
  rows of `1×1` icons align evenly without awkward orphans.
