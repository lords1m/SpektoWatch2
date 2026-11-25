# Task 6: Format Conversion Sheet, Save Flows & App Entry Points

Status: pending
Created: 2026-11-25
Milestone: `milestone-22-audio-editor-and-converter`

## Goal

Implement `AudioExportSheet` for multi-format conversion (`WAV`, `MP3`,
`M4A/AAC`, `ALAC`, `AIFF`, `CAF`), safe SpektoWatch2 recording persistence that
protects calibrated `.spekto` sidecars, external audio file import, and all UI
entry points in `RecordingDetailView` and `RecordingsListView`.

## Scope

- **`AudioExportSheet.swift` (`SpektoWatch2/AudioEditor/`):**
  - Format picker (`WAV`, `MP3`, `M4A (AAC)`, `ALAC`, `AIFF`, `CAF`) with
    short format descriptions (lossless vs. compressed, typical use case).
  - Dynamic quality controls: bitrate selector (`128` / `192` / `256` / `320` kbps
    or VBR) for `MP3`/`M4A (AAC)`, bit depth (`16` / `24`-bit) for `WAV`/`AIFF`,
    sample rate (`Original`, `44.1 kHz`, `48 kHz`), and channel mode (`Original`,
    `Mono`).
  - Live estimated output file size readout based on edited duration and format.
  - Cancellable progress overlay during offline edit render + format conversion,
    followed by direct Share (`ActivityView`) or Save-to-Files export.
- **Measurement-Integrity-Safe Save Flows:**
  - For `Recording`-backed sessions:
    - **Default — "Als neue Kopie speichern":** Renders edited audio (in chosen
      format or source-compatible PCM/M4A), writes into `Documents/Recordings/`,
      and inserts a new `Recording` via `RecordingManager` named
      `"<Originalname> (Bearbeitet)"` with updated `duration`, `sampleRate`,
      `channelCount`, and `measurementDataFileName: nil`. Original recording and
      its `.spekto` measurement sidecar remain untouched.
    - **Secondary — "Original ersetzen":** Shows explicit confirmation alert
      warning that any calibrated `.spekto` measurement data will be detached
      (since time/EQ/filter edits invalidate SPL calibration), atomically
      replaces the audio file, and updates the `Recording` metadata.
  - For standalone external files (imported via `.fileImporter`):
    - Offers **Teilen / In Dateien sichern** (`ActivityView` / file exporter)
      and optional **"In Aufnahmen importieren"** to add the converted file to
      `RecordingManager`.
- **Entry Points & Localization:**
  - `RecordingDetailView`: add `Audio bearbeiten & konvertieren` in the trailing
    toolbar menu and a prominent action card/button; pause `audioPlayer` before
    opening `.fullScreenCover`, and reload `audioPlayer` / recording state if the
    original was replaced.
  - `RecordingsListView`: add row context menu action (`Bearbeiten / Konvertieren`)
    and toolbar action (`Audiodatei importieren`) using
    `.fileImporter(allowedContentTypes: [.audio])` to open external files
    (e.g. `.wav`, `.mp3`, `.m4a`, `.flac`, `.aiff`, `.caf`) directly in
    `AudioEditorView`.
  - Home-Screen representation (`AudioWidgetType.audioEditor` / `WidgetCardView`
    integration ready for `M23`'s dual-mode system):
    - `AudioEditorHomeWidget`: compact Mainscreen widget (`2×1` / `3×1`) showing
      the latest recording's mini waveform, duration/format badge, and quick
      `Bearbeiten`, `Konvertieren`, and `Importieren` actions.
    - `AudioEditorIconTile`: `1×1` Home-Screen Icon launcher opening
      `AudioEditorView` (latest recording or external file import).
  - Add all new German/English strings to `SpektoWatch2/Localizable.xcstrings`.

## Acceptance

- Exporting to any of the 6 formats (`WAV`, `MP3`, `M4A`, `ALAC`, `AIFF`, `CAF`)
  completes with accurate progress, cancellation safety, and a valid shareable
  file.
- "Als neue Kopie speichern" leaves the original `Recording` and its `.spekto`
  file intact and adds a playable edited copy to `RecordingsListView`.
- Importing an external `.wav` file via `RecordingsListView` and converting it
  to `.mp3` works end-to-end without creating unwanted measurement artifacts.

## Notes

- Use `RecordingManager.updateRecording` / `addRecording` patterns and never
  directly mutate `recordings_metadata_v2.json`.
