# Task 3-level-history: Level History (Pegelverlauf)

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-9-widget-audit`

## Code-side pre-pass (2026-05-21)

Method step 1 completed. Hardware steps 2-5 still pending.

### Surface: settings UI

`SpektoWatch2/WidgetSettingsView.swift` lines 164-212, section "Pegelverlauf Einstellungen":

| UI control | Persists key | Default | Consumer |
|---|---|---|---|
| Messwert über Zeit (Picker, 15 options) | `historyMetric` | `WidgetSettings.defaultLevelHistoryMetric` ("AUTO") | ✅ `LevelHistoryWidget.selectedHistoryMetric` + `LevelHistoryView.selectedHistoryMetric` |
| Zeitbereich (Picker 1s/5s) | `timeSpan` | `WidgetSettings.defaultTimeSpanSeconds` (5) | ✅ `LevelHistoryView.timeSpan` (drives `resetBuffer()` column count) |
| Frequenzbewertung (Picker A/C/Z) | `freqWeighting` | `"A"` | ⚠ **Conditional** — only used when `historyMetric == "AUTO"`; ignored for any explicit metric (LAF/LCpeak/etc.) |
| Zeitbewertung (Picker Fast/Slow) | `timeWeighting` | `"Fast"` | ⚠ **Conditional** — same as above |

Plus override toggle (`useWidgetOverrides`).

### Surface: render path

Two layers:

- `LevelHistoryWidget.body` (`SpektoWatch2/LAFGraphWidget.swift`) wraps
  `LevelHistoryView` and adds overlays: a metric label (top-left) and
  a phon/sone readout (top-right) when `LoudnessCalculator` has a
  result.
- `LevelHistoryView` (`SpektoWatch2/LAFGraphView.swift`) holds the
  ring buffer + Canvas chart. Wall-clock-synced (2026-05-21 quickwins).

### Findings (code-side only — no screenshots yet)

- ✅ Wall-clock time-axis sync already landed (see
  `agent/reports/2026-05-21-spectrogram-quickwins.md`). Out of scope
  here.
- ✅ All four settings are consumed (none dead).
- ⚠ **Conditional `freqWeighting` + `timeWeighting`** — these pickers
  only have an effect when `historyMetric == "AUTO"`. When the user
  picks `LCpeak` (or any explicit metric), the two pickers are
  silently no-ops. Two ways to fix:
  1. Disable/hide the two pickers when `historyMetric ≠ "AUTO"`
     (clean UX, matches Apple HIG for conditional fields).
  2. Move them inside a disclosure group labelled "AUTO-Modus".
- ⚠ **Phon/Sone overlay uses `data.levels["LAF"]` regardless** of the
  user's selected `historyMetric` (`LAFGraphWidget.swift:106`). If
  the user sets `historyMetric = LCpeak`, the line graph shows
  C-weighted peak but the phon/sone readout silently keeps
  A-weighted fast loudness. Either:
  1. Drive loudness off `resolvedMetricKey` so they agree.
  2. Hide the phon/sone overlay when an explicit metric is selected.
- ⚠ **`scrollOffset: 0.0` constant pass-through** — same dead-knob
  pattern we removed from the spectrogram (M9 task-1). `LevelHistoryView`
  declares `var scrollOffset: Float` and uses it at line 118
  (`let offsetSamples = Int(scrollOffset * Float(count))`), but no
  caller ever passes a non-zero value. Worth checking if it's a
  playback scrubbing hook for `RecordingDetailView` or genuinely dead.
- ⚠ **Metric label string** (`metricLabel`) is just `resolvedMetricKey`
  — in AUTO mode that yields strings like `LAF` / `LAS` / `LZF` —
  same syntax as the picker's explicit options. A user who explicitly
  picks `LAF` and a user who's in AUTO with A+Fast see an identical
  overlay. Visually correct (the value is the same) but maybe worth a
  subtle "AUTO" hint when in auto mode.

### Pending (hardware)

- 📸 Screenshots per allowed size (`sizeRange(for: .levelHistory)`:
  `2×1 … 3×3`), edit + view mode, dark + light.
- 📸 Each `historyMetric` × `timeSpan` (1s / 5s) combination.
- Phon/Sone overlay layout at small sizes (2×1) — does it overlap the
  Y-axis labels?
- Behaviour during silence (does the line sit on -120 / off-screen?).
- Side-by-side with spectrogram: time-axis labels at `-5.0 / -4.0 /
  …` should now stay aligned thanks to the wall-clock fix. Verify
  empirically under load.

## Subject

- Widget type: `AudioWidgetType.history` (verify exact case in
  `SpektoWatch2/WidgetConfiguration.swift`).
- Source: `SpektoWatch2/AudioWidgets.swift`
- Settings exposed: displayed metric (LAF / LAS / LAeq / AUTO)

## Method

1. Read the widget source + its settings sheet. Note every public
   knob and every persisted setting key.
2. Launch on hardware (AGENT.md: local simulator is broken).
3. For every size in `WidgetConfiguration.sizeRange(for: .history)`
   from min to max, capture a screenshot. Edit mode and view mode.
4. Cycle every settings combination. Capture before/after.
5. Stress: silence, clipped input, sample-rate change mid-stream,
   recording active vs inactive, dark mode, light mode.

## Specific checks

- time axis legibility at 2×1…3×3; autorange behaviour; marker rendering; metric switch mid-record.
- Layout integrity at each allowed size.
- Touch-target accessibility (>= 44pt).
- Color contrast pass for the displayed metric text.
- No `Logger` errors / warnings on the relevant subsystem during
  the audit.
- Settings persist across app restart.

## Output

- `agent/screenshots/m9-history-<n>.png` (or linked from a shared
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
