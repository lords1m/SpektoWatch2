# Performance Contract (Steps 6-7)

This contract links optimization work, regression gates, and release monitoring.

## Release Criteria

- All scenarios in `/Users/simeonbrandt/SpektoWatch/SpektoWatch2/PERFORMANCE_BUDGET.md` are within budget.
- Baseline traces and measured values are captured using `/Users/simeonbrandt/SpektoWatch/SpektoWatch2/BASELINE_PROFILING_MATRIX.md`.
- No audio XRuns/dropouts in `S2-S5`.
- Performance regression tests pass in `SpektoWatch2Tests`.

## Regression Guards In Code

- Signposts:
- `AudioTapCallback`, `FFTFrameProcessing`, `PerformFFT`
- `SpectrogramProcess`, `TextureUpload`, `MetalDraw`
- `WatchSendSpectrogram`, `WatchDidReceiveMessage`
- Automated guard tests:
- `FFTProcessorTests.testFFTRegressionBudget`
- `IntegrationTests.testSpectrogramProcessingRegressionBudget`

## Runtime Degradation Policy

When under pressure, degrade in this order:

1. Reduce watch send cadence and coalesce payloads
2. Reduce render cadence / increase column advance step
3. Reduce visual fidelity settings
4. Increase analysis hop size only as last resort

Audio continuity is always prioritized over visual smoothness.

## Ship Checklist

1. Run baseline scenarios `S1-S5` on reference devices.
2. Compare values to budget and mark pass/fail.
3. Run focused regression test suite.
4. Record measured values and attach trace bundle paths to release notes.

## Post-Release Monitoring

- Compare Xcode Organizer metrics release-over-release:
- CPU time
- hang rate / launch stability
- memory footprint trend
- Watch connectivity reliability
- Trigger investigation if any KPI worsens by >10% versus last accepted baseline.
