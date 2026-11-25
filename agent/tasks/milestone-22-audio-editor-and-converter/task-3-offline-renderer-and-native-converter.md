# Task 3: Offline Edit Renderer & Native Audio Format Converter

Status: pending
Created: 2026-11-25
Milestone: `milestone-22-audio-editor-and-converter`

## Goal

Implement faster-than-real-time offline rendering (`AudioEditRenderer`) that
materializes an `AudioEditRecipe` into a clean PCM file, plus a streaming
multi-format converter (`AudioFormatConverter`) supporting all native Apple
audio output formats (`WAV`, `M4A/AAC`, `ALAC`, `AIFF`, `CAF`) and defining the
`MP3EncoderBackend` hook for Task 4.

## Scope

- **`AudioEditRenderer`:**
  - Renders kept source segments via `AVAudioEngine.enableManualRenderingMode(.offline, ...)`
    through the exact same `AVAudioUnitEQ` configuration helper used by
    `AudioEditorEngine`.
  - Applies 5–10 ms raised-cosine micro-crossfades at cut splice boundaries to
    eliminate discontinuities/clicks, plus linear/S-curve `fadeInDuration` and
    `fadeOutDuration` ramps and gain.
  - Supports optional two-pass peak normalization (`-1.0 dBFS` ceiling) when
    `normalizeEnabled` is enabled.
  - Streams fixed 4096-frame buffers off the main thread, reports progress
    (`0.0...1.0`), honors `Task` cancellation, and removes temporary files on
    cancellation or failure.
- **`AudioExportFormat` & `AudioExportOptions`:**
  - Supported formats: `.wav`, `.mp3`, `.m4aAAC`, `.alac`, `.aiff`, `.caf`.
  - Options: PCM bit depth (`16` / `24`-bit for WAV/AIFF), bitrate (`128` /
    `192` / `256` / `320` kbps for AAC/MP3), sample rate (`original`, `44100`,
    `48000`), channel layout (`original`, `mono` downmix), optional ID3/asset
    title metadata, and output file-size estimator.
- **`AudioFormatConverter` & `MP3EncoderBackend`:**
  - Converts any readable input (`WAV`, `CAF`, `M4A`, `ALAC`, `AIFF`, `FLAC`,
    `MP3`) to `WAV`, `M4A (AAC)`, `ALAC`, `AIFF`, and `CAF` using `AVAudioFile`,
    `AVAudioConverter`, and `AVAssetWriter` / `AVAssetExportSession`.
  - Defines `protocol MP3EncoderBackend` and routes `.mp3` conversion through it
    (implemented in `task-4-mp3-encoder-integration`).
- **Unit tests (`SpektoWatch2Tests/`):**
  - `AudioEditRendererTests`: synthetic multi-tone WAV (`100 Hz + 1 kHz + 8 kHz`)
    verifying exact Trim output duration, Cut output duration & splice continuity,
    and spectral attenuation via `FFTProcessor` for HPF, LPF, Notch, and EQ.
  - `AudioFormatConverterTests`: round-trip conversions (`WAV → M4A`,
    `WAV → ALAC`, `WAV → AIFF`, `WAV → CAF`, `M4A → WAV`) verifying readable
    output, expected duration within tolerance, sample rate, and non-zero audio.

## Acceptance

- Offline rendered audio matches live `AudioEditorEngine` EQ/filter behavior and
  exhibits zero clicks across cut boundaries.
- `AudioFormatConverter` converts cleanly between `WAV`, `M4A (AAC)`, `ALAC`,
  `AIFF`, and `CAF` with streaming memory usage and clean cancellation cleanup.
- `AudioEditRendererTests` and `AudioFormatConverterTests` pass.

## Notes

- Do not assume `AVAudioFile` settings alone can write `.m4a`/AAC on all OS
  versions without testing; verify `AVAssetWriter` / `AVAudioFile` behavior in
  `AudioFormatConverterTests` on iOS Simulator.
