# Task 4: Watch Faces & Complications

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-12-liquid-glass-redesign`
Depends on: task-1

## Goal

Implement the three watch faces and the five complication slot
layouts from `design_handoff_spektowatch_redesign/README.md § 6–7`.

## Subtasks

This task is broken into incremental slices so each `/acp.proceed`
turn ships a coherent deliverable.

- **4a. Pegelmesser face** — landed 2026-05-21.
- **4b. Spektrogramm face** — landed 2026-05-21.
- **4c. Tongenerator face** — pending. New file; mini sine wave
  with glow filter + PAUSE button + λ readout. Requires a watch-side
  tone source or a "static demo" mode.
- **4d. Complication chrome refresh** — pending. Update
  `WatchComplicationViews` for the 5 slot layouts.
- **4e. Modular 4-slot face** — pending. New face combining hero
  LAF + mini spectrogram strip + PEAK + Leq tiles.

## Landed (2026-05-21) — Subtask 4a

- New `SpektoWatch Watch App/WatchPegelmesserFace.swift`. Big LAF
  number (56pt SF Pro Display ultralight, phosphor green
  `oklch(0.84 0.18 145)` ≈ `Color(red: 0.45, green: 0.93, blue:
  0.55)`), dB(A) unit, peak bar (green→yellow→red gradient with
  30–110 dB range), MIN/MAX labels. Reads from
  `WatchAudioEngine.liveData`; ingest pulls LAF preferentially with
  LAeq → broadbandLevel fallbacks, peak from LCpeak → LAFmax → LAF.
- Added as first `TabView` page in `WatchContentView` so it surfaces
  on first launch.
- Phosphor color hardcoded for now — wiring watch-side to the iOS
  `AccentChoice` token requires shared design tokens across the
  App Group; deferred to a later sweep.

## Validation

- `xcodebuild -scheme "SpektoWatch Watch App" -destination 'generic/
  platform=watchOS Simulator' build` → `** BUILD SUCCEEDED **`.
- Local simulator broken; visual acceptance gated on hardware
  (task-6).

## Landed (2026-05-21) — Subtask 4b

- `WatchSpectrogramView` gained two redesign chrome strips:
  - **Top status pill**: pulsing phosphor LED + current `HH:mm`
    time (monospaced) + "STFT" cap on a translucent black capsule.
  - **Bottom STFT info pill**: small phosphor dot + "STFT · N"
    block-size label (derives N from `latestMagnitudesCount * 2`).
- Kernel rendering, axis labels, digital-crown zoom, and the
  existing bottom record control are untouched.
- New private `PulsingDot` view drives the LED animation; phosphor
  green hardcoded to match face 4a until App Group accent sharing
  lands.

## Acceptance status

- [x] Pegelmesser face implemented (subtask 4a).
- [x] Spektrogramm face implemented (subtask 4b).
- [ ] Tongenerator face (subtask 4c).
- [ ] Complication chrome refresh (subtask 4d).
- [ ] Modular 4-slot face (subtask 4e).
- [ ] Hardware visual pass (task-6).
