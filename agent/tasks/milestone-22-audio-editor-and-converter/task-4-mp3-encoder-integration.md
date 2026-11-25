# Task 4: MP3 Encoder Integration (`libmp3lame` via SPM)

Status: completed
Created: 2026-11-25
Milestone: `milestone-22-audio-editor-and-converter`

## Goal

Enable native on-device MP3 export and `WAV → MP3` (and `M4A/AIFF/CAF/FLAC → MP3`)
conversion on iOS by integrating `libmp3lame` via Swift Package Manager and
implementing `LameMP3Encoder: MP3EncoderBackend`.

## Scope

- **SPM Dependency (iOS Target Only):**
  - Add a prebuilt `libmp3lame` `.xcframework` SPM package (such as
    `LAME-xcframework`) to `SpektoWatch2.xcodeproj` and link it **exclusively** to
    the `SpektoWatch2` iOS app target (and test target as needed).
  - Verify `SpektoWatch Watch App`, `SpektoWatch Complications`, and
    `SpektoWatch2WidgetExtension` do **not** link `LAME` and build cleanly.
- **`LameMP3Encoder` (`MP3EncoderBackend`):**
  - Stream PCM frames from `AVAudioFile` in fixed chunks (e.g. 8192 frames) off
    the main thread through `lame_t` (`lame_init`, `lame_set_in_samplerate`,
    `lame_set_out_samplerate`, `lame_set_num_channels`, `lame_set_brate` / VBR
    mode, `lame_init_params`, `lame_encode_buffer_ieee_float` /
    `lame_encode_buffer_interleaved`, `lame_encode_flush`, `lame_close`).
  - Support mono and stereo inputs, optional stereo-to-mono downmix, target
    sample rates (`original`, `44100`, `48000` via `AVAudioConverter` when
    resampling is needed), CBR bitrates (`128`, `192`, `256`, `320` kbps) and
    VBR (`V2`), plus ID3v2 title/date/comment tags.
  - Report progress (`0.0...1.0`), honor `Task` cancellation, guarantee `lame_close`
    via `defer`, and delete partial `.mp3` files on cancel/failure.
- **Converter Wiring & License Attribution:**
  - Register `LameMP3Encoder` as the default `MP3EncoderBackend` in
    `AudioFormatConverter`.
  - Document LGPL compliance notice for `libmp3lame` (dynamic/xcframework notice
    in project docs / app info).
- **Unit tests (`MP3EncoderTests`):**
  - Convert synthetic mono and stereo WAV fixtures to `.mp3` at 128 and 320 kbps.
  - Verify non-empty output with valid ID3/MP3 frame headers, readable back via
    `AVAudioFile(forReading:)` with duration within ±100 ms of source, and clean
    cancellation cleanup.

## Acceptance

- Converting a `WAV` recording (mono or stereo) to `.mp3` succeeds off the main
  thread and produces a valid, playable `.mp3` file readable by `AVAudioFile` and
  iOS QuickLook/Files.
- `SpektoWatch2`, `SpektoWatch Watch App`, `SpektoWatch Complications`, and
  `SpektoWatch2WidgetExtension` all build without error.
- `MP3EncoderTests` pass.

## Notes

- iOS `AVFoundation` decodes MP3 natively (`AVAudioFile` / `AVAsset`) but has
  no built-in MP3 encoder, making `libmp3lame` the required encoder backend.
