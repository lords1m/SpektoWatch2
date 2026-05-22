# Task 1: Quick wins (R6 + R7 + R8 + R9)

Status: pending
Created: 2026-05-21
Milestone: `milestone-14-performance-centralization`
Source: `2026-05-21-performance-centralization-audit.md`
(items R6, R7, R8, R9)

## Goal

Four cheap perf/clean-up fixes bundled into one task. None
changes behavior; all reduce per-frame work or duplicate state.
Foundation for the bigger tasks that follow.

## Scope

### R8 — Calibration snapshot per frame

`AudioEngine.processFFTFrame` reads `calibrationOffset` twice
(lines ~1332, ~1404). Snapshot once at the top of the function:
```swift
let cal = calibrationOffset
```
Use `cal` for both the `vDSP_vsadd` and the
`pow(10, cal / 10.0)` energy factor.

### R9 — Bandstop filter snapshot cache

`SpectrogramProcessor.applyBandstopFilters` calls
`bandstopFilterManager.snapshotEnabledFilters()` every frame.
Add a cached `enabledFiltersSnapshot` + invalidation hook on
filter mutation. Effective only when ≥1 filter is configured.

### R7 — Delete `currentOctaveBands` alias

`LiveAcousticState.currentOctaveBands` is an alias of one of
`currentOctaveBandsZ/A/C` picked by `frequencyWeighting`. Per
the audit, no live consumer reads the alias — `FrequencySpectrumWidget`
reads the weighted variants explicitly. Drop the alias, its
forwarder on AudioEngine, and the writer in `updateUI`.

### R6 — Consolidate `currentSpectrum`

`live.currentSpectrum` carries the same data as
`live.currentSpectrogramData?.magnitudes` (for the active
weighting). Audit every consumer; migrate to the `data.magnitudes`
accessor; drop the standalone `currentSpectrum` field + its
publish + its forwarder.

## Acceptance

- AudioEngine.swift LOC drops by ~20 (forwarders gone).
- LiveAcousticState publishes 10 properties instead of 12.
- iOS + watchOS builds green.
- Zero behavior change. Existing widgets render identically.
