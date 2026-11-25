# Task 7: Acceptance, Automated Tests & Hardware Verification

Status: in_progress
Created: 2026-11-25
Milestone: `milestone-22-audio-editor-and-converter`

## Goal

Verify all Milestone 22 build targets, unit tests, UI smoke tests, simulator
screenshots, and hardware acceptance checks, and record the completed handoff
report in `agent/reports/`.

## Scope

- **Multi-Target Build & Unit Tests:**
  - Build all targets (`SpektoWatch2`, `SpektoWatch Watch App`,
    `SpektoWatch Complications`, `SpektoWatch2WidgetExtension`, `SpektoWatch2Tests`)
    and verify `LAME` is linked only on iOS.
  - Run `AudioEditRecipeTests`, `WaveformAnalyzerTests`,
    `AudioEditRendererTests`, `AudioFormatConverterTests`, and `MP3EncoderTests`
    as well as existing `SpektoWatch2Tests` regression suites.
- **UI Smoke Tests & Screenshots:**
  - Add `AudioEditorUITests` in `SpektoWatch2UITests/` verifying opening
    `AudioEditorView` from a recording, switching between `Zeit` / `EQ` / `Filter`
    panels, toggling `Sprache verbessern`, and opening `AudioExportSheet`.
  - Refresh simulator screenshots via `./agent/scripts/capture-screenshots.py`.
- **Hardware Acceptance Checklist (On-Device):**
  1. Pinch-to-zoom waveform (`1×`–`32×`) and trim/cut handle dragging at 60/120 FPS.
  2. Real-time audible preview of 5-band EQ, HPF/LPF/Notch, Loop Selection, and
     A/B Bypass (`Original` vs. `Bearbeitet`).
  3. Trim + interior Cut produce click-free playback and export.
  4. `WAV → MP3` (128/320 kbps), `WAV → M4A (AAC)`, `WAV → ALAC`, `WAV → AIFF`,
     and `WAV → CAF` exports play cleanly in Apple Files / QuickLook.
  5. External `.wav` import via `.fileImporter` converts to `.mp3` and shares
     cleanly.
  6. "Als neue Kopie speichern" leaves original `.spekto` recording untouched.
  7. Long recording (30+ min) waveform analysis and offline render complete
     within memory budget and handle mid-render cancellation with no temp leaks.
- **ACP Closure:**
  - Write acceptance report at `agent/reports/YYYY-MM-DD-milestone-22-acceptance.md`.
  - Update `agent/STATE.md`, `agent/progress.yaml`, and run `./agent/scripts/acp-validate`.

## Acceptance

- All unit and UI smoke tests pass on iOS Simulator with zero compiler errors.
- All 7 hardware checklist items pass on device (or remaining hardware items are
  explicitly documented in the acceptance report if executed code-side first).
- `./agent/scripts/acp-validate` exits 0.

## Notes

- Keep any audio fixtures generated in tests deterministic (synthetic sine /
  multi-tone buffers created in temp directories and cleaned up in `tearDown`).
