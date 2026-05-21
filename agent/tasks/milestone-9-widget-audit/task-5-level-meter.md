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

- ⚠ **Empty settings sheet** — there is no per-widget settings UI for
  the level meter, and no override toggle. Tapping the cog icon
  in edit mode opens a sheet with nothing actionable. Either:
  1. Hide the settings cog for `.levelMeter` (clean — match the UI
     to what exists).
  2. Add settings that match the hardcoded values (min/max dB,
     color zones).
- ⚠ **Inconsistent peak-hold semantics** — `currentPeakLevel` is
  written two different ways depending on the audio source:
  - `AudioEngine.swift:1098` (watch-source path):
    `max(self.currentPeakLevel, data.broadbandLevel)` — implicit
    max-hold across frames.
  - `AudioEngine.swift:1564` (local-mic path): direct assignment
    `self.currentPeakLevel = peakLevel` — no hold.
  → On the local mic path, the small peak line on this widget drops
  back as soon as the peak falls. On a watch-source the indicator
  rises and stays. Confusing.
- ⚠ **No peak-hold decay** — even where max-hold exists (watch path),
  the held value only resets at session start (line 663 / 1060:
  `self.currentLevel = -120.0` resets). A real meter usually decays
  the peak indicator over ~1-2 s, or holds for ~1 s and then drops
  smoothly.
- ⚠ **Hardcoded color thresholds** — the gradient is uniform from
  30 → 100 dB. In acoustic engineering, color zones usually mark
  thresholds (≥ 85 dB → yellow, ≥ 100 dB → red). Worth surfacing as
  product question: do we want WHO-style thresholds or stay with
  the visual gradient?
- ⚠ **No weighting indicator** — the label is just `"L"`. The user
  has no way to tell from the widget whether they're seeing
  A-/C-/Z-weighted. The widget uses `audioEngine.currentLevel`
  which is the broadband level computed with the engine's current
  weighting.
- ⚠ **Hardcoded range [30, 100] dB SPL** misses both ends of the
  realistic measurement range (sub-30 dB ambient rooms exist; > 100
  dB events are exactly what the meter should show clearly). At least
  bump to [20, 120] to match the other widgets' Y-axis.
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
