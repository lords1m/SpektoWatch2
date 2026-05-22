# Task 10-masking: Sound Masking

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-9-widget-audit`

## Subject

- Widget type: `AudioWidgetType.masking`
- Source: `SpektoWatch2/Masking/MaskingEntryWidget.swift` +
  `MaskingEngine.swift` + supporting files in
  `SpektoWatch2/Masking/`.
- Settings exposed: **none** (see findings).

## Method

1. Read the widget source + its settings sheet. Note every public
   knob and every persisted setting key.
2. Launch on hardware (AGENT.md: local simulator is broken).
3. For every size in `WidgetConfiguration.sizeRange(for: .masking)`
   (1×1 to 3×3, default 2×2) capture a screenshot in edit + view
   mode.
4. Cycle every settings combination. Capture before/after.
5. Stress: silence, clipped input, sample-rate change mid-stream,
   recording active vs inactive, dark mode, light mode.

## Code-side pre-pass (2026-05-21)

Done from CLI per the existing M9 pattern; hardware screenshots and
cycling pass still required for full acceptance.

### Settings inventory

| Key | Type | Wired? |
|---|---|---|
| (none) | — | — |

The widget takes no `settings: [String: String]` parameter; the
`WidgetSettingsView` switch falls through to the default
`"Keine Einstellungen verfügbar für diesen Widget-Typ."` text.
The MaskingEntryWidget initializer in `WidgetCardView` is
`MaskingEntryWidget(engine: maskingEngine)` — engine state lives
in the `@EnvironmentObject` MaskingEngine and per-widget
configuration is not propagated.

### Internal tunables (not surfaced in any UI)

- `MaskingEngine.minimumCaptures: Int = 3` (public `var` — settable
  in code, not in UI).
- Convergence promotion threshold hardcoded at `convergenceScore
  >= 0.7` in `MaskingEngine.handleNewFrame` (line ~130).
- `SpectralNoveltyDetector` divergence-to-score map hardcoded:
  `rawScore = min(divergence / 20.0, 1.0)`; `scoreAlpha = 0.2`;
  `minCalibrationFrames` derived from `ambientTimeConstant = 10s`
  passed in at init.

### Findings

- ✅ **Single-tap entry point.** The whole card body is a
  `Button(action: { showSheet = true })`, so the touch target is
  the entire card area (well over 44pt at any allowed size).
- ✅ **Defensive empty state.** "Profile" toolbar button hides
  when `profileManager.profiles.isEmpty`.
- ✅ **State indicator is animated** but uses
  `.animation(.easeInOut(...), value: engine.previewPlayer.isPlaying)`,
  not a `repeatForever` — no leak / stuck animation hazard.
- ⚠ **Zero user-facing settings.** Common with other audit-flagged
  widgets (task-5 levelMeter, task-6 phaseMeter — now deactivated
  in M12 — task-8 toneGenerator, task-9 spektralanalyseLab). The
  empty settings sheet behind the gear icon is a cross-widget
  inconsistency. **Acceptance follow-up:** expose at minimum
  `minimumCaptures` (1…10 stepper) and an "Ambient calibration
  time" (5…30s stepper, default 10s).
- ⚠ **Convergence threshold and novelty-divergence scaling are
  hardcoded.** The 0.7 and 20.0 constants drive when the engine
  promotes to `.ready` and how loudly a noise has to deviate from
  the ambient model. Reasonable defaults, but no way to tune for
  different rooms / mic-gain combos. Flag for a future tunables
  sheet — not blocking.
- ⚠ **"Neu aufnehmen" has no confirmation.** Tapping the red
  toolbar button in the suggestion sheet (`MaskingSuggestionView`)
  calls `engine.reset()` immediately and dismisses, discarding any
  current calibration / capture progress without confirmation.
  Recommend an `.alert` with a destructive button before reset.
- ⚠ **No accessibilityIdentifier on the widget body.** All other
  audit widgets carry an identifier (e.g. `levelHistoryWidget`).
  Add `.accessibilityIdentifier("maskingWidget")` on the outer
  Button for UI-test parity.
- ⚠ **At 1×1 (200pt), the three vertical zones (header, mini
  spectrum, footer) plus 20pt of chrome padding leave ≈ 160pt for
  the spectrum.** Won't crash and won't truncate, but the
  spectrum will be a thin strip — capture a hardware screenshot
  before deciding if it's acceptable. The 1×1 size is in
  `sizeRange(for: .masking)`'s min so users can shrink to it.
- ⚠ **At 3×3 (~636pt), the mini spectrum stretches to fill via
  `maxHeight: .infinity`** but the footer state text stays at 9pt
  mono. Visually the spectrum dominates and the readout looks
  small. Consider scaling the footer text up at larger sizes
  (size-aware typography in a future polish pass — not blocking).
- ⚠ **State color tokens use hardcoded RGB literals** (cyan
  `0.0, 0.85, 1.0`, gold `1.0, 0.80, 0.30`, etc.) rather than
  reading from `AccentChoice` / a shared palette. Cross-widget
  consistency only — not a functional issue.
- ❌ **Open: hardware screenshots still required** for the size
  grid (1×1, 1×2, 1×3, 2×1, 2×2, 2×3, 3×1, 3×2, 3×3 — that's
  9 sizes × 2 modes = 18 screenshots) and stress scenarios.

## Specific checks (deferred to hardware)

- [ ] Trigger fires at the expected threshold against a known signal
- [ ] Abort path (engine.reset) cleans up
- [ ] UI feedback during armed state
- [ ] Threshold persistence (currently N/A — no UI to set thresholds)
- [ ] Layout integrity at each allowed size
- [x] Touch-target accessibility (>= 44pt) — code-side: entire card
  is tappable
- [ ] Color contrast pass for the displayed metric text
- [ ] No `Logger` warnings during the audit
- [ ] Settings persist across app restart (N/A until settings exist)

## Acceptance

- All size + settings combinations covered with at least one
  screenshot.
- Findings list is exhaustive — every ⚠ / ❌ either has a fix in
  this task or a queued follow-up backlog item.

## Non-Goals

- Refactoring the masking engine's signal pipeline.
- Cross-widget consistency (handled by the acceptance task
  `milestone-9-widget-audit/task-11-acceptance.md`).
