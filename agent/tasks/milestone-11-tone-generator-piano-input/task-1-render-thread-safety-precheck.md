# Task 1: Render Thread Safety Precheck

Status: pending
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

## Acceptance

- No blocking lock is taken from the source-node render callback.
- Existing tone generator tests still build.
- Manual smoke: start/stop tone, change frequency, amplitude, waveform.
