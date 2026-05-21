# Milestone 11: Tone Generator Piano Input

Status: pending
Started: null
Priority: low
Estimated: 0.5 weeks

## Goal

Add a small optional piano-style frequency input to the existing tone generator
widget as an easter egg / alternate control path. It should let users pick
musical notes quickly without weakening the widget's primary engineering role
as a frequency generator.

## Why

The tone generator currently exposes direct frequency control through a
logarithmic slider and fixed acoustic preset buttons. A compact piano input is
useful for quick musical reference tones such as A4 = 440 Hz, octave checks,
and harmonics, while keeping exact Hz control available for measurement work.

## Scope

1. Fix the tone generator's known audio-render-thread safety issue before
   adding new UI paths. M9 task-8 identified `ToneGenerator.phaseLock` as an
   `NSLock` used inside the source-node render callback.
2. Add a pure note-to-frequency model with A4 = 440 Hz, octave-aware note
   names, and deterministic rounding/formatting.
3. Add an optional compact piano input mode inside `ToneGeneratorWidget`.
   The existing Hz slider and acoustic preset buttons remain the default
   engineering controls.
4. Persist the selected input mode and last selected note through the widget
   settings path if that path is available by implementation time.
5. Keep layout usable at the M8 `toneGenerator` minimum size of 2x2.

## UX Direction

- The control should be compact, optional, and clearly secondary.
- Use familiar note labels (`C`, `C#`, `D`, etc.) and octave controls rather
  than a full decorative piano keyboard if space is tight.
- The selected note must update the same `toneGenerator.frequency` value used
  by the slider, presets, oscilloscope, and audio engine.
- Exact Hz display remains visible so the feature stays instrument-like.

## Non-Goals

- No polyphony, MIDI, recording, sequencing, scales, or full keyboard
  performance mode.
- No change to waveform synthesis semantics.
- No watchOS tone-generator UI work.
- No compliance or calibration claims.

## Acceptance

- Existing tone generator frequency slider and preset buttons still work.
- Optional piano input can select notes across a bounded octave range.
- A4 maps to exactly 440 Hz.
- Frequency updates are reflected in audio output, display text, and the
  oscilloscope path.
- The widget remains usable at 2x2 and larger M8 sizes.
- Targeted tests cover note-frequency mapping and persistence/selection logic.
