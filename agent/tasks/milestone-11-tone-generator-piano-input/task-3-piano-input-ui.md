# Task 3: Piano Input UI

Status: pending
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

## Acceptance

- Existing slider and acoustic preset controls remain available.
- Selecting a note changes frequency immediately.
- Selected note is visibly indicated.
- UI remains usable at 2x2, 3x3, and 3x4.
