# Task 3: Recording Writer Backpressure

Status: completed  
Created: 2026-05-11  
Completed: 2026-05-11  
Milestone: `milestone-2-performance-stabilization-watch-architecture`

## Objective

Prevent measurement recording writes from stalling audio processing.

## Scope

- Move synchronous measurement frame writes off the audio processing path.
- Use a bounded queue or equivalent backpressure strategy.
- Preserve the existing `.spekto` file format and reader compatibility.
- Add or update tests around measurement data writing and reading.

## Acceptance

- Recording writes no longer block the audio hot path.
- Existing measurement files remain readable.
- New recording output remains readable by `MeasurementDataReader`.
- Dropped-frame behavior is explicit and logged if backpressure is exceeded.

## Non-Goals

- Do not redesign the measurement file format.
- Do not add cloud sync or external storage.

## Implementation Notes

`MeasurementDataWriter` now writes measurement frames through a bounded async
writer path:

- Added a reusable frame-buffer pool sized by `maxPendingFrames`.
- `writeFrame` checks out one buffer, fills it on the caller path, and dispatches
  the file write to the existing serial utility queue.
- If no buffer is available, the frame is dropped, `droppedFrameCount` is
  incremented, and periodic drop logging remains explicit.
- `close()` marks the writer closed, drains pending async writes, syncs the file,
  updates the header frame count, and closes the handle.
- The `.spekto` binary frame layout and `MeasurementDataReader` contract are
  unchanged.

The writer initializer exposes `maxPendingFrames` only as a defaulted parameter
so tests can force backpressure deterministically without changing production
call sites.

Added `MeasurementDataIOTests.testWriterDropsExplicitlyWhenBackpressureCapacityIsZero`
to verify explicit drop behavior and reader compatibility for a zero-frame
recording.

## Validation

Compile gate:

```sh
xcodebuild build-for-testing -project SpektoWatch2.xcodeproj -scheme SpektoWatch2 -testPlan SpektoWatch2 -destination "platform=iOS Simulator,name=iPhone 12 mini,OS=26.3.1"
```

Result: `TEST BUILD SUCCEEDED`.

Runtime targeted tests were not rerun because task 1 established that
CoreSimulator launch currently fails before producing unit-test results. Run
`MeasurementDataIOTests` once simulator launch is healthy.
