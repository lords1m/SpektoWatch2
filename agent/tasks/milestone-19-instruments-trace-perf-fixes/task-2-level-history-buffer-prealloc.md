# Task 2: LevelHistoryView Buffer Pre-allocation

Status: completed
Created: 2026-05-29
Priority: P1

## Problem

The 2026-05-29 trace shows **91 samples** of
`specialized _ArrayBuffer._consumeAndCreateNew(bufferIsUnique:
minimumCapacity:growForAppend:)` — Swift's array growth-and-copy routine.

Sources traced back to:

| Frame | Samples |
|-------|---------|
| `closure #1 in closure #1 in closure #1 in LevelHistoryView.body.getter` | 4 |
| `LevelHistoryView.updateLevelBuffer(level:)` | 1 |
| `closure #2 in LevelHistoryView.body.getter` | 1 |
| `LiveAcousticState.currentSpectrogramData.setter` | 1 |
| `closure #1 in LevelHistoryWidget.body.getter` | 1 |

`updateLevelBuffer` appends a new `Float` value on every audio callback
(~100 Hz). The array doubles whenever it exceeds capacity. On a buffer
that cycles continuously this means frequent large copies and heavy
allocator pressure.

Additionally, `LevelHistoryView.body.getter` rebuilds a `Path` from the
full level buffer on every audio-callback-triggered render — the 38-sample
hot closure includes `Path.withMutableBuffer` and the array growth above.

## Acceptance

- The level-history buffer in `LevelHistoryView` (and `LevelHistoryWidget`)
  is initialised with `reserveCapacity(maxSamples)` where `maxSamples`
  matches the display window (e.g. 300 for a 3-second / 100 Hz window).
- No `_consumeAndCreateNew` call is triggered by `updateLevelBuffer` in a
  re-trace once the buffer has reached its steady-state size.
- The `Path` in `LevelHistoryView.body.getter` is not rebuilt on every
  audio frame; it is recomputed only when the buffer contents change
  (`.equatable()` or manual `Equatable` conformance on the buffer model).
- iOS build succeeds; existing level-history display tests pass.

## Implementation notes

- Find the buffer declaration in `LevelHistoryView` (likely a `@State var
  levels: [Float] = []` or equivalent in `LiveAcousticState`). Add
  `levels.reserveCapacity(maxSamples)` in `init` or `onAppear`.
- Consider replacing the raw `[Float]` with a fixed-capacity ring buffer
  (`RingBuffer<Float>` already exists in the watch target — port or reuse).
  A ring buffer eliminates the append / removeFirst pattern entirely.
- For the `Path` rebuild: extract a `LevelHistoryPath` value type
  (`Equatable`) and use `.equatable()` on the drawing sub-view, so SwiftUI
  skips body re-evaluation when the path data hasn't changed.
- `LiveAcousticState.currentSpectrogramData.setter` also triggers array
  growth — check if the spectrogram data array also needs `reserveCapacity`
  in `SpectrogramData`.

Milestone: `milestone-19-instruments-trace-perf-fixes`
Source: 2026-05-29 Instruments trace — 91 _consumeAndCreateNew samples
