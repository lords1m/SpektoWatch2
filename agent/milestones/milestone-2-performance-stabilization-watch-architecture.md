# Milestone 2: Performance Stabilization And Watch Architecture

Status: completed  
Created: 2026-05-11  
Completed: 2026-05-11  
Source design: `agent/design/spektowatch-field-engineering-design.md`

## Goal

Make live iPhone measurement and recording smooth on iPhone 12 while firming up
the watch microphone path as a compact processed-data source. This milestone
must preserve existing `.spekto` compatibility and keep masking out of scope.

## Completion Criteria

- Live iPhone measurement and recording remain smooth on the iPhone 12 target.
- A representative recording run has no dropped measurement frames.
- Watch microphone live data streams compact processed data at least once per
  second.
- Existing recordings and `.spekto` files remain readable.
- Masking behavior is not changed except where required to preserve builds or
  tests.

## Manual Acceptance

1. Place a real sound level meter near the iPhone.
2. Run SpektoWatch live measurement with the built-in iPhone microphone.
3. Confirm displayed levels roughly match the external meter.
4. Start a recording, stop it, reopen the saved measurement, and verify audio
   plus measurement data are available.
5. Confirm live UI does not visibly degrade to low FPS during recording.
6. Confirm watch live data updates at least once per second in the wearable
   source path.

## Recommended Automated Validation

- `AudioEngineTests`
- `FFTProcessorTests`
- `FrequencyWeightingTests`
- `MeasurementDataIOTests`
- `WatchConnectivityTests`
- `PerformanceProfilingTests`

Use `SpektoWatch2.xctestplan` for broader validation where practical. If the
full simulator suite is too expensive, run the targeted test set and document
skipped tests.

## Tasks

- `agent/tasks/milestone-2-performance-stabilization-watch-architecture/task-1-baseline-and-test-safety.md`
- `agent/tasks/milestone-2-performance-stabilization-watch-architecture/task-2-weighting-and-fft-hot-path.md`
- `agent/tasks/milestone-2-performance-stabilization-watch-architecture/task-3-recording-writer-backpressure.md`
- `agent/tasks/milestone-2-performance-stabilization-watch-architecture/task-4-gate-redundant-processing.md`
- `agent/tasks/milestone-2-performance-stabilization-watch-architecture/task-5-watch-compact-protocol.md`
- `agent/tasks/milestone-2-performance-stabilization-watch-architecture/task-6-watch-wearable-source-controls.md`
- `agent/tasks/milestone-2-performance-stabilization-watch-architecture/task-7-acceptance-and-compatibility.md`

## Explicit Non-Goals

- No masking feature work.
- No full export/report redesign.
- No compliance claims for built-in iPhone or Apple Watch microphones.
- No measurement file format breakage.
- No continuous raw audio transfer over WatchConnectivity.

## Future Milestones

- Dashboard layouts and recording review polish.
- Client-facing export/report redesign.
- External calibrated microphone and compliance workflow.
- Polished masking workflow and reusable masking profiles.
- Watch complications and standalone recording hardening.
