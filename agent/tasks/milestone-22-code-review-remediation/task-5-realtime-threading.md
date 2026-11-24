# Task 5: Real-Time & Threading Safety

Status: code_complete (pending macOS build + simulator tests)
Created: 2026-11-24
Milestone: `milestone-22-code-review-remediation`
Owns: RT-1 … RT-8

## Goal

No data races between render/background threads and main; no allocations,
locks that can block, ObjC dispatch, or logging on the audio render thread.

## Steps

1. **RT-1 — pipeline reconfiguration.** Make `ProcessingPipeline` immutable per
   FFT size. Main builds a new pipeline and publishes it through a single
   atomic slot (`OSAllocatedUnfairLock<ProcessingPipeline?>` *try-lock* swap or
   `ManagedAtomic` pointer). The render thread picks up the new instance at the
   top of a frame; the old one is released on a non-RT queue (hand back via
   SPSC "graveyard" ring). Remove `resetScratch` from main entirely. The same
   mechanism handles sample-rate-triggered `FFTProcessor` rebuilds (RT-5).
2. **RT-5 — RT-safe writer & frame path.**
   - Replace `RealtimeAudioFileWriter`'s locks + `DispatchQueue.async` with a
     preallocated SPSC ring of `AVAudioPCMBuffer`s drained by a writer thread;
     count drops atomically, log from the writer thread.
   - Ensure the writer's last reference is dropped off the render thread.
   - Preallocate per-frame `metricKeys`, level storage (fixed struct instead of
     `[String: Float]`), smoothing/bandstop scratch; make histogram percentile
     scans incremental or run them on the publish (UI) cadence, not per frame.
3. **RT-4 — publish on main.** `spectrogramSubject` consumers: add
   `.receive(on: DispatchQueue.main)` in `WaterfallView` (and audit every
   `.onReceive` of engine publishers via grep).
4. **RT-2 / RT-3 / RT-7 — HighEndSpectrogramAdapter.**
   - Introduce `Geometry { bins, columns, generation }` snapshotted under the
     lock once per incoming frame; background work uses only the snapshot and
     its own scratch.
   - All geometry changes (incl. sample-rate-driven column changes) are
     scheduled on main; background frames with a stale `generation` are dropped.
   - Texture writes go to a triple-buffered staging `MTLBuffer` and are blitted
     in the command buffer (or ring of textures), so no `replace` races in-flight GPU reads.
5. **RT-6 — watch tap.** Preallocate scratch in `WatchAudioEngine`; move
   `AVAudioFile` writes to a serial queue fed by a buffer ring; snapshot
   `gain`/`recordingStartDate` via an `OSAllocatedUnfairLock` read.
6. **RT-8 — actor isolation.** Make `PlaybackAnalyzer.processSamples`
   `nonisolated` with its own lock, or hop to main explicitly. Turn on
   `SWIFT_STRICT_CONCURRENCY = complete` warnings for the app target and fix
   what surfaces in touched files.

## Regression tests

- `ProcessingPipelineConcurrencyTests`: hammer FFT size changes while a
  background loop calls `computeFrame` (run under TSan in CI scheme).
- `HighEndSpectrogramAdapterTests`: resolution change between frames → no
  crash, stale-generation frames dropped.
- Enable Thread Sanitizer for `SpektoWatch2Tests` in one test-plan
  configuration.

## Acceptance

TSan-clean test run; Instruments "Audio" / System Trace shows no allocations
or lock waits on the render thread during live + recording (task-8).
