# Task 1: Render Thread Safety Precheck

Status: completed
Created: 2026-05-21
Completed: 2026-05-25
Milestone: `milestone-11-tone-generator-piano-input`

## Objective

Resolve or explicitly integrate the M9 tone-generator audit blocker before
adding the piano input UI.

## Context

`agent/tasks/milestone-9-widget-audit/task-8-tone-generator.md` flags
`ToneGenerator.phaseLock` as an `NSLock` used inside the `AVAudioSourceNode`
render callback. The piano input will create another path that mutates
frequency, so the underlying generator must not depend on blocking locks on
the render thread.

## Implementation Notes

- Keep synthesis real-time safe.
- Snapshot mutable frequency/amplitude/waveform state without blocking the
  audio render callback.
- Preserve existing public behavior for `ToneGeneratorWidget`.

## What landed (2026-05-25)

### `ToneGeneratorWidget.swift`

- Added `import os.lock`.
- Added `private struct SynthState { frequency, amplitude, waveform, phase }`.
- Added `private let synthLock = OSAllocatedUnfairLock<SynthState>(initialState:)`.
- `@Published var frequency/amplitude/waveform` gained `didSet` observers that
  call `synthLock.withLock { $0.field = newValue }` — main-thread writes are
  safe and non-blocking for the render thread.
- `private var phase: Double` and `private let phaseLock = NSLock()` **removed**.
- Render callback: `self.phaseLock.lock/unlock` → `synthLock.withLockUnchecked { $0 }`
  (snapshot at start) and `synthLock.withLockUnchecked { $0.phase = currentPhase }`
  (write-back at end). No blocking lock on the render thread.
- `stop()`: `phase = 0.0` → `synthLock.withLock { $0.phase = 0.0 }`.

## Acceptance

- [x] No blocking lock (`NSLock`) taken from the source-node render callback.
- [x] iOS `** BUILD SUCCEEDED **`.
- [ ] Manual smoke: start/stop tone, change frequency/amplitude/waveform (hardware).
