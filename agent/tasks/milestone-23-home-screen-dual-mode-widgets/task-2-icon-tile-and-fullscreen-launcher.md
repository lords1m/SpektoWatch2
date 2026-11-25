# Task 2: Icon Tile View & Unified Fullscreen Launcher

Status: pending
Created: 2026-11-25
Milestone: `milestone-23-home-screen-dual-mode-widgets`

## Goal

Create `FeatureIconTileView` for crisp iOS-Home-Screen-style `1×1` launcher
tiles and `FeatureFullScreenHostView` so tapping any icon opens that feature's
dedicated fullscreen/sheet view with zero idle Metal or audio overhead.

## Scope

- **`FeatureIconTileView` (`SpektoWatch2/HomeScreen/FeatureIconTileView.swift`):**
  - `1×1` Liquid Glass launcher tile featuring an accent-tinted glass squircle
    with SF Symbol, concise 1–2 line German label, and optional lightweight
    badge (e.g., recording count on `Aufnahmen`, active tone status on
    `Tongenerator`, metric label on `Einzelwert`).
  - Subtle press scale/highlight feedback on tap; no Metal views, no
    `HighEndSpectrogramAdapter`, and no 15 Hz `AudioEngine` live subscriptions.
  - German VoiceOver label + hint (`"<Name>, Icon. Tippen zum Öffnen."`) and
    ≥44×44 pt accessible tap target.
- **`FeatureLauncherDestination` & `FeatureFullScreenHostView`:**
  - `Identifiable` destination model carrying the tapped `WidgetConfiguration`
    (including per-widget `settings` such as `SingleValue` metric or
    `FrequencySpectrum` band mode).
  - Unified presenter mounted once at `ModularDashboardView` level
    (`.fullScreenCover(item:)` / `.sheet(item:)`) routing every `AudioWidgetType`:
    - `.spectrogram` → Fullscreen `InteractiveLiveSpectrogramView`
    - `.levelHistory` → Fullscreen `LevelHistoryWidget` / `LevelHistoryView`
    - `.frequencyDisplay` / `.octaveBands` → Fullscreen `FrequencySpectrumWidget`
    - `.levelMeter` → Fullscreen `LevelMeterWidget`
    - `.singleValue` → Fullscreen `SingleValueWidget`
    - `.toneGenerator` → Fullscreen `ToneGeneratorWidget`
    - `.spektralanalyseLab` → Fullscreen `SpektralanalyseLaborWidget`
    - `.audioEditor` → `AudioEditorView` (latest recording or file importer)
    - `.recordings` → `RecordingsListView`
    - `.settings` → `SettingsRootView`
  - Consistent top close bar (`Schließen`, title, and live status badge where
    relevant) using Liquid Glass styling.
- **`WidgetCardView` Tap Wiring:**
  - When `widget.displayStyle == .icon` and `!isEditMode`, tapping the card
    invokes `onLaunchFeature(widget)`.

## Acceptance

- Tapping any `1×1` icon tile launches the matching dedicated fullscreen/sheet
  view cleanly and closes without leaking engine/player state.
- Idle `.icon` tiles create zero Metal drawables or 15 Hz view re-renders.

## Notes

- Reuse `ModularDashboardView`'s existing `AppServices` environment object so
  launched views share the single `AudioEngine` and `RecordingManager`.
