# Task 1: Quick wins (R6 + R7 + R8 + R9)

Status: completed
Created: 2026-05-21
Completed: 2026-05-25
Milestone: `milestone-14-performance-centralization`
Source: `2026-05-21-performance-centralization-audit.md`
(items R6, R7, R8, R9)

## Goal

Four cheap perf/clean-up fixes bundled into one task. None
changes behavior; all reduce per-frame work or duplicate state.
Foundation for the bigger tasks that follow.

## Scope

### R8 — Calibration snapshot per frame ✅

Added `let cal = calibrationOffset` at the top of
`processFFTFrame`. All four downstream reads (visual DCT
`calibrationOffset:` arg, `var calOffset` for `vDSP_vsadd`, the
energy `calibrationFactor = pow(10, cal/10)`, and the LCpeak
`+ calibrationOffset`) now use `cal` — one read of the
`@Published` property per frame on the audio render thread.

### R9 — Bandstop filter snapshot cache ✅ (already implemented)

`BandstopFilterManager` already maintained `enabledFiltersSnapshot`
(an `nonisolated(unsafe)` var guarded by `snapshotLock`) with a
`didSet { updateSnapshot() }` invalidation hook. `snapshotEnabledFilters()`
already reads from the cached snapshot under the lock. No change
needed.

### R7 — Delete `currentOctaveBands` alias ✅

- Deleted `@Published var currentOctaveBands` from `LiveAcousticState`.
- Deleted `var currentOctaveBands` forwarder from `AudioEngine`.
- Removed `self.currentOctaveBands = ...` write in both
  `ingestWearableSpectrogramData` and the `DispatchQueue.main.async`
  updateUI block.
- Removed the dead `displayOctaveBands` selector block (5 LOC) that
  was only ever passed as the now-deleted `octaveBands:` parameter.
- Removed `octaveBands:` and `spectrum:` parameters from `updateUI()`
  signature and call site (now only the three per-weighting variants
  are passed).
- `OctaveBandWidget.body` now reads the weighted variant directly via
  a private `weightedOctaveBands` computed property.

### R6 — Consolidate `currentSpectrum` ✅

- Deleted `@Published var currentSpectrum` from `LiveAcousticState`.
- Deleted `var currentSpectrum` forwarder from `AudioEngine`.
- Removed `self.currentSpectrum = ...` writes in both
  `ingestWearableSpectrogramData` and the `updateUI` block.
- `FrequencySpectrumWidget.weightedSpectrum` simplified to
  `audioEngine.currentSpectrogramData?.magnitudes(for: weighting) ?? []`.
- `OctaveBandWidget.body` fallback likewise uses `[] ` (the startup
  case where no FFT frame has arrived yet).

## Net changes

- `LiveAcousticState` publishes **10** properties (was 12).
- `AudioEngine` has **2** fewer computed forwarders.
- `updateUI()` takes **2** fewer parameters.
- `processFFTFrame` reads `calibrationOffset` **once** (was 4 times).
- **~30 LOC removed** across `AudioEngine.swift`, `LiveAcousticState.swift`,
  `AudioWidgets.swift`.

## Validation

- `xcodebuild -scheme SpektoWatch2 -destination 'generic/platform=iOS
  Simulator' build` → `** BUILD SUCCEEDED **`.
- Zero behavior change; `OctaveBandWidget` renders the same bands as
  before (now reads the weighted per-weighting array directly).
- R9 already implemented; verified by reading
  `BandstopFilterManager.swift` lines 8-17 and `snapshotEnabledFilters`.
