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
- ✅ **`bandMode` always uses per-widget setting** (`AudioWidgets.swift`):
  The `useWidgetOverrides` conditional branch removed. There is no
  app-global band mode to fall back to, so the per-widget `frequencyBands`
  setting (default: "terz") is always the source of truth. Users can now
  select Bark or Octave bands even without the override toggle ON.
  Landed 2026-05-28.
- ✅ **Octave-bands dead arm removed** (`WidgetSettingsView.swift` line
  284): `|| widget.type == .octaveBands` deleted. `DashboardManager.normalizeWidgets`
  already rewrites `.octaveBands` → `.frequencyDisplay` on load so that
  branch was unreachable. Landed 2026-05-28.
- ✅ **Y-axis bounds are per-widget configurable** — finding outdated.
  `WidgetSettings.chartYMinDB/Max` (defaults 20/110 dB) were wired in
  M12 task-8; `FrequencySpectrumWidget` already passes them to
  `SpectrumBandChartView`; `yAxisBoundsSection` shown in settings sheet.
  No fix needed.
- ✅ **EMA `leqAlpha` finding outdated** — `leqBandAlpha = 0.02` was
  moved to `AcousticMetricsCalculator` in M14 task-3; `SpectrumBandChartView`
  now receives pre-computed `leqThirds` and owns no EMA. The constant
  remains in the metrics calculator (still hardcoded, but no longer a
  view-body concern). Routed to backlog if product wants it exposed.
- ✅ **`onAppear` print gated with `#if DEBUG`** (`AudioWidgets.swift`
  line 83): `print("[FrequencySpectrumWidget] View appeared...")` no
  longer fires in release builds. Landed 2026-05-28.
- ✅ **Diagnostics gated with `#if DEBUG`** (`AudioWidgets.swift`):
  `diagnosticsCounter`, `enableWidgetDiagnostics`, and the entire
  `logBandDiagnosticsIfNeeded` body are now inside `#if DEBUG` blocks.
  Release builds no longer allocate the `@State` counter, evaluate the
  `ProcessInfo` env lookup, or compile the print path. Landed 2026-05-28.

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
