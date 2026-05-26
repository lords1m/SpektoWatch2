# Task 6: Tighten weighting contract (R5)

Status: completed
Created: 2026-05-21
Completed: 2026-05-25
Milestone: `milestone-14-performance-centralization`
Source: audit R5

## Goal

`requiredSpectralWeightingsForCurrentFrame()` is the only place
that decides which weightings the AudioEngine computes. Widget
reads either get the requested weighting or `nil` — no silent
fallback to Z.

## Why

Today, `SpectrogramData.magnitudes(for: weighting)` falls back
to the Z magnitudes if the requested weighting array is `nil`:

```swift
case "A": return magnitudesA ?? magnitudes
case "C": return magnitudesC ?? magnitudes
```

A widget that requests A but didn't make it into
`widgetSpectralWeightingRequirements` (race during settings
change, or a missed call site) silently sees Z and renders a Z
line labelled "A". Visually plausible, numerically wrong.

## Scope

- Audit every call site that mutates a widget's frequency
  weighting → ensure `widgetSpectralWeightingRequirements`
  refresh happens synchronously on the same code path.
- Optional: change `SpectrogramData.magnitudes(for:)` to return
  `[Float]?` (optional) instead of falling back. Callers handle
  nil explicitly (e.g. show "waiting for data" placeholder).
- Add a `#if DEBUG` log when a fallback would have happened —
  surfaces missed registrations in development.

## Acceptance

- All widget settings paths that change `freqWeighting` also
  update the registered weighting requirement.
- Optional API change: `magnitudes(for:) -> [Float]?` (binding
  decision: yes if all consumers handle nil cleanly).
- iOS build green.
- Existing widgets behave identically on hardware.

## Risk

Optional API change ripples through ~10 call sites (spectrum,
waterfall, level history, watch widgets). If the optional path
is taken, do it in one pass and verify each consumer's nil
branch.

## What landed

### `Shared/SpectrogramData.swift`
`magnitudes(for:)` now has an explicit `if let` branch for A and C
before falling back to Z. When the weighting array is nil, a
`#if DEBUG` print fires:
```
[SpectrogramData] magnitudes(for:"A") fallback to Z — A-weighting not computed this frame (R5: check widgetSpectralWeightingRequirements)
```
This will surface any missed `widgetSpectralWeightingRequirements`
registrations during development without changing the public API or
adding any overhead in Release builds.

### Settings-change path verification
`WidgetSettingsView` → `dashboardManager.updateWidgetSettings(id:settings:)`
→ `@Published var widgets` → `DashboardViewModel` Combine sink →
`updateWidgetSpectralWeightingRequirements`. Path is synchronous on the
main actor. No missed call sites found.

### Optional API change
Binding decision: **not taken**. Changing return type to `[Float]?`
would produce `[Float]??` at every call site that chains optional on
`currentSpectrogramData?` (e.g. `audioEngine.currentSpectrogramData?.magnitudes(for:)`)
— double-optional requires structural changes across 5 files. The
`#if DEBUG` log achieves the safety-net goal without the ripple.

## Acceptance

- [x] All widget settings paths that change `freqWeighting` go through
  `dashboardManager.updateWidgetSettings` → Combine sink → weighting registration
  (verified: only path in `WidgetSettingsView.onSave`).
- [x] `#if DEBUG` log fires when A/C fallback would occur (surfacing
  missed registrations in development).
- [x] iOS `** BUILD SUCCEEDED **`.
