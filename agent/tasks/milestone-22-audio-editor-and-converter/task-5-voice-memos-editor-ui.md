# Task 5: Voice-Memos-Inspired `AudioEditorView` (Waveform, Time, EQ & Filter UI)

Status: pending
Created: 2026-11-25
Milestone: `milestone-22-audio-editor-and-converter`

## Goal

Build the separate `AudioEditorView` and its modular SwiftUI subviews, translating
Apple Voice Memos' intuitive direct-manipulation waveform UX into SpektoWatch2's
Liquid Glass design system for time editing, 5-band EQ, and audio filtering.

## Scope

- **Directory & View Architecture (`SpektoWatch2/AudioEditor/`):**
  - `AudioEditorView.swift` — top-level dedicated view (presented as
    `.fullScreenCover` or standalone sheet) coordinating `AudioEditHistory`,
    `WaveformAnalyzer`, and `AudioEditorEngine`.
  - `WaveformOverviewMinimap.swift` — compact (~48 pt) full-file envelope view
    showing the active zoom viewport window, selection bracket, and playhead.
  - `WaveformDetailCanvas.swift` — high-resolution (~160 pt) Canvas waveform with
    adaptive time ruler, tap-to-seek, horizontal scroll/scrub, two-finger
    pinch-to-zoom (`1×`–`32×`), draggable yellow/amber start/end handles
    (≥44×44 pt hit targets + `UIImpactFeedbackGenerator`), and spatial opacity
    dimming (~100% kept vs. ~30% discarded for Trim and Cut modes).
  - `AudioEditorTransportBar.swift` — thumb-zone `-15s`, `Play/Pause`, `+15s`,
    `Loop` selection toggle, and `Original` (A/B Bypass) hold/toggle button with
    live `.monospacedDigit()` playhead / selection duration readout.
  - `TimeEditPanel.swift` — `Zuschneiden` (Trim to selection), `Bereich löschen`
    (Cut interior selection), Fade-In / Fade-Out sliders (`0...3.0 s`), Gain
    slider (`-12...+12 dB`), and `Normalisieren` toggle.
  - `EQEditorPanel.swift` — live interactive frequency-response `Canvas` curve +
    5 vertical sliders (`60 Hz`, `250 Hz`, `1 kHz`, `4 kHz`, `12 kHz`), preset
    chips (`Flat`, `Sprache`, `Brummen reduzieren`, `Klarheit`, `Warm`), and Reset.
  - `FilterEditorPanel.swift` — Voice-Memos-style one-tap `Sprache verbessern`
    (Enhance) pill, HPF toggle + cutoff (`20–500 Hz`), LPF toggle + cutoff
    (`1–20 kHz`), and Notch/Band-Stop toggle + center frequency/Q + quick
    `50 Hz` / `60 Hz` mains-hum chips.
- **Navigation, Ergonomics & Performance:**
  - Top bar: `Abbrechen` (prompts discard confirmation if `hasChanges`), title +
    edited duration subtitle, `Undo` / `Redo` buttons, and `Export / Speichern` CTA.
  - Segmented contextual tool switcher (`Zeit`, `EQ`, `Filter`, `Export`) keeping
    the waveform and transport controls visible at all times.
  - Isolate 30 Hz playhead state (`AudioEditorEngine.currentTime`) inside the
    waveform/time-readout subviews so EQ sliders and filter panels do not re-body
    30×/s during playback.
  - Full VoiceOver labels and `.accessibilityAdjustableAction` on trim handles
    and sliders; stable `accessibilityIdentifier`s for UI tests.

## Acceptance

- Waveform pinch-to-zoom, tap-to-seek, and trim/cut handle dragging operate
  smoothly without main-thread frame drops.
- Dimming clearly distinguishes kept vs. discarded audio in both Trim and Cut
  previews; EQ curve updates live as bands or filters change.
- All controls meet ≥44×44 pt minimum tap target sizing and include German
  accessibility labels.

## Notes

- Follow `DesignTokens.swift`, `GlassStyle.swift`, and `GlassBackground` so the
  separate editor feels native to SpektoWatch2's Liquid Glass theme.
