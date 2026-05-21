# Milestone 12: Liquid Glass Redesign

Status: in_progress
Started: 2026-05-21
Priority: medium
Estimated: 2 weeks

## Goal

Reimplement the SpektoWatch UI in SwiftUI to match the high-fidelity
redesign delivered in `design_handoff_spektowatch_redesign/` (iOS 26
Liquid Glass aesthetic; floating header pill, preset chip rail, compact
transport, dark scientific inner canvas per widget, live theme/accent/
density/numerals/colormap tweaks). Rendering kernels
(`HighEndSpectrogramAdapter`, `WaterfallView`, `LAFGraphView`,
`ChartRenderer`, `SingleValueWidget`, `ToneGeneratorWidget`) stay — only
chrome, header, transport, theming, and navigation change.

## Why

- The current chrome (`backgroundExtensionEffect`, dot-indicator,
  `glassCardLite`) predates iOS 26 Liquid Glass and does not match the
  hand-off mocks the user signed off on.
- Tweaks (theme / accent / density / numerals / colormap) need to be
  user-controllable at runtime, not hard-coded.
- The redesign introduces a named preset rail (11 presets) intended to
  replace dot indicators above the dashboard.

## Scope

1. **Phase 1 chrome + tokens (landed task-1).** Floating header pill,
   preset chip rail, compact transport, `liquidGlassCard` chrome with
   accent edit border + jiggle + circular drag/delete handles,
   `DesignTokens` enums backed by `@AppStorage`, `TweaksPanelView`
   sheet, `DesignTokensReader` root wrapper. iOS only.
2. **Widget card headers.** Add the eyebrow + meta-value row inside
   every widget card (currently chrome wraps the kernel without a
   header strip). Requires per-kernel header taps.
3. **Preset rail wiring.** Map the 11-preset catalogue to
   `DashboardManager` layouts so chip selection swaps content.
   Today the rail is decorative.
4. **Density + numerals application.** Wire the tokens that are read
   from `@AppStorage` into actual grid padding and per-widget number
   rendering. Today the toggles persist but do not yet propagate.
5. **Watch faces (Pegelmesser, Spektrogramm, Tongenerator) +
   complications (Circular Small, Corner, Rectangular, Inline,
   Graphic Bezel) + Modular 4-slot face.** Likely new files in the
   watch target.
6. **Acceptance.** Hardware-pass verification of the full redesign
   under both color schemes and all five accents.

## Non-Goals

- Changing rendering kernels (Metal pipelines, Charts, LAF computation).
- Renaming or restructuring `WidgetConfiguration` / `DashboardManager`.
- Adding new widget types beyond the existing 11.
- Reworking masking or recording flows.
- Backwards-compatible "old chrome" toggle — the redesign replaces the
  old surfaces outright.

## Acceptance

- All 11 presets render under both Light and Dark theme without layout
  regression.
- Tweaks panel toggles take effect immediately and survive relaunch.
- Edit mode shows jiggle + accent border + circular handles on every
  card; preset rail + transport dim correctly.
- Watch app shows the three new faces and at least three complication
  slots use the new chrome.
- Build green; ACP validate passes.
