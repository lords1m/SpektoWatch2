# Task 1: Non-Destructive Edit Model & Streaming Waveform Analyzer

Status: pending
Created: 2026-11-25
Milestone: `milestone-22-audio-editor-and-converter`

## Goal

Define the immutable, non-destructive `AudioEditRecipe` data model, bounded
undo/redo history, source-to-edited timeline mapper, and streaming
Accelerate-backed `WaveformAnalyzer` so all editor UI and DSP engines share a
single deterministic state model.

## Scope

- **`AudioEditRecipe` (`Codable`, `Equatable`, `Sendable`):**
  - Time edits: ordered kept source ranges (`[ClosedRange<TimeInterval>]`)
    derived from Trim (keep selection) and Cut (delete interior selection),
    `fadeInDuration: TimeInterval`, `fadeOutDuration: TimeInterval`,
    `gainDB: Float` (`-12...12`), `normalizeEnabled: Bool`.
  - 5-band EQ: `[EQBandSetting]` at fixed center frequencies (`60 Hz`, `250 Hz`,
    `1 kHz`, `4 kHz`, `12 kHz`) with gain (`-12...12 dB`) and Q, plus named
    `EQPreset` cases (`flat`, `speech`, `reduceHum`, `clarity`, `warm`).
  - `FilterChainSettings`: HPF (`enabled`, `cutoffHz` `20...500`, slope), LPF
    (`enabled`, `cutoffHz` `1000...20000`, slope), Notch/Band-Stop (`enabled`,
    `centerHz`, `q`), quick `50 Hz` / `60 Hz` mains-hum preset helpers, and
    `enhanceVoiceEnabled: Bool` (Voice-Memos-style one-tap enhance preset).
- **`AudioEditHistory`:**
  - Bounded undo/redo stack (`canUndo`, `canRedo`, `undo()`, `redo()`, `reset()`),
    `hasChanges`, `effectiveDuration`, and deterministic time mapping between
    source file time and edited output timeline time across cut segments.
- **`WaveformAnalyzer`:**
  - Async streaming reader using `AVAudioFile` + Accelerate (`vDSP_maxmgv` /
    `vDSP_rmsqv`) reading fixed 8192–16384-frame chunks off the main thread.
  - Produces overview envelope bins (~1000–2000 min/max peak pairs) plus
    on-demand zoom-window detail bins with `Task` cancellation and caching keyed
    by `(url, fileModificationDate, binCount)`.
- **Unit tests (`SpektoWatch2Tests/`):**
  - `AudioEditRecipeTests`: trim, single/chained interior cuts, undo/redo stack
    bounds, `effectiveDuration`, and source↔edited time mapping.
  - `WaveformAnalyzerTests`: synthetic sine/impulse WAV peak & RMS extraction,
    zoom-window bin accuracy, and cancellation behavior.

## Acceptance

- `AudioEditRecipe` and `AudioEditHistory` accurately track trim, multiple cuts,
  fades, gain, EQ, and filter state with working undo/redo/reset.
- `WaveformAnalyzer` extracts overview and zoomed waveform bins from WAV/M4A
  files off the main thread without loading the entire PCM file into memory.
- `AudioEditRecipeTests` and `WaveformAnalyzerTests` compile and pass.

## Notes

- Keep all models pure Swift / Foundation / AVFoundation / Accelerate under
  `SpektoWatch2/AudioEditor/` so unit tests can exercise them without UI.
