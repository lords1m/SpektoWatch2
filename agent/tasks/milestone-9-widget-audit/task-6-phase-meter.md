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

### Findings (code-side only — no screenshots yet)

- ⚠ **Empty settings sheet** (same as level meter) — no per-widget UI,
  no override toggle, but the cog icon still opens an empty form.
  Hide the cog for `.phaseMeter` or add settings (e.g. orientation:
  bar+ellipse / bar-only / ellipse-only).
- ⚠ **Asymmetric indicator-color thresholds** — green starts at `> 0.3`
  while red starts at `< -0.1`. There's a wide yellow band from -0.1
  to 0.3 (mostly positive territory). Conventionally a phase meter
  treats `phase ≈ 0` as "uncorrelated, marginal" and `phase > ~0.6`
  as "mono-compatible". The current thresholds give green to anything
  > 0.3 which is fairly loose. Worth a product decision.
- ⚠ **Indicator color does not match the gradient background** — the
  bar fill is a red→yellow→green LinearGradient at 0.3 opacity, so
  `phase = 0` lands in yellow (the midpoint) but the needle would be
  yellow there too — fine. But `phase = 0.4` shows a green needle on
  a still-yellowish background — visually mismatched.
- ⚠ **Ellipse `scaleX = sqrt((1-phase)/2)` / `scaleY = sqrt((1+phase)/2)`**
  — math is correct (encodes 2-channel Lissajous correlation), but
  worth confirming on hardware that the goniometer rotates as
  expected (the 45° reference lines suggest a real-goniometer-style
  presentation, but the ellipse is axis-aligned, not rotated 45°).
  Either the labels should drop the L/R axis lines, or the ellipse
  should be rotated.
- ⚠ **Mono fallback hint "Stereo-Mikrofon in den Einstellungen aktivieren"**
  — verify this links somewhere or at least matches the actual menu
  path. Cold dead end if the setting moved.
- ⚠ **`isStereoActive` reset semantics** — `isStereoActive = channels > 1`
  is updated on every audio callback. If the engine ever provides
  N=1 then N=2 within one callback batch, the widget flips back and
  forth. Probably fine in practice, but the mono → stereo transition
  is unanimated (instant view swap) which may flicker.
- ⚠ **Fixed 110 pt ellipse width** in the HStack — at the small allowed
  size (`1×1` = ~140 pt wide cell on iPhone 12 mini per M8 grid),
  the ellipse takes 78 % of the row, leaving the correlation bar
  squished. Verify on smallest allowed size.

### Pending (hardware)

- 📸 Screenshots per allowed size (`sizeRange(for: .phaseMeter)`:
  `1×1 … 2×2`).
- Inject a known stereo signal: pure mono (phase=+1), polarity-flipped
  (phase=-1), random noise pair (phase~0). Confirm needle + ellipse
  + indicator color all match.
- Verify mono fallback when only one input channel exists.
- Verify ellipse rotation convention against a recognized goniometer
  (e.g. a TV broadcast vectorscope or a known DAW's phase scope).

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
