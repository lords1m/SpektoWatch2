# Task 3: Piano Input UI

Status: completed
Created: 2026-05-25
Completed: 2026-05-25
Milestone: `milestone-11-tone-generator-piano-input`
Depends on: task-2

## Objective

Add the optional compact piano-style input to `ToneGeneratorWidget`.

## Scope

- Add a small mode switch between Hz control and piano/note control.
- Render compact note buttons or piano-style keys that fit inside the widget.
- Update `toneGenerator.frequency` through the same path used by the existing
  slider and presets.
- Keep exact Hz display visible.

## What landed (2026-05-25)

### `SpektoWatch2/ToneGeneratorWidget.swift`

- Added `private struct PianoInputView` (new, ~60 LOC): one-octave piano keyboard
  rendered in a `GeometryReader + ZStack`. White keys fill the full width (7 keys,
  1 pt gaps); black keys overlay at 62 % width / 60 % height. Selected note shown
  with blue fill and a bottom dot on white keys, blue fill on black keys. Tap any
  key to call `onNoteSelected`.
- Added `private enum InputMode { case hz, piano }` inside `ToneGeneratorWidget`.
- Added `@State private var inputMode: InputMode = .hz`, `@State private var
  pianoOctave: Int = 4`, `@State private var selectedNote: MusicalNote? = nil`.
- Replaced the hard-coded slider+presets section with:
  - `Picker("Eingabemodus", …)` with `.segmented` style (Hz / Piano toggle).
  - `if inputMode == .hz` branch: original slider + preset scroll view, unchanged.
  - `else` branch: octave stepper + selected-note label + `PianoInputView(…)` at
    64 pt height.
- `.onChange(of: inputMode)`: on switching to piano, pre-selects the nearest note
  and navigates to that octave.
- Frequency is set via `toneGenerator.frequency = note.frequency` — same path as
  existing slider and preset buttons.

## Acceptance

- [x] Existing slider and acoustic preset controls remain available (Hz mode unchanged).
- [x] Selecting a note changes frequency immediately.
- [x] Selected note is visibly indicated (blue fill + dot).
- [x] iOS `** BUILD SUCCEEDED **`.
- [ ] UI usability at 2x2, 3x3, 3x4 (hardware / manual).
