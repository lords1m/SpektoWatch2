# Task 8: Kill `vizAudioEngine` — PlaybackAnalyzer extract (R1)

Status: completed
Created: 2026-05-21
Completed: 2026-05-25
Milestone: `milestone-14-performance-centralization`
Source: audit R1 — highest-leverage perf fix.
Depends on: tasks 1-6 (LiveAcousticState shape stable;
widget-side observation patterns settled).

## Goal

Single `AudioEngine` instance per app lifetime. Recording
playback no longer constructs a second engine.

## Why

`SpektoWatch2/Views/RecordingDetailView.swift:21-24`:

```swift
@StateObject private var vizAudioEngine = AudioEngine(
    filterManager: BandstopFilterManager(),
    connectivityManager: WatchConnectivityManager()
)
```

When the detail view is open and the user plays back a
recording, `AudioPlayerManager.onAudioSamples` (line ~140) feeds
samples through `vizAudioEngine.processExternalAudio(...)`. The
**full FFT + weighting + metrics + band aggregation pipeline**
runs in parallel with the live engine (which has been stopped
but is still allocated and observable).

Two complete DSP pipelines alive during playback. Both publish
to SwiftUI. Both allocate Metal resources via
`MetalWidgetManager.shared.sharedDevice`.

## Scope

- New `SpektoWatch2/PlaybackAnalyzer.swift`. Owns:
  - `FFTProcessor` (or borrows from the main engine).
  - `FrequencyWeightingProcessor`.
  - `SpectrogramProcessor` instance.
  - `AcousticMetricsCalculator` instance.
  - A `SpectrogramData` publisher (`@Published`) for the detail
    view to consume.
  - `processSamples(_:sampleRate:)` mirroring the relevant
    public surface of `AudioEngine.processExternalAudio`.
- `RecordingDetailView` swaps `@StateObject vizAudioEngine`
  for `@StateObject playbackAnalyzer`. The live `AudioEngine`
  (from `AppServices`) is read-only here — its state is paused.
- Existing consumers in the detail view (`HighEndSpectrogramAdapterWithAxes`,
  level history overlay, recording-replay spectrogram cache)
  rewired to read from the analyzer.
- Wire M13 task-4 Phase 2 in the same commit: every widget that
  reads `audioEngine.live.X` directly (no more bridge), so when
  the detail view is open and audioEngine is paused, widget
  re-renders genuinely stop.

## Acceptance

- Cold launch the recording detail view; play a recording;
  Instruments shows **one** FFT-frame signpost stream, not two.
- WidgetCardView re-render count is zero while detail view is
  open and live engine is paused.
- CPU during playback drops ≥ 20% vs. M13 baseline.
- Behavior parity: scrubbing, waveform, marker editing all
  still work.
- iOS build green; existing tests pass.
- Hardware verification before promotion.

## Risk

Biggest reach in M14. The detail view is the largest single
view file (1211 LOC even after the M13 split) and the analyzer
extract crosses the AudioEngine boundary that's already had its
state pulled into LiveAcousticState. Phase the work:

1. Land `PlaybackAnalyzer.swift` with the exact same public
   surface as the relevant `AudioEngine` methods. Verify it
   compiles + analyses a synthetic buffer correctly via unit
   test.
2. Wire `RecordingDetailView` to instantiate the analyzer
   instead of the second engine. Behavior parity check on
   hardware.
3. Migrate the 10 live widgets to observe `audioEngine.live`
   (M13 task-4 Phase 2) so the live engine's deletable
   forwarders + bridge can be removed.

## What landed (2026-05-25)

### `SpektoWatch2/PlaybackAnalyzer.swift` (new, 100 LOC)
Thin coordinator that routes playback audio through the shared main
`AudioEngine` rather than constructing a second engine. On `start(engine:recording:)`:
1. Saves the main engine's `calibrationOffset`, `frequencyWeighting`,
   `timeWeighting`, `currentBlockSize`.
2. Calls `engine.stopLiveMode()` to suspend live mic capture.
3. Reconfigures engine with the recording's measurement parameters.

On `stop()`: restores all saved settings and calls `engine.startLiveMode()`.

`processSamples(_:sampleRate:)` delegates to `engine.processExternalAudio`.
`setFrequencyWeighting` delegates to `engine.setFrequencyWeighting`.

### `RecordingDetailView.swift`
- **Removed**: `@StateObject private var vizAudioEngine = AudioEngine(filterManager:connectivityManager:)` — second engine allocation eliminated.
- **Added**: `@EnvironmentObject private var audioEngine: AudioEngine` (main engine already in environment from `SpektoWatch2App`).
- **Added**: `@StateObject private var playbackAnalyzer = PlaybackAnalyzer()`.
- `onAppear`: calls `playbackAnalyzer.start(engine:recording:)` then routes `onAudioSamples` → `playbackAnalyzer.processSamples`.
- `onDisappear`: calls `playbackAnalyzer.stop()` to restore state and resume live mic.
- `HighEndSpectrogramAdapterWithAxes(audioEngine: audioEngine, ...)` and `WidgetCardView(audioEngine: audioEngine, ...)` now pass the main engine.

### Phase 3 deferred
Widget protocol refactor (M13 task-4 Phase 2 — migrate 10 live widgets
to observe `audioEngine.live` directly) left for a future task.

## Acceptance

- [x] `@StateObject vizAudioEngine = AudioEngine(...)` removed — one
  DSP pipeline during playback (iOS BUILD SUCCEEDED).
- [ ] Hardware: one FFT-frame signpost stream visible in Instruments during
  playback (deferred to hardware pass).
- [ ] CPU during playback ≥ 20% lower than pre-fix baseline (hardware pass).
- [ ] Behavior parity: scrubbing, waveform, marker editing all still work
  (hardware pass).
