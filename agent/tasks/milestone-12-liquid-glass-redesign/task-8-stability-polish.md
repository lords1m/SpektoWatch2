# Task 8: Stability & Polish (in-flight fixes)

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-12-liquid-glass-redesign`
Depends on: task-2, task-3, task-4

## Goal

Capture the bug fixes and UX-polish improvements that landed during
M12 implementation and don't fit any single existing task. Tracked
here so M12 task-6 (acceptance) has a complete inventory.

## Items landed (2026-05-21)

### Audio correctness

- **Waterfall default range was dBFS, not dB SPL.** AudioEngine has
  converted magnitudes to calibrated dB SPL since M3, but the
  waterfall's default range was still `-110…20`, clipping all
  positive SPL readings into the floor. Defaults moved to `30…110`
  dB SPL; settings stepper bounds adjusted; migration drops any
  saved override with a negative min or non-positive max.
- **Spectrum band levels were mean, not sum.** Both
  `AudioEngine.computeDisplayThirdOctaveBands` and the
  `SpectrumBandChartView.thirdOctaveBands` fallback computed mean of
  linear bin powers per band, under-reporting by 10·log10(bins-in-
  band) — 5 dB on a low band up to ~22 dB on a high band. Switched
  to sum (the convention for 1/3-octave SPL).
- **Phase meter deactivated.** Removed from `AudioWidgetType.allCases`,
  filtered out by `DashboardManager.normalizeWidgets` on load.
  Enum case retained for backward-compatible decoding.

### Performance (iPhone 12 mini A14)

- `WidgetCardView` no longer observes `audioEngine` — meta readout
  moved into an isolated `CardMetaReader` child so card chrome
  doesn't re-render at 15 Hz.
- `LiquidGlassCard` switched `.regularMaterial` → `.thinMaterial`,
  collapsed two shadows into one conditional shadow.
- `DarkCanvasBackground` was later removed entirely (see seamless
  chrome below) — gradient stack was a per-card cost.

### UX polish

- **Settings tap regression** (gear button in edit mode): fixed by
  reordering overlays so the resize-strip overlay doesn't cover the
  corner buttons, and by adding `.highPriorityGesture(TapGesture)`
  so the parent `.onDrag` on each card can't swallow the tap.
- **Design tokens inlined in main settings.** Extracted reusable
  `DesignTweaksSections` view from `TweaksPanelView`; embedded
  directly in `SpectrogramSettingsView`. Header accent menu and the
  standalone TweaksPanelView sheet are gone — accent + theme +
  density + numerals + colormap all live under the gear icon.
- **Per-widget editable Y bounds.** New shared `chartYMinDB` /
  `chartYMaxDB` keys + accessor helpers in `WidgetSettings`;
  reusable `yAxisBoundsSection` in WidgetSettingsView; wired into
  levelHistory, frequencyDisplay/octaveBands, and levelMeter. Bounds
  pass through to LAFGraphView, SpectrumBandChartView, and the
  LevelMeter bar normalization. Spectrogram intentionally not
  touched (its Y is frequency, governed by sensitivity / Metal
  shader).
- **Waterfall labels moved out of the plot area.** Plot rect insets
  retuned; all labels now live in the top/bottom margins instead of
  overlaying the spectrogram trace.
- **Seamless inner canvas.** Dropped the dark inner-canvas fill;
  `InnerCanvas` modifier now uses the same `.thinMaterial` as the
  card chrome (later restructured so the kernel fills the card
  edge-to-edge — no perceived inner border). Widget cards have no
  visible border in live mode; edit mode still shows the accent
  border + glow.

## Deferred / out of scope

- Kernels with their own opaque background (Waterfall's `Color.black`,
  Metal-backed SpectrogramAdapter) still show that color as a block
  inside the otherwise-seamless card. Making them truly seamless
  requires editing the rendering kernels — deferred.
- Spectrogram Y-axis (frequency) editable bounds — needs separate
  plumbing through to the Metal shader.
- X-bounds (time-window) for chart widgets beyond the existing
  `timeSpan` pickers.

## Validation

- iOS build green (`xcodebuild -scheme SpektoWatch2 -destination
  'generic/platform=iOS Simulator' build` → `** BUILD SUCCEEDED **`).
- Watch build green for the changes affecting the watch target.
- Hardware visual pass for the polish/perf items is gated on task-6.

## Acceptance status

- [x] Audio-correctness fixes landed (waterfall range, spectrum
  band aggregation, phase meter deactivation).
- [x] Perf pass landed (chrome no longer re-renders at 15 Hz,
  thinner material, single shadow, flat canvas).
- [x] Design tokens inlined into main settings.
- [x] Per-widget editable Y bounds wired.
- [x] Waterfall labels relocated to margins.
- [x] Seamless inner canvas + non-edit borders removed.
- [ ] Hardware visual pass — gated on task-6.
