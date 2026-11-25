# Milestone 22: Audio Editor & Format Converter

Status: in_progress
Created: 2026-11-25
Priority: medium
Estimated: 3 weeks

## Goal

Provide a dedicated, separate iOS view (`AudioEditorView`) for simple,
non-destructive audio editing (time trimming/cutting, fades, gain, 5-band EQ,
and HPF/LPF/Notch filtering plus an Enhance Voice preset) and multi-format
audio conversion (`WAV`, `MP3`, `M4A/AAC`, `ALAC`, `AIFF`, `CAF`) for both
SpektoWatch2 recordings and imported external audio files.

To align with the Home-Screen dual-mode architecture (`M23`), the Audio Editor
& Format Converter also exposes a Home-Screen representation
(`AudioWidgetType.audioEditor`) in both modes:
- **Icon (`1×1`):** Compact Liquid Glass launcher tile (`Audio-Editor`) opening
  `AudioEditorView` (for the latest recording or external file import).
- **Mainscreen-Widget (`2×1` / `3×1`):** `AudioEditorHomeWidget` displaying the
  latest recording's mini waveform, duration/format badge, and quick actions
  (`Bearbeiten`, `Konvertieren`, `Importieren`).

## Apple Voice Memos UI/UX Research & Adaptation

Apple's iOS Voice Memos editor achieves fast, approachable single-hand audio
editing by replacing complex DAW timelines with direct-manipulation waveform
controls and unmistakable visual states:

- **Two-Tier Waveform Navigation:**
  - Compact top overview minimap (~48 pt) displaying the entire recording
    envelope, current zoom viewport bracket, and active selection range.
  - Main high-resolution bidirectional detail waveform canvas (~160 pt) with an
    adaptive time ruler, horizontal scroll/scrub, and two-finger pinch-to-zoom
    (`1×`–`32×`) down to millisecond precision.
- **Direct-Manipulation Selection Handles:**
  - High-contrast yellow/amber vertical selection handles on left and right edges
    with ≥44×44 pt touch targets and light haptic feedback on grab/snap.
  - Spatial opacity dimming makes intent unambiguous: kept audio stays bright
    (~100% opacity) while audio marked for removal is dimmed (~30% opacity) for
    both **Trim** (keep inside selection) and **Cut/Delete** (remove interior,
    spliced with a 5–10 ms cosine micro-crossfade to prevent clicks).
- **Thumb-Zone Transport & Safety Net:**
  - Bottom-anchored `-15s` / `Play/Pause` / `+15s` transport controls paired with
    **Loop Selection** and **A/B Bypass** (`Original` vs. `Bearbeitet`) for
    instant auditioning of EQ and filter changes.
  - Top bar houses **Undo / Redo / Reset** backed by an immutable
    non-destructive `AudioEditRecipe` history stack.
- **Single-Screen Contextual Tool Bar (No DAW Clutter):**
  - Compact segmented tool switcher (`Zeit`, `EQ`, `Filter`, `Export`) below the
    waveform and transport bar so the waveform stays visible while tweaking
    parameters.
  - Includes a Voice-Memos-style one-tap **"Sprache verbessern" (Enhance)**
    preset combining gentle HPF, vocal presence boost, and light normalization.
- **SpektoWatch2 Adaptation:**
  - Uses SpektoWatch2's Liquid Glass visual language (`GlassBackground`,
    `DesignTokens`, `.numerals`, `.monospacedDigit()`) and German UI strings
    (`Localizable.xcstrings`).
  - Protects calibrated acoustic measurement integrity: saving defaults to
    **"Als neue Kopie speichern"** so the original recording and its `.spekto`
    measurement sidecar stay untouched; **"Original ersetzen"** requires explicit
    confirmation and detaches any stale `.spekto` sidecar.

## Current State (2026-11-25 Baseline)

