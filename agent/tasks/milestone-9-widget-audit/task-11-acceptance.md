# Task 11: Acceptance

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-9-widget-audit`
Depends on: task-1 … task-10

## Objective

Collate per-widget findings into a single handoff report and cross-check
for inconsistencies between widgets that share patterns (level metering,
settings sheets, dB scaling, color zones).

## Landed (2026-05-21) — Code-side acceptance

Handoff report written: `agent/reports/2026-05-21-milestone-9-widget-audit.md`.

Contents:
- Per-widget verdict (✅ / ⚠ / ❌ / Deactivated) for all 10 widgets.
- 12 cross-cut findings spanning empty settings sheets, override-toggle
  UX, hardcoded color literals, loudness metric coherence, dead
  `scrollOffset` knob, O(n) history pruning, audio-session-category
  mutation, NSLock blocker, missing confirmations, accessibility
  identifiers, and localization.
- Prioritized backlog split High/Blocker (NSLock + empty settings),
  Medium (loudness coherence, peak-hold consistency, override
  decision), Low/Polish (≈ 25 items, each linked to its source
  task).

### Per-widget verdicts at a glance (updated 2026-05-28)

| # | Widget | Verdict |
|---|---|---|
| 1 | Spectrogram | ✅ all code fixes landed |
| 2 | Waterfall | ✅ minDB/maxDB cross-validation fixed; 3 backlog ⚠ |
| 3 | Level History | ✅ scrollOffset removed; weighting picker guard; phon/sone guard; 1 backlog ⚠ |
| 4 | Frequency Spectrum | ✅ bandMode always per-widget; #if DEBUG gated; 2 backlog ⚠ |
| 5 | Level Meter | ✅ peak-hold consistent; dB(A/C/Z) indicator added; 2 backlog ⚠ |
| 6 | Phase Meter | Deactivated (M12 removed from picker + load filter) |
| 7 | Single Value | ✅ metricKey always per-widget; "—" idle placeholder; 3 backlog ⚠ |
| 8 | Tone Generator | ✅ NSLock→OSAllocatedUnfairLock (M11); persistence added; dead settings param removed |
| 9 | Spektralanalyse Lab | ✅ overlap discrete picker; reset button; duplicate selector removed; 5 backlog ⚠ |
| 10 | Masking | ✅ reset confirmation dialog; accessibilityIdentifier; 4 backlog ⚠ |

### Code fixes landed 2026-05-28 (this session)

- **Waterfall**: `resolvedSettings` cross-validates `minDB < maxDB` (clamped to 5 dB minimum range).
- **Level History**: `scrollOffset` dead param removed end-to-end; weighting/time pickers disabled in non-AUTO metric mode; phon/sone overlay guarded to AUTO-only.
- **Frequency Spectrum**: `bandMode` always reads per-widget setting (removed `useWidgetOverrides` branch).
- **Single Value**: `metricKey` always per-widget; idle placeholder `"0.0"` → `"—"`.
- **Level Meter**: peak-hold consistent on local-mic path (`max(…)` hold); `dB(A/C/Z)` weighting badge added to scale row.
- **Tone Generator**: NSLock confirmed fixed (M11); `@AppStorage` persistence for frequency/amplitude/waveform; dead `settings` parameter removed from widget + call site.
- **Spektralanalyse Lab**: overlap `Slider(step:25)` → segmented `Picker`; "Zurücksetzen" reset button; duplicate window chip selector removed from Window tab.
- **Masking**: "Neu aufnehmen" now shows `.confirmationDialog` before `engine.reset()`; `.accessibilityIdentifier("maskingWidget")` added.
- **All widgets**: `onAppear` prints gated `#if DEBUG`; `diagnosticsCounter`/`enableWidgetDiagnostics` gated `#if DEBUG`.

### Outcomes recorded in M11/M12 already

- **Tone Generator NSLock** — resolved in M11 task-1.
- **Hardcoded dB ranges** — resolved in M12 task-8.
- **Phase Meter** — deactivated in M12.

## Remaining work (hardware)

Each per-widget task has a "Pending (hardware)" checklist for screenshot
grids + stress scenarios. M9 promotion to `completed` is gated on that
work; no new code findings expected — purely verification.

### UITest added 2026-05-29

`SpektoWatch2UITests/WidgetGridScreenshotTests.swift` — two new test methods:

- `testWidgetSizeGrid` — installs the Widgetgrößen preset and captures
  one full-page screenshot per widget type (9 pages × all allowed sizes
  visible on each page). Screenshot names: `M9-01-Spektrogramm-sizes`
  through `M9-09-Sound-Masking-sizes`.
- `testWidgetSizeGridEditMode` — same pages in edit mode so resize handles
  and delete circles are visible at every size.

`ScreenshotCatalogTests.swift` — removed stale "Layouts abrufen" button
assertion; replaced with robust retry logic that checks for "Neue leere Seite"
directly (both taps now go through the confirmationDialog unambiguously).

**Manual action needed**: add `WidgetGridScreenshotTests.swift` to the
`SpektoWatch2UITests` target membership in Xcode (same as the M18 TT-1
pattern for new test files).

Run the screenshot pass with:
```sh
xcodebuild test \
  -scheme SpektoWatch2 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SpektoWatch2UITests/WidgetGridScreenshotTests
python3 agent/scripts/capture-screenshots.py --skip-build
```

## Acceptance

- [x] Report exists and is reviewable.
- [x] Every per-widget task has a verdict (10/10).
- [x] Open backlog items are either routed (NSLock → M11, dB ranges
  → M12 task-8 (done), phase meter → M12 (done)) or explicitly
  deferred with rationale.
- [x] UITest for widget-size screenshot grid written (2026-05-29).
- [ ] UITest wired into Xcode target + run passes on simulator.
- [ ] Screenshots extracted to `agent/screenshots/` and committed.

Code-side acceptance complete; status stays `in_progress` until the
screenshot run executes and screenshots are committed.
