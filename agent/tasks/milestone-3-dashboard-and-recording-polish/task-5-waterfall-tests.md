# Task 5: Waterfall Tests

Status: completed  
Created: 2026-05-12  
Completed: 2026-05-12  
Milestone: `milestone-3-dashboard-and-recording-polish`

## Objective

Add unit tests for `WaterfallDataBuilder` covering the key transform contracts.

## Context

- `WaterfallDataBuilder.swift` is a new, untracked file introduced during
  milestone 2. It has no tests.
- The builder takes `[[Float]]` history frames and produces a `WaterfallDataSet`
  with time-sliced, frequency-bucketed data.
- Tests belong in `SpektoWatch2Tests/`.

## Test Cases

Add `SpektoWatch2Tests/WaterfallDataBuilderTests.swift` with at minimum:

1. **`testEmptyHistoryProducesEmptyDataSet`** — `build(history: [], …)` returns
   an empty `WaterfallDataSet`.
2. **`testSliceCountDoesNotExceedTarget`** — output slice count ≤ `targetSliceCount`.
3. **`testFrequencyCountDoesNotExceedTarget`** — output frequency count ≤
   `targetFrequencyCount`.
4. **`testSingleFrameProducesOneSlice`** — one input frame produces exactly one
   output slice.
5. **`testMinMaxDBPreserved`** — `dataSet.minDB` and `dataSet.maxDB` match the
   values passed to `build`.
6. **`testSourceFrequenciesThirdOctave`** — when `binCount` equals
   `thirdOctaveCenters.count`, `sourceFrequencies` returns the third-octave
   center frequencies unchanged.
7. **`testSourceFrequenciesFullFFT`** — when `storedProviderHasFullFFT` is true,
   frequencies are linearly spaced up to Nyquist.

## Acceptance

- All listed tests compile.
- Tests pass under `xcodebuild test-without-building` if runtime is available;
  otherwise `TEST BUILD SUCCEEDED` is the gate.

## Non-Goals

- Do not add SwiftUI snapshot or UI tests for `WaterfallView` in this task.
