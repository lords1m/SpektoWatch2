# Task 5: Extract RecordingCoordinator from AudioEngine

Status: pending
Created: 2026-05-21
Milestone: `milestone-13-architecture-hygiene`
Source finding: A1 phase 3 in `2026-05-21-architecture-review.md`
Depends on: task-4.

## Goal

Pull recording start/stop control + `recordingDuration` ticker out
of AudioEngine into a focused coordinator. Final phase of the
AudioEngine decomposition.

## Scope

- New `SpektoWatch2/RecordingCoordinator.swift`. Owns:
  - `@Published var isRecording: Bool`
  - `@Published var isMeasurementRecording: Bool`
  - `@Published var isRecordingToFile: Bool`
  - `@Published var recordingDuration: TimeInterval`
  - Duration-ticker `Timer` lifecycle.
  - `start()` / `stop()` / `cancel()` methods coordinating with
    `RecordingManager` and `MeasurementDataWriter`.
- AudioEngine holds one `RecordingCoordinator` and exposes it.
- AudioEngine keeps forwarding stubs for one release cycle.

## Non-Goals

- Replacing `RecordingManager` (which already exists and handles
  the file-system side).
- Changing the recording file format.
- Touching `MeasurementDataWriter`.

## Acceptance

- AudioEngine.swift LOC drops by ~150.
- ControlBarView still drives recording correctly.
- Existing recordings still play back via RecordingDetailView.
- iOS build green; existing tests pass.
- After this task, AudioEngine should be ≤ 1300 LOC (down from
  1761). Further reductions are out of scope for M13.
