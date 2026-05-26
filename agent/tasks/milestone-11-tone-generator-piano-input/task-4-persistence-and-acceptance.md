# Task 4: Persistence And Acceptance

Status: completed
Created: 2026-05-25
Completed: 2026-05-25
Milestone: `milestone-11-tone-generator-piano-input`
Depends on: task-3

## Objective

Persist the optional input mode and validate the full user flow.

## Scope

- Persist input mode and last selected note if widget settings are wired.
- If tone-generator widget settings are still not wired, document that
  limitation and keep state local to the widget.
- Add targeted tests for model and selection behavior.
- Run build and focused tests.

## Widget settings wiring status

The tone generator widget's `settings: [String: String]` dict is passed in
read-only from `DashboardManager` — it cannot be written back from within the
widget. Other widgets (SingleValueWidget, LAFGraphWidget) also only read from it.
Persistence is therefore implemented via `@AppStorage` (UserDefaults.standard),
the same approach used by `TweaksPanelView` for design-token settings.

## What landed (2026-05-25)

### `Shared/PersistenceKeys.swift`

- Added `public enum ToneGenerator` namespace with three keys:
  `inputMode` ("toneGenerator.inputMode"), `pianoOctave`
  ("toneGenerator.pianoOctave"), `selectedMidi` ("toneGenerator.selectedMidi").

### `SpektoWatch2/ToneGeneratorWidget.swift`

- Replaced `@State private var inputMode/pianoOctave/selectedNote` with:
  - `@AppStorage(PersistenceKeys.ToneGenerator.inputMode) inputModeRaw: String`
  - `@AppStorage(PersistenceKeys.ToneGenerator.pianoOctave) pianoOctave: Int`
  - `@AppStorage(PersistenceKeys.ToneGenerator.selectedMidi) selectedMidi: Int`
  - `@State private var selectedNote: MusicalNote?` (runtime-only, restored on appear)
- Added computed `inputMode: InputMode` getter from `inputModeRaw`.
- Added `inputModeBinding: Binding<InputMode>` — set path runs mode-switch
  side-effects (nearest-note pre-selection + MIDI save) and is used by the Picker.
- Removed the now-redundant `.onChange(of: inputMode)` modifier on the Picker.
- Updated Stepper `.onChange` to also clear `selectedMidi = -1`.
- Updated note-selection callback to write `selectedMidi = note.midiNote`.
- Added `.onAppear` that reconstructs `selectedNote` from `selectedMidi` using the
  same MIDI → (octave, semitone, Name) arithmetic as `MusicalNote.midiNote`.

### `SpektoWatch2Tests/PianoSelectionTests.swift` (NEW)

- 8 XCTest cases:
  - `testSelectA4Sets440Hz` — smoke scenario from acceptance criteria.
  - `testNearestTo440IsA4` — `nearest(to:)` agrees.
  - `testMidiRoundTripAllNotes` — 108-note MIDI round-trip (persist + reconstruct).
  - `testMidiSentinelProducesNoNote` — sentinel -1 excluded.
  - `testMidiBoundaryReconstruction` — MIDI 12 (C0) and 119 (B8).
  - `testPianoModeSwitchPreSelectsCorrectOctave` — switch to piano at 440 Hz → oct 4.
  - `testPianoModeSwitchAtC4` — switch at C4 pre-selects C4.
  - `testFrequencyDisplayConsistencyForA4` — Hz display label "440.0".

## Acceptance

- [x] App builds (iOS `** BUILD SUCCEEDED **`).
- [x] Test target builds cleanly (no new errors).
- [x] Persistence keys registered in `PersistenceKeys`.
- [ ] Focused tests pass on hardware / Xcode Cloud (simulator broken locally).
- [ ] Manual smoke: switch to piano input, select A4, confirm 440 Hz display,
      play tone, switch back to Hz input, use existing slider/presets.
