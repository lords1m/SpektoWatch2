# Task 4-frequency-display: Frequency Display (Frequenz-Spektrum)

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-9-widget-audit`

## Code-side pre-pass (2026-05-21)

Method step 1 completed. Hardware steps 2-5 still pending.

### Surface: settings UI

`SpektoWatch2/WidgetSettingsView.swift` lines 213-232, section
"Spektrum Einstellungen" (shared with `octaveBands` legacy type):

| UI control | Persists key | Default | Consumer |
|---|---|---|---|
| Frequenzbewertung (Picker A/C/Z) | `freqWeighting` | `"Z"` | ✅ `FrequencySpectrumWidget.weighting` (only when override toggle on) |
| Frequenzbänder (Picker Bark/Oktav/Terz) | `frequencyBands` | `WidgetSettings.defaultSpectrumBandMode` ("terz") | ✅ `FrequencySpectrumWidget.bandMode` (only when override toggle on) |

Plus override toggle (`useWidgetOverrides`).

### Surface: render path

`FrequencySpectrumWidget.body` (`SpektoWatch2/AudioWidgets.swift:20-64`)
→ `SpectrumBandChartView`:

- `bandMode` switches between Bark, Octave, ThirdOctave.
- `weighting` selects between `data.magnitudes(for:)` (FFT) and
  pre-weighted octave-band arrays from `audioEngine.currentOctaveBandsA/C/Z`.
- Y-axis fixed at 20…110 dB.
- Bar gap `3 pt` for octave, `1 pt` otherwise.
- Optional EMA smoothing on Leq with `leqAlpha = 0.02`.
- "Warte auf Audio..." placeholder when bands empty or all ≤ -100 dB.
- Debug diagnostics gated by env var `SPEKTO_DEBUG_WIDGET_SPECTRUM=1`.

### Findings (code-side only — no screenshots yet)

- ✅ Both settings are consumed (none dead).
- ⚠ **`bandMode` is locked to default when override is OFF.** Look at
  lines 31-36: without override the widget reads
  `WidgetSettings.defaultSpectrumBandMode` ("terz") regardless of any
  app-global. There is **no global app setting** for band mode (grep
  for `frequencyBands` confirms — only the per-widget key exists).
  Net effect: a user without override toggle on can never see Bark or
  Octave bands. Either:
  1. Make per-widget setting the only place this lives (drop the
     conditional override; band mode is always per-widget).
  2. Add a global app default that the override can fall back to.
- ⚠ **Octave-bands legacy type still shares this widget's settings
  section** (line 213: `widget.type == .frequencyDisplay || widget.type == .octaveBands`).
  Per `DashboardManager.normalizeWidgets`, legacy `.octaveBands`
  widgets are rewritten to `.frequencyDisplay` on load — but the
  settings sheet still has an `|| widget.type == .octaveBands` arm.
  Dead path after normalize-on-load runs. Safe to remove.
- ⚠ **Y-axis hardcoded 20…110 dB** — no per-widget min/max settings
  unlike the waterfall. With a quiet signal or after calibration, the
  bottom of the chart sits at 20 dB even if the actual floor is
  -60 dB SPL → empty space below the bars. Worth flagging for product:
  do we want a `spectrumMinDB`/`spectrumMaxDB` setting (mirrors waterfall)
  or is the hardcoded range deliberate?
- ⚠ **EMA `leqAlpha = 0.02`** is hardcoded. At 86 Hz update rate this
  is roughly a 580 ms time constant. Effectively a slow-Leq. If a user
  picks an "explicit" weighting (no per-frame display), they get an
  unexpected averaging behaviour. Document or expose.
- ⚠ **Debug-only env var `SPEKTO_DEBUG_WIDGET_SPECTRUM`** — would not
  ship to production users but worth confirming the diagnostics block
  is `#if DEBUG`-gated (it's only env-var-gated, so the code runs in
  release; harmless but unnecessary).

### Pending (hardware)

- 📸 Screenshots per allowed size (`sizeRange(for: .frequencyDisplay)`:
  `2×1 … 3×3`), edit + view mode, dark + light.
- 📸 Each `frequencyBands` × `freqWeighting` combination — 9 cells.
- Behaviour with a known reference tone (does the right bin/band
  light up at the expected dB?).
- "Warte auf Audio..." placeholder timing / layout.
- Side-by-side check against the waterfall using same weighting.

## Subject

- Widget type: `AudioWidgetType.display` (verify exact case in
  `SpektoWatch2/WidgetConfiguration.swift`).
- Source: `SpektoWatch2/AudioWidgets.swift`
- Settings exposed: band mode (Terz / Oktave / FFT)

## Method

1. Read the widget source + its settings sheet. Note every public
   knob and every persisted setting key.
2. Launch on hardware (AGENT.md: local simulator is broken).
3. For every size in `WidgetConfiguration.sizeRange(for: .display)`
   from min to max, capture a screenshot. Edit mode and view mode.
4. Cycle every settings combination. Capture before/after.
5. Stress: silence, clipped input, sample-rate change mid-stream,
   recording active vs inactive, dark mode, light mode.

## Specific checks

- bar heights vs reference signal; band-label readability at 2×1; smooth vs blocky transitions; behaviour at FFT-block-size change.
- Layout integrity at each allowed size.
- Touch-target accessibility (>= 44pt).
- Color contrast pass for the displayed metric text.
- No `Logger` errors / warnings on the relevant subsystem during
  the audit.
- Settings persist across app restart.

## Output

- `agent/screenshots/m9-display-<n>.png` (or linked from a shared
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
