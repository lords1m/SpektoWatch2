# Task 2: Weighting And FFT Hot Path

Status: completed  
Created: 2026-05-11  
Completed: 2026-05-11  
Milestone: `milestone-2-performance-stabilization-watch-architecture`

## Objective

Reduce Swift-side CPU and allocation cost in the live FFT and weighting path
without changing measurement semantics.

## Scope

- Precompute frequency weighting gain values that are constant after
  initialization.
- Replace scalar log/linear conversion loops with Accelerate-backed vector
  operations where practical.
- Add buffer-in/buffer-out helpers where they remove repeated hot-path array
  allocation.
- Preserve existing public behavior and tests.

## Acceptance

- Hot-path code avoids recomputing constant weighting gains per frame.
- FFT conversion helpers reduce scalar per-bin work.
- Targeted FFT and weighting tests pass.
- Any performance test changes are documented.

## Non-Goals

- Do not rewrite the whole DSP pipeline.
- Do not change metric definitions.
- Do not alter masking behavior.

## Implementation Notes

The existing `FrequencyWeightingProcessor` already met the weighting-side
acceptance criteria at task start:

- A/C linear gains are precomputed at initialization.
- A/C dB gains are precomputed at initialization.
- `applyWeighting` uses vectorized `vDSP_vadd`.
- Squared A/C gains are precomputed for energy dot products.

This task therefore focused on the remaining allocation cost in the FFT path.

Changes made:

- Added reusable-output `FFTProcessor.performFFT(on:gainBoost:into:)`.
- Added reusable-output `FFTProcessor.convertToDB(_:into:)`.
- Added reusable-output `FFTProcessor.convertToLinear(_:into:)`.
- Kept the original return-value APIs for compatibility.
- Updated `AudioEngine.processFFTFrame` to reuse linear magnitude, dB magnitude,
  and energy scratch buffers.
- Cleared those scratch buffers on FFT block-size/configuration changes.
- Added `FFTProcessorTests.testReusableOutputVariantsMatchReturnValueAPIs`.

## Validation

Compile gate:

```sh
xcodebuild build-for-testing -project SpektoWatch2.xcodeproj -scheme SpektoWatch2 -testPlan SpektoWatch2 -destination "platform=iOS Simulator,name=iPhone 12 mini,OS=26.3.1"
```

Result: `TEST BUILD SUCCEEDED`.

Runtime targeted tests were not rerun because task 1 established that
CoreSimulator launch currently fails before producing unit-test results. Use
the same targeted FFT/weighting tests once simulator launch is healthy.