What already exists:
- `RecordingManager` persists `Recording` entries (`audioFileName`, optional
  `measurementDataFileName` `.spekto` sidecar, `sampleRate`, `channelCount`,
  `duration`) under `Documents/Recordings/`.
- `AudioPlayerManager` wraps `AVAudioEngine` + `AVAudioPlayerNode` with
  generation-guarded `scheduleSegment` playback and `.playAndRecord` /
  `.defaultToSpeaker` session activation.
- `BandstopFilter` / `BandstopFilterManager` implement live frequency-domain
  band-stop definitions, while `AVAudioUnitEQ` provides unified time-domain EQ
  and HPF/LPF/Notch filtering for both real-time preview and offline manual
  rendering.
- `ActivityView` and `RecordingDetailView` handle share sheets and export
  progress overlays.

What is missing:
- Dedicated `AudioEditorView` and modular waveform/EQ/filter/time UI panels.
- Non-destructive `AudioEditRecipe` model, undo/redo history, and streaming
  `WaveformAnalyzer`.
- Real-time preview engine (`AudioEditorEngine`) with live EQ/filter updates,
  A/B bypass, loop selection, and cut-skipping playback.
- Faster-than-real-time offline renderer (`AudioEditRenderer`) and multi-format
  converter (`AudioFormatConverter` + `LameMP3Encoder` via SPM).

## Technical Architecture & Format Matrix

- **Unified Live & Offline DSP Graph:**
  `AVAudioEngine` (`AVAudioPlayerNode` → `AVAudioUnitEQ` [8 bands: HPF, LPF,
  Notch, 5 parametric EQ bands] → gain/mixer). A single shared
  `AVAudioUnitEQ` configuration helper drives both live preview
  (`AudioEditorEngine`) and offline rendering (`AudioEditRenderer` via
  `enableManualRenderingMode(.offline, ...)`).
- **Format Conversion Matrix:**
  - **Native (`AVAudioFile` / `AVAudioConverter` / `AVAssetWriter`):** Read &
    Write `WAV` (PCM 16/24-bit), `M4A (AAC 128/192/256/320 kbps)`, `ALAC`
    (lossless `.m4a`), `AIFF` (16/24-bit), and `CAF`. Read-only native import
    for `FLAC` and `MP3` (can be edited and converted to any supported output).
  - **MP3 Write (`MP3EncoderBackend`):** iOS `AVFoundation` provides no native
    MP3 encoder. Integrate `libmp3lame` via Swift Package Manager
    (`LAME-xcframework`), linked **exclusively** to the iOS `SpektoWatch2`
    target (never watchOS or WidgetExtension), with streaming PCM encoding,
    CBR (`128`/`192`/`256`/`320` kbps) and VBR (`V2`), and ID3v2 tags.
- **Streaming Memory Budget:**
  `WaveformAnalyzer` and `AudioEditRenderer` stream fixed buffers
  (4096–16384 frames) off the main thread with `Task` cancellation and progress
  callbacks so 30+ minute recordings never OOM.

## Scope & Non-Goals

In scope:
- Separate `AudioEditorView` reachable from `RecordingDetailView`,
  `RecordingsListView`, external `.fileImporter(allowedContentTypes: [.audio])`,
  and the Home Screen (`AudioWidgetType.audioEditor`).
- Home-Screen Icon (`1×1` launcher tile `AudioEditorIconTile`) and Mainscreen
  Live-Widget (`AudioEditorHomeWidget` with latest recording mini waveform,
  duration/format badge, and quick `Bearbeiten` / `Konvertieren` / `Importieren`
  actions).
- Voice-Memos-style trim, interior cut, fade-in/out, gain, and peak normalize.
- 5-band parametric/graphic EQ + presets and interactive frequency-response curve.
- HPF, LPF, Notch/Band-Stop filters (with 50/60 Hz mains-hum chips) and
  "Sprache verbessern" (Enhance) preset.
