# Task 6-phase-meter: Phase Meter

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-9-widget-audit`

## Code-side pre-pass (2026-05-21)

Method step 1 completed. Hardware steps 2-5 still pending.

### Surface: settings UI

**None.** Like the level meter, `WidgetSettingsView` has no `.phaseMeter`
arm and `supportsOverrideToggle` excludes it. Settings sheet is empty.

### Surface: render path

`PhaseMeterWidget` (`SpektoWatch2/AudioWidgets.swift:469-608`):

- Takes `audioEngine` only — no settings parameter (`WidgetCardView.swift:67`:
  `PhaseMeterWidget(audioEngine: audioEngine)`).
- Branches on `audioEngine.isStereoActive`:
  - Stereo → correlation bar (gradient red/yellow/green, needle position
    derived from `currentStereoPhase ∈ [-1, +1]`) + phase ellipse
    goniometer (Canvas, ellipse scale via `sqrt((1±phase)/2)`).
  - Mono → placeholder card "Kein Stereo-Signal / Stereo-Mikrofon in den
    Einstellungen aktivieren".
- Indicator color thresholds (`indicatorColor(phase:)`):
  - `< -0.1` → red
  - `-0.1 … 0.3` → yellow
  - `> 0.3` → green
- Data source: Pearson correlation in `AudioEngine.swift:1149-1167` —
  `dotProd / sqrt(sumSqL × sumSqR + 1e-9)`. For mono inputs (single
  channel), phase is forced to `1.0`.

### Findings — widget deactivated (M12 product decision, 2026-05-28 audit)

All pre-pass findings below are **N/A**: `.phaseMeter` was deactivated
as a product decision in M12. `WidgetConfiguration.allCases` excludes it
from the picker, and `DashboardManager.normalizeWidgets` removes any
existing `.phaseMeter` instances on load. The widget code is retained
for backward-compatible decoding only.

- ✅ (N/A) **Empty settings sheet** — widget not user-accessible; moot.
- ✅ (N/A) **Asymmetric indicator-color thresholds** — moot.
- ✅ (N/A) **Indicator color / gradient mismatch** — moot.
- ✅ (N/A) **Ellipse orientation convention** — moot.
- ✅ (N/A) **Mono fallback hint** — moot.
- ✅ (N/A) **`isStereoActive` reset semantics** — moot.
- ✅ (N/A) **Fixed 110 pt ellipse width** — moot.

### Pending (hardware)

None — widget deactivated; no hardware verification required.

## Subject

- Widget type: `AudioWidgetType.meter` (verify exact case in
  `SpektoWatch2/WidgetConfiguration.swift`).
- Source: `SpektoWatch2/AudioWidgets.swift`
- Settings exposed: stereo handling

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

- mono-input behaviour (does it sensibly degrade?); stereo correlation correctness vs known signal; labels at 1×1.
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
