# Task 9-spektralanalyse-lab: Spektralanalyse-Labor

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-9-widget-audit`

## Code-side pre-pass (2026-05-21)

Method step 1 completed. Hardware steps 2-5 still pending.

### Surface: widget purpose

**Not a passive readout widget.** This is a **control panel** dashboard
widget that lets the user mutate app-global FFT settings (block size,
window function, overlap) live. It also visualizes the consequences
(resolution badges, window shape chart, Heisenberg time-frequency
uncertainty plot).

### Surface: settings UI

**None.** `WidgetSettingsView` has no `.spektralanalyseLab` arm. Cog
falls to "Keine Einstellungen verfügbar" placeholder.

### Surface: render path

`SpektoWatch2/SpektralanalyseLaborWidget.swift` (417 lines):

- Takes `fftConfig: FFTConfiguration` (app-global) and
  `audioEngine: AudioEngine` directly. **No `settings: [String: String]`
  parameter** — unlike every other widget.
- Three tabs (`LabTab` enum): "Parameter", "Fenster", "Auflösung".
- **Parameter tab** (`ParametersTabView`): segmented Block-Size picker,
  WindowFunction Menu, Overlap Slider `0…75 step 25`, ResolutionBadges
  (Δf, Δt, Bins). `onChange` writes back to
  `audioEngine.setWindowFunction(_:)` / `setBlockSize(_:)`.
- **Fenster tab** (`WindowTabView`): WindowShapeChart + StatBadges
  (main-lobe width, sidelobe attenuation, coherent gain) + description
  + horizontal Quick-Selector chips.
- **Auflösung tab** (`ResolutionTabView`): HeisenbergChart +
  ResolutionRows.

### Findings (code-side only — no screenshots yet)

- ⚠ **Multiple instances share state** — two Spektralanalyse-Lab
  widgets on the same dashboard both read/write the same `fftConfig`.
  Changing block size in one immediately changes the other. Per-tab
  selection is per-instance (`@State`), but the underlying FFT
  config is global. Subtle.
- ⚠ **No settings sheet** — same "cog opens empty placeholder" pattern
  as ToneGenerator, LevelMeter, PhaseMeter. Hide the cog or add
  per-widget options (e.g. default-tab on appear).
- ⚠ **App-global mutation without warning** — every interaction
  changes the FFT pipeline for the whole app. A user editing dashboard
  layout could unintentionally pick a 256-sample block and degrade
  every other spectrogram/waterfall widget's resolution. Consider:
  - A "Lab" badge on the widget signalling "this affects all widgets".
  - Confirmation prompt for changes mid-recording.
- ✅ **Reset to defaults** — "Zurücksetzen" button added at the bottom
  of the Parameters tab; resets windowFunction → `.blackmanHarris`,
  blockSize → `.size2048`, overlapPercent → `75.0` and propagates to
  the audio engine. Landed 2026-05-28.
- ⚠ **Mid-recording mutation behaviour** — `audioEngine.setBlockSize(...)`
  mid-recording: does the FFT pipeline cleanly transition? Does the
  `.spekto` measurement file get a frame-size discontinuity? Critical
  for data-integrity claims. Hardware test required.
- ✅ **Overlap picker** — replaced `Slider(value:, in: 0...75, step: 25)`
  with a segmented `Picker` showing 0 % / 25 % / 50 % / 75 %. Binding
  snaps to nearest so the legacy 87.5 % default maps to 75 %. Landed
  2026-05-28.
- ✅ **Window selector duplication removed** — horizontal chip selector
  in the Window tab deleted; Parameter tab's Menu is the sole canonical
  control. Window tab is now a pure visualization surface. Landed
  2026-05-28.
- ✅ **87.5 % overlap legacy default** — `FFTConfiguration.overlapPercent`
  default and hop-size clamp changed from 87.5 → 75.0 (matches picker
  range 0/25/50/75). Persisted values > 75 % clamp down on load.
  Landed 2026-05-29.
- ⚠ **German strings hardcoded** — `LabTab.rawValue = "Parameter" /
  "Fenster" / "Auflösung"`. No `localized()`. If the app ever ships
  English, the tabs stay German.
- ⚠ **Tab labels tight** at 2×2 — three tabs × 14-pt icon + 9-pt
  label in `HStack(spacing: 0)`. At the M8 minimum `2×2 cell` (~270
  pt wide on iPhone 12 mini), each tab gets ~90 pt — fine in German
  but "Spektralanalyse" / "Resolution" English candidates could
  truncate.
- ⚠ **ScrollView inside the widget** — the body wraps content in a
  `ScrollView`. Combined with the widget's `2×2 … 3×4` size range
  and dashboard-level scrolling, you get nested scrollables. Verify
  on hardware that the gesture priority is correct.

### Pending (hardware)

- 📸 Screenshots per allowed size (`sizeRange(for: .spektralanalyseLab)`:
  `2×2 … 3×4`), all three tabs.
- Confirm mid-recording mutation behaviour with `.spekto` file open
  in `MeasurementDataReader`.
- Two-instance dashboard: drop two Lab widgets, confirm they
  reflect each other's changes immediately.
- Overlap slider step-25 vs continuous expectation.
- Nested-scroll gesture priority between widget's `ScrollView` and
  the dashboard `LazyVGrid`.

## Subject

- Widget type: `AudioWidgetType.lab` (verify exact case in
  `SpektoWatch2/WidgetConfiguration.swift`).
- Source: `SpektoWatch2/combined analyzer view`
- Settings exposed: full feature inventory

## Method

1. Read the widget source + its settings sheet. Note every public
   knob and every persisted setting key.
2. Launch on hardware (AGENT.md: local simulator is broken).
3. For every size in `WidgetConfiguration.sizeRange(for: .lab)`
   from min to max, capture a screenshot. Edit mode and view mode.
4. Cycle every settings combination. Capture before/after.
5. Stress: silence, clipped input, sample-rate change mid-stream,
   recording active vs inactive, dark mode, light mode.

## Specific checks

- inventory every control on the view; flag dead controls; check overlay rendering; layout at 2×2 → 3×4.
- Layout integrity at each allowed size.
- Touch-target accessibility (>= 44pt).
- Color contrast pass for the displayed metric text.
- No `Logger` errors / warnings on the relevant subsystem during
  the audit.
- Settings persist across app restart.

## Output

- `agent/screenshots/m9-lab-<n>.png` (or linked from a shared
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
