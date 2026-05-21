# Task 2: Note Frequency Model

Status: pending
Milestone: `milestone-11-tone-generator-piano-input`
Depends on: task-1

## Objective

Add a small pure model for musical note selection and Hz conversion.

## Scope

- Define note names and octave range.
- Convert note + octave to frequency using A4 = 440 Hz.
- Provide display labels and stable selected-note identity.
- Keep the model independent of SwiftUI and AVFoundation.

## Acceptance

- A4 maps to exactly 440 Hz.
- Octaves double/halve as expected.
- Unit tests cover representative notes, octave boundaries, and labels.
