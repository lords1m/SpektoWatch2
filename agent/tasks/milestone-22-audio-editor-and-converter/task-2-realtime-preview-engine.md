# Task 2: Real-Time Preview Audio Engine (EQ, Filters, Cuts, Loop & A/B Bypass)

Status: pending
Created: 2026-11-25
Milestone: `milestone-22-audio-editor-and-converter`

## Goal

Build `AudioEditorEngine` to provide low-latency real-time playback preview of
`AudioEditRecipe` changes—including live 5-band EQ, HPF/LPF/Notch filtering,
gain, A/B bypass comparison, selection looping, and seamless cut-skipping—with
safe `AVAudioSession` and live-mic engine coordination.

## Scope

- **Shared `AVAudioUnitEQ` graph helper:**
  - Configure an 8-band `AVAudioUnitEQ` (band 0 = high-pass, band 1 = low-pass,
    band 2 = band-stop/notch, bands 3…7 = 5 parametric EQ bands at 60/250/1k/4k/12k Hz)
    plus mixer gain so live preview and offline rendering (`task-3`) share one
    source of truth for filter coefficients.
- **`AudioEditorEngine` (`@MainActor ObservableObject`):**
  - Owns its own `AVAudioEngine`, `AVAudioPlayerNode`, and `AVAudioUnitEQ`.
  - Updates EQ/filter/gain parameters live during playback without interrupting
    the audio stream.
  - Instant `isBypassed` A/B toggle (switches between processed recipe and raw
    original signal) and `isLoopingSelection` toggle (loops active `[start, end]`
    selection).
  - Transport actions matching Voice Memos UX: `play()`, `pause()`, `stop()`,
    `seek(to:)`, `seek(by: ±15s)`, `beginScrubbing()`, `endScrubbing()`, and a
    monotonic `playbackGeneration` counter (following `AudioPlayerManager` in
    `SpektoWatch2/Views/AudioPlayerManager.swift`) to reject stale completion
    callbacks.
  - Edit-list segment scheduling: skips cut/deleted interior ranges seamlessly
    and maps node render time back to both edited timeline time and source file
    time for the playhead.
  - Suspends the live measurement `AudioEngine` while active (matching
    `PlaybackAnalyzer` lifecycle) and activates `.playAndRecord` / `.playback`
    with `.defaultToSpeaker` so playback routes cleanly through the speaker.
- **Unit tests:**
  - Verify `AVAudioUnitEQ` band parameter mapping from `AudioEditRecipe`
    (HPF/LPF/Notch/5-band EQ + bypass state), segment scheduling intervals
    across multiple cuts, and seek/loop boundary clamping.

## Acceptance

- Changing EQ, HPF, LPF, Notch, Gain, or A/B Bypass updates audible playback in
  real time without clicking, restarting from 0, or crashing.
- Playback skips deleted interior ranges smoothly and respects selection loop
  boundaries.
- Leaving `AudioEditorView` cleanly stops the editor engine, invalidates timers,
  and restores prior `AudioEngine` capture state.

## Notes

- Reuse the `.common` `RunLoop` timer pattern and `OSAllocatedUnfairLock`
  thread-safety guards established in `AudioPlayerManager.swift`.