- Non-destructive undo/redo, real-time preview with loop & A/B bypass, offline
  render, and multi-format export (`WAV`, `MP3`, `M4A/AAC`, `ALAC`, `AIFF`,
  `CAF`) with save-as-copy, replace-original (with sidecar warning), and share.

Non-goals:
- Multi-track DAW mixing, MIDI, or virtual instruments.
- Destructive mutation or re-calibration of `.spekto` measurement sidecars.
- watchOS audio editing or WidgetExtension linking of `libmp3lame`.
- FLAC encoding (read-only import is supported natively) or cloud transcoding.

## Acceptance Criteria

1. **Voice-Memos-parity waveform interaction:** Overview minimap, 1×–32×
   pinch-to-zoom detail canvas, ≥44×44 pt trim/cut handles with haptics, spatial
   opacity dimming, and smooth 60/120 FPS Canvas rendering.
2. **Accurate time edits:** Trim isolates `[start, end]` cleanly; interior Cut
   removes selected audio with a click-free 5–10 ms cosine micro-crossfade;
   Fade In/Out and Gain/Normalize apply accurately.
3. **Live preview matches offline render:** Real-time EQ, HPF/LPF/Notch, A/B
   bypass, and loop selection match offline output; automated FFT tests confirm
   expected spectral attenuation in rendered files.
4. **Multi-format conversion:** Exports playable files with verified codec,
   duration, and non-empty payload for `WAV`, `MP3`, `M4A (AAC)`, `ALAC`,
   `AIFF`, and `CAF` (including WAV → MP3 and MP3 → WAV round-trips).
5. **Measurement integrity preserved:** "Als neue Kopie speichern" adds a
   playable edited copy to `RecordingManager` without altering the original
   recording or its `.spekto` sidecar; "Original ersetzen" warns and detaches
   stale sidecars.
6. **Standalone external file workflow:** Importing an external `.wav`/`.m4a`/
   `.mp3`/`.flac` via `.fileImporter` opens cleanly in `AudioEditorView` and
   converts/shares without errors.
7. **Accessibility & durability:** ≥44 pt tap targets, VoiceOver labels and
   adjustable traits on handles/sliders, cancellable rendering with zero temp-file
   leaks, and bounded streaming memory on long recordings.
8. **Home-Screen Icon & Mainscreen-Widget entry points:** `AudioWidgetType.audioEditor`
   works both as a `1×1` Home-Screen Icon launching `AudioEditorView` and as an
   inline `AudioEditorHomeWidget` displaying the latest recording preview with
   working quick actions (`Bearbeiten`, `Konvertieren`, `Importieren`).

## Tasks

1. `task-1-edit-model-and-waveform-analyzer` — Non-destructive `AudioEditRecipe`, undo/redo history, time mapping, and streaming Accelerate `WaveformAnalyzer` + tests.
2. `task-2-realtime-preview-engine` — `AudioEditorEngine` for real-time EQ/filter preview, A/B bypass, loop selection, and cut-skipping playback + tests.
3. `task-3-offline-renderer-and-native-converter` — Offline `AudioEditRenderer` (`AVAudioEngine` manual rendering) and native `AudioFormatConverter` (`WAV`, `M4A/AAC`, `ALAC`, `AIFF`, `CAF`) + tests.
4. `task-4-mp3-encoder-integration` — `libmp3lame` SPM integration (iOS-only) and streaming `LameMP3Encoder` (`MP3EncoderBackend`) + tests.
5. `task-5-voice-memos-editor-ui` — `AudioEditorView` and modular waveform/time/EQ/filter panels modeled after Apple Voice Memos with Liquid Glass styling.
6. `task-6-export-sheet-and-app-integration` — `AudioExportSheet`, save-as-copy/replace flows, `RecordingDetailView` & `RecordingsListView` entry points, `.fileImporter`, and `Localizable.xcstrings`.
7. `task-7-acceptance-and-ui-tests` — Full multi-target build, unit/UI smoke tests, screenshots, hardware checklist, and ACP acceptance report.
