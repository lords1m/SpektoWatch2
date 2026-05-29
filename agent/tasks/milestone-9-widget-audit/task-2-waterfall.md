# Task 2-waterfall: Waterfall

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-9-widget-audit`

## Code-side pre-pass (2026-05-21)

Method step 1 completed. Hardware steps 2-5 still pending.

### Surface: settings UI

`SpektoWatch2/WidgetSettingsView.swift` lines 121-141, section "Wasserfall Einstellungen":

| UI control | Persists key | Default | Consumer |
|---|---|---|---|
| Frequenzbewertung (Picker Z/A/C) | `freqWeighting` | `"Z"` | ✅ `WaterfallWidget.weighting` |
| Zeitscheiben (Picker 48/96/160) | `waterfallSlices` | `WidgetSettings.defaultWaterfallSliceCount` (96) | ✅ `WaterfallWidget.sliceCount` |
| Minimum-Stepper -140…-40 dB step 5 | `waterfallMinDB` | `WidgetSettings.defaultWaterfallMinDB` (-110) | ✅ `WaterfallWidget.minDB` |
| Maximum-Stepper -20…120 dB step 5 | `waterfallMaxDB` | `WidgetSettings.defaultWaterfallMaxDB` (20) | ✅ `WaterfallWidget.maxDB` |

Plus override toggle (`useWidgetOverrides`).

### Surface: render path

`WaterfallWidget.body` (`SpektoWatch2/WaterfallView.swift:189-258`):
- Subscribes to `audioEngine.spectrogramSubject` (Combine).
- Per-update: `appendFrame` collects magnitudes for current weighting,
  trims history to `max(24, min(240, sliceCount * 2))` frames.
- `rebuildDataSet` is throttled to 0.12 s (= ~8 Hz). Builds via
  `WaterfallDataBuilder.build` with `targetSliceCount = sliceCount`,
  `targetFrequencyCount = 128`.
- Time span shown is implicit: `duration = max(hopDuration ×
  history.count, audioEngine.recordingDuration)`, where `hopDuration
  = scrollSpeed / sampleRate`.

### Findings (code-side only — no screenshots yet)

- ✅ No dead settings — all four settings are consumed by the widget.
- ✅ Override toggle pattern consistent with spectrogram + level-history.
- ✅ **Cross-validation `minDB < maxDB`** — `resolvedSettings` now
  clamps via `min(lo, hi-5)` / `max(hi, lo+5)`, matching the pattern
  in `SpectrumBandChartView`. Landed 2026-05-28. `WaterfallDataBuilder`
  always receives a valid range; the `max(1, …)` guard at line 531 is
  now belt-and-suspenders only.
- ⚠ **Throttle constant 0.12 s** (~8 Hz redraw) vs. spectrogram's 60
  fps. Visually different cadence when shown side by side; not
  necessarily wrong (waterfall slice density is the real time
  resolution, not the redraw rate), but worth a screenshot pair to
  confirm the two widgets feel coherent.
- ⚠ **`history.removeFirst(...)` is O(n)** on an Array. With
  `maxHistoryFrames = sliceCount × 2` capped at 240, n stays small,
  but every FFT callback (~86 Hz) does this. Move to a ring buffer
  or use `Shared/RingBuffer.swift` (added in M6 task-7) if profiling
  shows time on `removeFirst`.
- ⚠ **`maxHistoryFrames = max(24, min(240, sliceCount * 2))`** is
  effectively `2 × sliceCount` for the picker values (48 → 96, 96 →
  192, 160 → 240). The cap at 240 hits the 160-slice option exactly
  — slightly arbitrary. Document or pin to a deliberate seconds-of-history.

### Pending (hardware)

- 📸 Screenshots per allowed size (`sizeRange(for: .waterfall)`:
  `2×2 … 3×4`), edit + view mode, dark + light.
- 📸 Each sliceCount × each weighting combination.
- Stepper edge case: `minDB > maxDB` — does it render anything sane?
- Behaviour during silence (does the widget go uniformly bright at
  `minDB`?) and clipped input.
- Side-by-side with spectrogram for cadence consistency check.

## Subject

- Widget type: `AudioWidgetType.waterfall` (verify exact case in
  `SpektoWatch2/WidgetConfiguration.swift`).
- Source: `SpektoWatch2/AudioWidgets.swift`
- Settings exposed: slice count, minDB / maxDB

## Method

1. Read the widget source + its settings sheet. Note every public
   knob and every persisted setting key.
2. Launch on hardware (AGENT.md: local simulator is broken).
3. For every size in `WidgetConfiguration.sizeRange(for: .waterfall)`
   from min to max, capture a screenshot. Edit mode and view mode.
4. Cycle every settings combination. Capture before/after.
5. Stress: silence, clipped input, sample-rate change mid-stream,
   recording active vs inactive, dark mode, light mode.

## Specific checks

- slice scroll direction stable; dB range UX (manual vs auto); rendering at 2×2…3×4; transition when slice count changes mid-stream.
- Layout integrity at each allowed size.
- Touch-target accessibility (>= 44pt).
- Color contrast pass for the displayed metric text.
- No `Logger` errors / warnings on the relevant subsystem during
  the audit.
- Settings persist across app restart.

## Output

- `agent/screenshots/m9-waterfall-<n>.png` (or linked from a shared
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
