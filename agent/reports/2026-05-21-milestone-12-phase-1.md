# M12 Phase 1 — Liquid Glass Chrome & Tweaks

Date: 2026-05-21
Branch: `redesign/liquid-glass`
Commit: `21453dd`
Milestone: M12 Liquid Glass Redesign
Task: task-1-chrome-and-tokens (completed)

## Summary

Reimplemented the dashboard chrome from
`design_handoff_spektowatch_redesign/README.md` natively in SwiftUI on a
parallel branch. Rendering kernels untouched. Build green via
`xcodebuild -scheme SpektoWatch2 -destination 'generic/platform=iOS
Simulator' build` → `** BUILD SUCCEEDED **`.

## Files

### New

- `SpektoWatch2/DesignTokens.swift` — `ThemeMode`, `AccentChoice`
  (phosphor / amber / cyan / magenta / paper, OKLCH→sRGB), `Density`,
  `NumeralStyle`, `Colormap`, `CanvasMode`; `liquidGlassCard`,
  `floatingPill`, `innerCanvas`, `editJiggle` modifiers; dark canvas
  gradient; per-widget SF Symbol map; `PresetCatalogue.all` (11
  presets).
- `SpektoWatch2/PresetRailView.swift` — horizontal chip rail with
  accent-filled active chip + glow; auto-scroll to selection; dims in
  edit mode.
- `SpektoWatch2/TweaksPanelView.swift` — bottom sheet exposing every
  token; `DesignTokensReader` root wrapper sets
  `preferredColorScheme`, `tint`, and `Environment` values from
  `@AppStorage`.

### Modified

- `DashboardHeaderView.swift` — floating pill: eyebrow + title +
  glass icon buttons (gear / layouts / sparkles=tweaks) + pencil;
  edit-mode variant.
- `ControlBarView.swift` — `floatingPill` chrome + new `StatusLED`
  (pulsing) + tabular-mono duration.
- `WidgetCardView.swift` — `liquidGlassCard` chrome + accent edit
  border + glow; circular drag/delete handles replacing old capsule
  pair; per-card jiggle desynced via UUID hash.
- `ModularDashboardView.swift` — root wrapped in
  `DesignTokensReader`; preset rail rendered below header; dot
  indicator removed; Tweaks sheet wired.

## Decisions

- **Branch over main.** Parallel work; M8 acceptance still gates
  on hardware, redesign work shouldn't block that.
- **Chrome-only scope.** Did not touch any widget kernel
  (SpectrogramWidget, WaterfallView, LAFGraphView, etc.) — adding
  the eyebrow + meta-value header inside each card is task-2.
- **OKLCH → sRGB.** Approximated by hand rather than pulling in a
  conversion library. Phosphor green visibly matches the mock; other
  accents are close. Revisit if the user flags drift.
- **Preset rail decorative.** The 11-chip rail renders and animates
  but does not yet swap dashboard content (task-3).
- **Density / Numerals.** Tokens persist via `@AppStorage` but are
  not yet wired into grid padding or per-widget number rendering
  (task-5).

## Validation

- `xcodebuild` build green on iOS Simulator generic destination.
- No automated tests touched.
- Local simulator is broken (AGENT.md constraint); visual acceptance
  deferred to task-6 (hardware / Xcode Cloud).

## Risks / Next Actions

- The `DesignTokensReader` `preferredColorScheme` modifier may
  conflict with existing color-scheme assumptions inside individual
  widgets — needs a hardware pass to verify no widget breaks under
  forced dark/light.
- The pencil and Fertig button paths animate independently of the
  existing `viewModel.dashboardManager.isEditMode` consumers; verify
  the existing long-press-to-enter-edit gesture in `ModularDashboardView`
  still composes cleanly under task-6.
- Old `glassCardLite` / `backgroundExtensionEffect` callers still
  exist elsewhere (e.g. `WidgetCardView` resize handle backgrounds,
  hidden-handle drag chip). No regression — `GlassStyle.swift` was
  not deleted — but worth a sweep during task-2.

## Up-next when M12 work resumes

Task-2 (Widget Card Headers) is the natural next pickup: it
unblocks task-5 (numerals are most visible in card meta values) and
delivers the most user-visible fidelity gap remaining.
