# Baseline Profiling Matrix (Step 2)

This runbook defines how to collect the baseline for SpektoWatch2 and compare it against `/Users/simeonbrandt/SpektoWatch/SpektoWatch2/PERFORMANCE_BUDGET.md`.

## Preconditions

- Build configuration: `Release`
- Device: physical iPhone (iPhone 12 class or newer), Apple Watch (Series 7 class or newer) for watch scenarios
- iPhone setup: brightness 50%, Low Power Mode off, battery > 40%, airplane mode off for watch tests, app freshly launched before each scenario

## Instruments Templates

- `Time Profiler`
- `Metal System Trace`
- `Allocations`
- `Energy Log`
- `Points of Interest` (for signpost intervals)

## Signpost Names To Track

- `AudioTapCallback`
- `FFTFrameProcessing`
- `PerformFFT`
- `SpectrogramProcess`
- `TextureUpload`
- `MetalDraw`
- `WatchSendSpectrogram`
- `WatchDidReceiveMessage`

## Scenarios and Durations

- `S1 Idle`: 3 minutes
- `S2 Live`: 5 minutes
- `S3 Live+Record`: 5 minutes
- `S4 Live+Watch`: 5 minutes
- `S5 Stress`: 10 minutes

## Capture Procedure (Per Scenario)

1. Connect iPhone and confirm `Release` build is installed.
2. Start Instruments with `Time Profiler + Points of Interest`.
3. Run the scenario for the full duration.
4. Save trace as `Baseline_<scenario>_TimeProfiler.trace`.
5. Repeat scenario for `Metal System Trace + Points of Interest`, `Allocations + Points of Interest`, and `Energy Log + Points of Interest`.
6. Save all traces under `/Users/simeonbrandt/SpektoWatch/SpektoWatch2/TestResults/PerformanceBaseline/`.

## Metrics To Record

- FPS average and frame-time p95/p99
- CPU total (app process)
- GPU utilization (render stage)
- Memory RSS steady-state and growth trend
- Audio dropouts / XRuns count
- End-to-end audio-to-visual latency p95 (from signposts and existing latency log)
- Watch update latency p95 and drop/loss estimate (`S4`)
- Battery change over scenario runtime
- Thermal state excursions

## Baseline Results Table

| Scenario | CPU % | GPU % | FPS Avg | Frame p95 ms | RSS MB | RSS Growth MB | XRuns | A/V Latency p95 ms | Watch Latency p95 ms | Battery Delta % | Thermal |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| S1 Idle |  |  |  |  |  |  |  |  | n/a |  |  |
| S2 Live |  |  |  |  |  |  |  |  | n/a |  |  |
| S3 Live+Record |  |  |  |  |  |  |  |  | n/a |  |  |
| S4 Live+Watch |  |  |  |  |  |  |  |  |  |  |  |
| S5 Stress |  |  |  |  |  |  |  |  |  |  |  |

## Pass/Fail Gate

- Compare each row against `/Users/simeonbrandt/SpektoWatch/SpektoWatch2/PERFORMANCE_BUDGET.md`.
- Mark scenario as `FAIL` if any audio dropout/XRun occurs, any metric exceeds budget by >10%, memory growth exceeds budget trend, or thermal state remains `.serious` for >60s or reaches `.critical`.

## Notes Template

- Device model:
- iOS / watchOS version:
- App commit/branch:
- Ambient conditions:
- Observed regressions:
- Follow-up actions:

## Calibration Invariants

- `gainBoost` in `AudioEngine` and all entries in
  `CalibrationProvider.deviceCalibrationOffsets` are co-dependent.
  They were measured together at gainBoost = 10.0 dB. Do not
  change one without re-deriving the other.
- Effective SPL = dBFS + calibrationOffset (device table value).
  gainBoost shifts the dBFS reading upward before this formula;
  it is baked into the table.
