# Task 5-level-meter: Level Meter (Pegel-Meter)

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-9-widget-audit`

## Code-side pre-pass (2026-05-21)

Method step 1 completed. Hardware steps 2-5 still pending.

### Surface: settings UI

**None.** Confirmed by grep — `WidgetSettingsView.swift` has no
`widget.type == .levelMeter` arm. `supportsOverrideToggle` also
excludes `.levelMeter`. Opening the settings sheet on a level meter
shows… an empty form.

### Surface: render path

`LevelMeterWidget` (`SpektoWatch2/AudioWidgets.swift:385-445`):

- Takes `audioEngine` only — no `settings: [String: String]` parameter
  (call site `WidgetCardView.swift:63`: `LevelMeterWidget(audioEngine: audioEngine)`).
- Reads `audioEngine.currentLevel` (broadband dB SPL).
- Reads `audioEngine.currentPeakLevel` for the small peak indicator line.
- Hardcoded `minDB = 30`, `maxDB = 100`.
- Color gradient hardcoded green → yellow → red (`.fill(LinearGradient(...))`).
- Scale labels hardcoded: `"30"`, `"65"`, `"100"`.

### Findings (code-side only — no screenshots yet)

- ✅ **Settings sheet finding outdated** — M12 task-8 added
  `yAxisBoundsSection` for `.levelMeter` in `WidgetSettingsView`; the
  widget accepts `settings: [String: String]` and reads
  `WidgetSettings.chartYMinDB/Max` (defaults 20/110 dB). Settings cog
  is actionable. No fix needed.
- ✅ **Peak-hold semantics now consistent** — local-mic path
  (`AudioEngine.swift` line ~1795) now uses
  `max(self.live.currentPeakLevel, peakLevel)` matching the watch
  path, so the peak indicator shows max-hold on both sources.
  Landed 2026-05-28.
- ⚠ **No peak-hold decay** — the held value resets only at session
  start. A real meter decays the peak indicator over ~1-2 s.
  Routed to backlog (requires a timer and would affect all
  LevelMeterWidget instances).
- ⚠ **Hardcoded color thresholds** — uniform green→yellow→red
  gradient regardless of calibrated range. WHO-style thresholds
  (≥ 85 dB → yellow, ≥ 100 dB → red) would be more informative.
  Routed to product backlog.
- ✅ **Weighting indicator added** — `LevelMeterWidget` now
  observes `audioEngine.frequencyWeighting` and displays a
  `dB(A)` / `dB(C)` / `dB(Z)` badge in the scale row. Updates
  live when the app-global weighting changes. Landed 2026-05-28.
- ✅ **Hardcoded range finding outdated** — range now reads from
  `yMinDB`/`yMaxDB` (defaults 20/110 dB via M12 task-8); scale labels
  also derived dynamically (`Int(yMinDB)`, midpoint, `Int(yMaxDB)`).
  No fix needed.
- ✅ **`onAppear` print gated with `#if DEBUG`** (`AudioWidgets.swift`):
  `print("[LevelMeterWidget] View appeared")` now inside `#if DEBUG`.
  Landed 2026-05-28 (alongside OctaveBandWidget same-file fix).
- ⚠ **`scrollSpeed` / `frequencyWeighting` invariance** — the meter
  doesn't expose either, but the value it shows depends on both
  app-globally. A second `LevelMeter` next to one configured for
  A-weighting would silently show the same number — there's no way
  to have two level meters with different weightings on the same
  dashboard.

### Pending (hardware)

- 📸 Screenshots per allowed size (`sizeRange(for: .levelMeter)`:
  `1×1 … 2×3`).
- Peak-hold decay characteristic: tap a clap, watch how fast the
  peak indicator falls. Compare local-mic vs watch-source paths.
- Color zone accessibility (deuteranopia: green/yellow/red gradient
  problematic; consider blue→green→red or pattern).
- Behaviour during silence — does the bar drop to 0 width? Is the
  empty bar visually clear?

## Subject

- Widget type: `AudioWidgetType.meter` (verify exact case in
  `SpektoWatch2/WidgetConfiguration.swift`).
- Source: `SpektoWatch2/AudioWidgets.swift`
- Settings exposed: metric, peak hold, color zones

## Method

1. Read the widget source + its settings sheet. Note every public
   knob and every persisted setting key.
2. Launch on hardware (AGENT.md: local simulator is broken).
3. For every size in `WidgetConfiguration.sizeRange(for: .meter)`
   from min to max, capture a screenshot. Edit mode and view mode.
4. Cycle every settings combination. Capture before/after.
5. Stress: silence, clipped input, sample-rate change mid-stream,
   recording active vs inactive, dark mode, light mode.

## Specific checks

- peak-hold timing; clipping indicator; color-zone accessibility (deuteranopia); 1×1…2×3 layouts.
- Layout integrity at each allowed size.
- Touch-target accessibility (>= 44pt).
- Color contrast pass for the displayed metric text.
- No `Logger` errors / warnings on the relevant subsystem during
  the audit.
- Settings persist across app restart.

## Output

- `agent/screenshots/m9-meter-<n>.png` (or linked from a shared
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
