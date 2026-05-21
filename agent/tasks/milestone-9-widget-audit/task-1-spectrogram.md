# Task 1-spectrogram: Spectrogram

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-9-widget-audit`

## Code-side pre-pass (2026-05-21)

Method step 1 ("Read the widget source + its settings sheet. Note every
public knob and every persisted setting key") completed code-side.
Hardware steps 2-5 still pending.

### Surface: settings UI

`SpektoWatch2/WidgetSettingsView.swift` lines 38-99, section "Spektrogramm Einstellungen":

| UI control | Persists key | Default | Consumer |
|---|---|---|---|
| Farbschema (Picker) | `colormap` | `WidgetSettings.defaultSpectrogramColormap` (0) | ✅ `SpectrogramWidget.colormapType` |
| Dargestellter Zeitbereich (Picker) | `timeSpan` | `WidgetSettings.defaultTimeSpanSeconds` (5) | ✅ `SpectrogramWidget.timeSpan` |
| Zeitbewertung (Picker, Fast/Slow) | `timeWeighting` | `"Fast"` | ❌ **DEAD** — `SpectrogramWidget` never reads it; only `LAFGraphView`/`LAFGraphWidget` consume `settings["timeWeighting"]`. The picker writes to a key with no effect on the spectrogram render. |
| Frequenzbewertung (Picker, Z/A/C) | `freqWeighting` | `"Z"` | ✅ `SpectrogramWidget.freqWeighting` (when override toggle on) |
| Dynamikbereich slider 60-110 dB step 5 | `sensitivity` | `WidgetSettings.defaultSpectrogramSensitivity` (90.0) | ✅ `SpectrogramWidget.sensitivity` |

Plus the global override toggle: `useWidgetOverrides` (boolean). When off,
the widget uses app-global `audioEngine.frequencyWeighting` and built-in
defaults for colormap/sensitivity — only `timeSpan` survives the override.

### Surface: render path

`SpectrogramWidget.body` (`SpektoWatch2/SpectrogramWidget.swift`) passes
through to `HighEndSpectrogramAdapterWithAxes` with:

- `colormapType` (Int → ColormapType)
- `timeSpan` (SpectrogramTimeSpan)
- `scrollSpeed` (read from `audioEngine.scrollSpeed`, **not exposed in
  per-widget settings** — driven app-globally)
- `isPaused` (derived from engine status)
- `scrollOffset` (constant `0.0` — appears unused; check before flagging)
- `freqWeighting`
- `sensitivity`
- `frequencySmoothing` (read from `audioEngine.spectrogramFrequencySmoothing`,
  app-global only, no per-widget knob)

### Findings (code-side only — no screenshots yet)

- ✅ **Dead setting `timeWeighting`** — picker removed from
  `WidgetSettingsView.swift` (Fast/Slow choice was orphaned for
  spectrogram; only level-history widgets consume the key). Legacy
  persisted `timeWeighting` values on existing dashboards are silently
  ignored.
- ✅ **Unused `scrollOffset` knob** — removed from the spectrogram
  pipeline end-to-end: parameter dropped from
  `HighEndSpectrogramAdapterView`, `HighEndSpectrogramAdapterWithAxes`,
  and `SpectrogramWidgetView`; `setManualScrollOffset` accessor,
  `manualScrollOffset` storage, and the `+ manualScrollOffset` add in
  `draw(_:)` all deleted. Zero callers ever set a non-zero value.
- ✅ **Per-widget `frequencySmoothing` slider** added to the
  spectrogram settings sheet (range 0.0–1.0, step 0.05). New
  `SpectrogramWidget.frequencySmoothing` computed property reads
  per-widget value when the override toggle is on, falls back to
  `audioEngine.spectrogramFrequencySmoothing` otherwise. Always-on
  baseline in `HighEndSpectrogramAdapter.applyFrequencySmoothingIfNeeded`
  (2026-05-21 quickwin) is unaffected — this slider stacks on top.
- ✅ Override toggle pattern is consistent with waterfall and
  level-history sections; no inconsistency to flag here.

### Pending (hardware)

- 📸 Screenshots per allowed size (`sizeRange(for: .spectrogram)`:
  `2×2 … 3×4`), edit + view mode, dark + light.
- 📸 Each colormap × each timeSpan combination.
- Sensitivity slider full sweep on a known reference signal.
- Behaviour during silence and clipped input.
- Behaviour at sample-rate change mid-stream.

## Subject

- Widget type: `AudioWidgetType.spectrogram` (verify exact case in
  `SpektoWatch2/WidgetConfiguration.swift`).
- Source: `SpektoWatch2/HighEndSpectrogramAdapter / Metal`
- Settings exposed: colormap, sensitivity, time span, freq min/max

## Method

1. Read the widget source + its settings sheet. Note every public
   knob and every persisted setting key.
2. Launch on hardware (AGENT.md: local simulator is broken).
3. For every size in `WidgetConfiguration.sizeRange(for: .spectrogram)`
   from min to max, capture a screenshot. Edit mode and view mode.
4. Cycle every settings combination. Capture before/after.
5. Stress: silence, clipped input, sample-rate change mid-stream,
   recording active vs inactive, dark mode, light mode.

## Specific checks

- GPU draw at every allowed size (2×2 min … 3×4 max); colormap switching mid-stream; sensitivity slider end-to-end; freq-axis labels not overlapping; behaviour during silence / clipped input.
- Layout integrity at each allowed size.
- Touch-target accessibility (>= 44pt).
- Color contrast pass for the displayed metric text.
- No `Logger` errors / warnings on the relevant subsystem during
  the audit.
- Settings persist across app restart.

## Output

- `agent/screenshots/m9-spectrogram-<n>.png` (or linked from a shared
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
