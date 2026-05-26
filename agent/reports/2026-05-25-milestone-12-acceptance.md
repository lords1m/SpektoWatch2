# Milestone 12: Liquid Glass Redesign — Acceptance Report

Date: 2026-05-25
Branch: `redesign/liquid-glass`
Status: Code-side complete. Hardware acceptance deferred.

---

## Per-task verdict

| Task | Name | Verdict |
|------|------|---------|
| task-1 | Chrome & Tokens (Phase 1) | ✅ Code complete |
| task-2 | Widget Card Headers | ✅ Code complete |
| task-3 | Preset Rail Wiring | ✅ Code complete |
| task-4 | Watch Faces & Complications | ✅ Code complete |
| task-5 | Density & Numerals Application | ✅ Code complete |
| task-6 | Acceptance | ⚠ Hardware deferred |
| task-7 | Review Follow-ups | ✅ Code complete |
| task-8 | Stability & Polish | ✅ Code complete |

---

## What landed (all on branch `redesign/liquid-glass`)

### Design system (task-1)
- `DesignTokens.swift`: `ThemeMode`, `AccentChoice` (phosphor/amber/cyan/magenta/paper),
  `Density` (compact/standard/airy), `NumeralStyle`, `Colormap`, all `@AppStorage`-backed.
- `TweaksPanelView.swift` + `DesignTweaksSections` embedded in `SpectrogramSettingsView`.
- Floating header pill, pulsing transport LED, `liquidGlassCard` widget chrome with
  accent edit border, jiggle, circular drag/delete handles.
- `Font.numerals(_:size:weight:)` helper — respects `NumeralStyle` token.

### Widget card headers (task-2)
- `WidgetCardView.cardHeader`: SF Symbol + uppercase mono title + right-aligned meta pill.
- Overlaid on top edge so dashboard grid height is unchanged.
- Hidden in edit mode; meta derives from `audioEngine.live` (LAF/LAeq per widget type).
- `CardMetaReader` isolated child — card chrome no longer re-renders at 15 Hz.

### Preset rail (task-3)
- `PresetCompositions.swift`: 11 presets mapped to concrete `WidgetConfiguration` arrays.
- `DashboardManager.applyPreset(id:)` replaces active layout non-destructively.
- `ModularDashboardView.activePresetID` promoted to `@AppStorage("dashboard.activePreset")`.
- Rail tap triggers `.easeInOut(0.25)` cross-fade.

### Watch faces & complications (task-4)
- **4a** `WatchPegelmesserFace.swift`: 56pt ultralight LAF + peak bar + MIN/MAX.
  Reset on `isRecording` rising edge + long-press haptic reset.
- **4b** `WatchSpectrogramView`: status pill (pulsing LED + HH:mm + STFT cap) + bottom STFT pill.
- **4c** `WatchTonegeneratorFace.swift`: frequency + animated sine + λ readout; tap cycles preset Hz.
- **4d** Complications reskinned: SF Mono + tracking-1.6 eyebrows + phosphor gauge tint.
  New `CornerComplicationView` for `accessoryCorner` + `LevelCornerWidget` in WidgetBundle.
- **4e** `WatchModularFace.swift`: 4-slot (hero LAF + 32pt spectrogram strip + PEAK + LEQ).
- Both TabView pages wired in `WatchContentView`.

### Density & numerals (task-5)
- `dashboardGrid` derives `padding`/`gap` from `Environment(\.designDensity)`:
  compact (10/8), standard (14/12), airy (18/16).
- `Font.numerals` wired into card meta pill, control-bar duration, `SingleValueWidget` hero.

### Review follow-ups (task-7) — all #2–#6 closed
- `metaText` filter tightened: `isFinite && v > -119.5` + `broadbandLevel > -119`.
- Edit button `accessibilityLabel` / `accessibilityHint` added.
- Jiggle phase switched to stable UUID-byte sum (consistent across cold launches).
- Pegelmesser min/max resets on recording start + long-press with haptic.
- Peak-bar range consolidated to `PeakBarRange` constant.
- #7, #8, #10, #11 explicitly deferred/won't-fix.

### Stability & polish (task-8)
- **Audio correctness**: waterfall defaults corrected to dB SPL (30–110); spectrum
  band aggregation switched from mean to sum (fixes 5–22 dB under-report per band);
  phase meter deactivated (enum retained for decode compatibility).
- **Performance**: `WidgetCardView` no longer observes `audioEngine` directly;
  `.thinMaterial` + single shadow; flat canvas.
- **UX**: settings tap regression fixed (overlay ordering + `.highPriorityGesture`);
  design tokens inlined into main settings; per-widget editable Y bounds
  (`chartYMinDB`/`chartYMaxDB`) wired into levelHistory, frequencyDisplay, levelMeter;
  waterfall labels relocated to margins; seamless inner canvas.

---

## Hardware acceptance checklist (all deferred)

1. Cold launch on device — Dark + Phosphor / Amber / Cyan / Magenta / Paper.
2. Light theme + each accent (canvas respects `CanvasMode`).
3. All 11 presets render at minimum widget sizes without overlap.
4. Edit mode: jiggle, accent border/glow, drag/delete circles, preset rail dim 35%.
5. Tweaks panel: every toggle persists across cold launch.
6. Transport bar: LED pulsing live/recording states.
7. Watch app: three faces selectable; three complication slots render correctly.
8. Regression: PDF export output correct; recording flow unchanged; masking unchanged.

---

## Open follow-ups

- **M13 task-4 Phase 2**: per-widget migration to `@ObservedObject live = audioEngine.live`
  (removes the `AudioEngine` forwarding bridge and reduces main-thread re-renders further).
- **M12 #10**: `single` preset 2×2 cluster — needs `gridPosition`-aware composer; deferred
  to the audit-driven grid refactor.
- **WatchTonegeneratorFace**: not wired to the iOS tone generator. Requires a
  WatchConnectivity protocol extension to relay tone state (out of M12 scope).
- **Complication sparkline / Leq / Lmax / Δ**: needs `WatchComplicationEntry` extension
  rippling into the WidgetKit provider + iOS write side.
- **Graphic Bezel complication**: face-layout API, out of WidgetKit scope.
- **Kernels with opaque backgrounds** (waterfall `Color.black`, Metal spectrogram):
  still show as blocks inside otherwise-seamless cards. Making truly seamless requires
  kernel changes — deferred.
