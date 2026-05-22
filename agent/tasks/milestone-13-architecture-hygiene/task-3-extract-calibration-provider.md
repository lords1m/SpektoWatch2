# Task 3: Extract CalibrationProvider from AudioEngine

Status: pending
Created: 2026-05-21
Milestone: `milestone-13-architecture-hygiene`
Source finding: A1 phase 1 in `2026-05-21-architecture-review.md`
Depends on: task-1.

## Goal

Pull `calibrationOffset` + device-specific defaults + persistence
out of `AudioEngine` into a focused `CalibrationProvider` type.
First phase of the AudioEngine decomposition.

## Scope

- New `SpektoWatch2/CalibrationProvider.swift`. Owns:
  - `@Published var offset: Float`
  - Device-specific default lookup (currently
    `AudioEngine.getRecommendedCalibrationOffset` /
    `getDeviceModel`).
  - UserDefaults persistence (`calibrationVersion`,
    `calibrationOffset` keys).
  - Public method `resetToRecommended()`.
- `AudioEngine` holds an instance and forwards reads for backward
  compatibility — every existing consumer of
  `audioEngine.calibrationOffset` continues to work.
- New consumers use the provider directly.
- Persistence keys + version are declared in the persistence
  registry once task-8 lands; for now, document them in
  `CalibrationProvider`'s file header.

## Non-Goals

- Changing the dBFS → dB SPL conversion math.
- Changing how recommended offsets are computed per device.
- Touching the audio frame-processing hot path.

## Acceptance

- AudioEngine.swift LOC drops by ~80-100.
- `audioEngine.calibrationOffset` getter/setter still works for
  existing consumers (forwards to provider).
- Cold launch with existing `calibrationVersion` and saved offset
  loads correctly.
- iOS + watchOS builds green.
- Existing tests pass.
- A new unit test covers `resetToRecommended()` on at least two
  device-model strings.
