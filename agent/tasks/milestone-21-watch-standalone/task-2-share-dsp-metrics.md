# Task 2: Share DSP/Metrics to the Watch Target

Status: in_progress
Created: 2026-05-30
Milestone: `milestone-21-watch-standalone`

## Goal

Compute correct, time-integrated acoustic metrics on the watch — real LAeq and
LCpeak — instead of the current placeholder where both `LAF` and `LAeq` are
just the instantaneous broadband level.

## Current gap

`AcousticMetricsCalculator`, `MeasurementDataWriter`, and
`MeasurementDataFormat` live in the iOS-only `SpektoWatch2/` target and are not
compiled into the watch. `WatchAudioEngine` sets
`levels: ["LAF": levelSPL, "LAeq": levelSPL]`.

## Scope

- Move the metrics-calculation subset (`AcousticMetricsCalculator` + the parts
  of `MeasurementDataFormat` it needs) into `Shared/` (or add watch target
  membership) so both platforms use one implementation. Keep iOS behavior
  unchanged.
- Replace the watch's placeholder `levels` with real time-integrated LAeq and a
  true LCpeak from the calculator.
- Account for the watch's reduced FFT config (document the config used).

## Acceptance

- Watch LAeq/LCpeak track the phone within ±1.0 dB on the same reference
  signal (document the achieved delta) — verified in [[task-6-acceptance]].
- No regression to the iOS metrics pipeline (existing parity tests still pass).

## Notes

Prefer sharing over duplication. If full sharing is too heavy, share the
calculator and keep platform-specific thin adapters. Coordinate the data format
with [[task-3-local-store]] (the `.swr` writer) so the on-watch sidecar matches
what the phone ingests in [[task-5-sync-back]].

## Progress (2026-05-30)

Code-side complete; ±1.0 dB hardware verification deferred to [[task-6-acceptance]].

- `git mv`'d `AcousticMetricsCalculator.swift` (from `SpektoWatch2/Managers/`)
  and `FrequencyWeightingProcessor.swift` (from `SpektoWatch2/Processing/`) into
  `Shared/`. Both targets include the `Shared/` sync group, so they now compile
  into iOS and the watch from a single source — no pbxproj edits, no duplication.
- Verified each shared symbol (`MetricsResult`, `TimeWeighting`,
  `AcousticMetricsCalculator`, `FrequencyWeighting`, `FrequencyWeightingProcessor`)
  is defined exactly once; the watch had no competing definition.
- `WatchAudioEngine` now computes real metrics instead of the placeholder:
  - `performFFT` captures linear magnitudes (memcpy into a preallocated buffer)
    before the dB conversion.
  - `processAudioBuffer` derives Z/A/C band energy via `vDSP_vsq` + `vDSP_sve`
    (Z) and `vDSP_dotpr` against the processor's squared weighting gains (A, C),
    applies the calibration offset in the energy domain
    (`pow(10, watchMicCalibrationOffset/10)`), computes LCpeak via
    `vDSP_vmul`(C gains) + `vDSP_maxv`, then feeds them to
    `metricsCalculator.updateMetrics(...)` to get time-integrated `levels`.
  - `SpectrogramData` now carries the real `levels` dictionary (LAF/LAeq/LCpeak),
    not `["LAF": levelSPL, "LAeq": levelSPL]`.
- Watch FFT config: `fftSize: 2048`, `sampleRate: 44100`
  (`FrequencyWeightingProcessor(fftSize: 2048, sampleRate: 44100)`), matching the
  watch audio engine. Reduced relative to the phone's lab config; documented here.
- Builds: watch scheme **BUILD SUCCEEDED**; iOS scheme **BUILD SUCCEEDED**
  (run sequentially — shared DerivedData rejects concurrent builds).

Remaining: on-device ±1.0 dB parity check against the phone on a shared
reference signal, tracked in [[task-6-acceptance]].
