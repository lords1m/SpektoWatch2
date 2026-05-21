# Task 1: Chrome & Tokens (Phase 1)

Status: completed
Created: 2026-05-21
Completed: 2026-05-21
Milestone: `milestone-12-liquid-glass-redesign`
Branch: `redesign/liquid-glass`

## Scope landed

Reimplemented the dashboard chrome from
`design_handoff_spektowatch_redesign/README.md` natively in SwiftUI.
Rendering kernels untouched.

### New files

- `SpektoWatch2/DesignTokens.swift` — `ThemeMode`, `AccentChoice`
  (phosphor / amber / cyan / magenta / paper, OKLCH mapped to sRGB),
  `Density`, `NumeralStyle`, `Colormap`, `CanvasMode` (all
  `@AppStorage`-backed via `DesignTokensReader`). `liquidGlassCard`,
  `floatingPill`, `innerCanvas`, `editJiggle` modifiers. Dark
  scientific-canvas gradient. Per-widget SF Symbol mapping. 11-preset
  catalogue (`PresetCatalogue.all`).
- `SpektoWatch2/PresetRailView.swift` — horizontal chip rail; active
  chip uses accent fill + glow; auto-scrolls selection to center;
  dims to 35% in edit mode.
- `SpektoWatch2/TweaksPanelView.swift` — bottom sheet exposing every
  token. `DesignTokensReader` wires `preferredColorScheme`, `tint`,
  and `Environment` values from `@AppStorage`.

### Modified files

- `DashboardHeaderView.swift` — floating pill: eyebrow
  `DASHBOARD · LIVE` + layout name + 3 glass circles (gear / layouts
  / sparkles=tweaks) + pencil. Edit mode → eyebrow
  `LAYOUT BEARBEITEN`, hides gear/layers, pencil → green "Fertig"
  pill.
- `ControlBarView.swift` — `floatingPill` chrome, new `StatusLED`
  (pulsing live/recording), tabular-mono duration readout.
- `WidgetCardView.swift` — `liquidGlassCard` chrome with accent edit
  border + glow; edit overlays = accent circular drag handle
  (top-left) + red delete circle (top-right) replacing the old
  capsule pair; per-card jiggle rotation desynced via UUID hash.
- `ModularDashboardView.swift` — root wrapped in
  `DesignTokensReader`; preset rail rendered below the header; old
  dot indicator removed; Tweaks sheet wired.

## Validation

- `xcodebuild -scheme SpektoWatch2 -destination 'generic/platform=iOS
  Simulator' build` → `** BUILD SUCCEEDED **`.
- Local simulator broken (per AGENT.md); visual acceptance gated on
  hardware/Cloud and tracked under task-6.

## Deferred to follow-up tasks

- Eyebrow + meta header *inside* each widget card → task-2.
- Preset rail → layout wiring → task-3.
- Density / Numerals token application → task-5.
- Watch faces and complications → task-4.

## Commit

`21453dd` on branch `redesign/liquid-glass`.
