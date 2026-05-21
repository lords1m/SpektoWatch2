# Task 7-single-value: Single Value (Einzelwert)

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-9-widget-audit`

## Code-side pre-pass (2026-05-21)

Method step 1 completed. Hardware steps 2-5 still pending.

### Surface: settings UI

`SpektoWatch2/WidgetSettingsView.swift` lines 234-253:

| UI control | Persists key | Default | Consumer |
|---|---|---|---|
| Messwert (Picker, 11 options) | `metric` | `WidgetSettings.defaultSingleValueMetric` ("LAF") | ✅ `SingleValueWidget.metricKey` (only when override toggle on) |

Plus override toggle (`useWidgetOverrides`). Picker options:
LAF, LAeq, LAFmin, LAFmax, LAF5, LAF95, LAFT5, LAFTeq, LCpeak,
PHON (loudness in phon), SONE (loudness in sone).

### Surface: render path

`SpektoWatch2/SingleValueWidget.swift`:

- Reads `audioEngine.currentSpectrogramData.levels[metricKey]` on
  receive for the dB metrics.
- For `PHON` / `SONE`, runs `LoudnessCalculator.calculate(spl:frequency:)`
  using the *dominant FFT bin* of the magnitude spectrum + `data.levels["LAF"]`.
- Layout: VStack with metric title (top-left, captioned), large
  numeric value (42 pt rounded, scales down to 21 pt), unit label.
- Title and unit use hardcoded switch statements (`displayTitle`,
  `unitLabel`).
- Defaults to `"0.0"` when `value == nil` or engine isn't running.

### Findings (code-side only — no screenshots yet)

- ✅ `metric` setting is consumed.
- ⚠ **`metric` locked to default when override is OFF** — same
  pattern as frequencyDisplay `bandMode` and waterfall settings. A
  user without the toggle is stuck on `LAF` forever. Same product
  decision: per-widget-only or global default? In this widget's case,
  per-widget makes more sense (multiple Single Value widgets each
  showing a different metric is the obvious use case).
- ⚠ **Picker metrics ≠ LevelHistory metrics** — LevelHistory exposes
  15 options (incl. LAS, LCF, LCS, LZF, LZS, plus AUTO). SingleValue
  shows 11 (no LAS, LCF, LCS, LZF, LZS; adds PHON/SONE). The widget
  code itself just reads `data.levels[metricKey]` — so it *could*
  show LAS/LCF/etc. if they were in the picker. Inconsistency
  between widgets that present "the same" data.
- ⚠ **Title formatting via AttributedString switch** (lines 19-53) —
  9 explicit case-branches + default. Adding a metric to the picker
  requires editing both the picker and this switch. Refactor candidate:
  derive the styled title programmatically from `metricKey`
  (split on `[FS5T]` boundaries, baseline-offset the subscript portion).
- ⚠ **"0.0" placeholder when not running** — visually identical to a
  real reading of 0 dB. Confusing in screenshots; use "—" or "n/a"
  to signal "no data".
- ⚠ **Loudness fallback uses `data.levels["LAF"]`** regardless of
  upstream weighting — same finding as LevelHistory task-3, finding #2.
  Both widgets share the dominant-bin + LAF coupling. Worth fixing
  in one place (LoudnessCalculator caller helper).
- ⚠ **Unit label by string prefix** (`metricKey.hasPrefix("LA")` etc.)
  works today, but a `metricKey = "L"` (typo / corrupted setting)
  falls through to `"dB"`. Defensive but obscure; structured enum
  would catch this at compile time.
- ⚠ **No font weight indicator for "AUTO" / dynamic metrics** — unlike
  LevelHistory, SingleValue doesn't have an AUTO mode. If we add it,
  the title needs to show whether the displayed value is the user's
  explicit pick or AUTO-derived.

### Pending (hardware)

- 📸 Screenshots per allowed size (`sizeRange(for: .singleValue)`:
  `1×1 … 2×2`).
- 📸 Each of the 11 metrics with the engine running on a stable
  reference signal — confirm decimal precision and unit suffix
  alignment.
- Typography scaling: at 1×1 with a 5-digit value (e.g. `120.4`),
  does `minimumScaleFactor(0.5)` produce a legible result?
- Behaviour during silence (LAF → -120 dB? displays as "-120.0
  dB(A)"?).
- Behaviour mid-recording when the engine is paused.
- PHON/SONE values when the source has no clear dominant
  frequency (broadband noise) — does loudness wobble?

## Subject

- Widget type: `AudioWidgetType.value` (verify exact case in
  `SpektoWatch2/WidgetConfiguration.swift`).
- Source: `SpektoWatch2/AudioWidgets.swift`
- Settings exposed: displayed metric

## Method

1. Read the widget source + its settings sheet. Note every public
   knob and every persisted setting key.
2. Launch on hardware (AGENT.md: local simulator is broken).
3. For every size in `WidgetConfiguration.sizeRange(for: .value)`
   from min to max, capture a screenshot. Edit mode and view mode.
4. Cycle every settings combination. Capture before/after.
5. Stress: silence, clipped input, sample-rate change mid-stream,
   recording active vs inactive, dark mode, light mode.

## Specific checks

- typography scaling 1×1 → 2×2 (max per M8); decimal-precision rules; unit suffix placement; behaviour during silence.
- Layout integrity at each allowed size.
- Touch-target accessibility (>= 44pt).
- Color contrast pass for the displayed metric text.
- No `Logger` errors / warnings on the relevant subsystem during
  the audit.
- Settings persist across app restart.

## Output

- `agent/screenshots/m9-value-<n>.png` (or linked from a shared
  album — note the source location here).
- Per-screenshot one-line annotation in this task file under
  "Findings".
- Findings split into: ✅ confirmed working, ⚠ open issue (file
  follow-up + link), ❌ broken (block acceptance).

## Acceptance

- All size + settings combinations covered with at least one
  screenshot.
- Findings list is exhaustive — every ⚠ / ❌ either has a fix in
  this task or a queued follow-up backlog item.

## Non-Goals

- Refactoring the widget's internal architecture beyond fixing
  obvious bugs surfaced by the audit.
- Cross-widget consistency (handled by the acceptance task).
