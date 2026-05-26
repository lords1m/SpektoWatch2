# Task 2: Note Frequency Model

Status: completed
Created: 2026-05-25
Completed: 2026-05-25
Milestone: `milestone-11-tone-generator-piano-input`
Depends on: task-1

## Objective

Add a small pure model for musical note selection and Hz conversion.

## Scope

- Define note names and octave range.
- Convert note + octave to frequency using A4 = 440 Hz.
- Provide display labels and stable selected-note identity.
- Keep the model independent of SwiftUI and AVFoundation.

## What landed (2026-05-25)

### `SpektoWatch2/Models/MusicalNote.swift` (NEW)

- `import Darwin` for `pow` / `log2`.
- `MusicalNote: Hashable, Identifiable, CustomStringConvertible` — pure Swift, no framework deps.
- `Name` enum: 12 cases `C…B` with `.displayName` and `.isSharp`.
- `midiNote`: `(octave + 1) * 12 + name.rawValue` → C0 = 12, A4 = 69, B8 = 119.
- `frequency`: `440 × 2^((midiNote − 69) / 12)`.
- `notes(in:)` returns all 12 notes for an octave, C first.
- `nearest(to:)` clamps to supported range (MIDI 12…119).

### `SpektoWatch2Tests/NoteFrequencyModelTests.swift` (NEW)

- 22 XCTest cases: frequency accuracy (A4 = 440 Hz, C4 ≈ 261.626 Hz), octave
  doubling/halving, boundary notes (C0, B8), MIDI numbering, labels, sharp
  identification, `notes(in:)` ordering, `nearest(to:)` clamping, Hashable
  equality, and unique-ID invariant across all 108 supported notes.
- Compiles clean (only pre-existing `AudioEngineTests.swift` build error in
  test target; unrelated to this task).

## Acceptance

- [x] A4 maps to exactly 440 Hz.
- [x] Octaves double/halve as expected.
- [x] Unit tests cover representative notes, octave boundaries, and labels.
- [x] iOS `** BUILD SUCCEEDED **`.
