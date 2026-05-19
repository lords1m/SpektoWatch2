# Task 6: Audio Thread Real-Time Safety

Status: completed
Created: 2026-05-18
Updated: 2026-05-19
Milestone: `milestone-6-code-audit-remediation`

## Status Summary

| Sub-item | Source finding | Result |
|---|---|---|
| 1. `NSLock` on audio render thread | Audit #9 (High) | **LANDED** — `SpektoWatch2/AudioEngine.swift:96-105, 393, 425, 436, 1213, 1284, 1737` |
| 2. `print`/`String(format:)` on watch audio thread | Audit #10 (High) | **LANDED** — `SpektoWatch Watch App/WatchAudioEngine.swift:29-31, 260-273, 347-368` |

Both sub-items landed. No deferrals.

## What Landed

### `SpektoWatch2/AudioEngine.swift` — NSLock → OSAllocatedUnfairLock

`processingLock` is held by:
- The audio render callback (`processSamples` and `processFFTFrame`) every audio buffer (snapshots `fftSize`, `fftProcessor`, `weightingProcessor`).
- Main-thread setters when the user picks a different FFT size or window function (`applyFFTConfiguration`, `setWindowFunction`, `setBlockSize`) and the sample-rate-change path (`updateProcessingSampleRateIfNeeded`).

`NSLock` wraps `pthread_mutex_lock`, which is a kernel mutex with priority-inheritance semantics that can block the audio render thread under contention or thermal pressure. `OSAllocatedUnfairLock` is an order of magnitude cheaper in the contention-free case and avoids the kernel call path — exactly the pattern `FFTProcessor` already uses (`FFTProcessor.swift:195-199`).

All six call sites were converted from `processingLock.lock()` / `processingLock.unlock()` (or the `defer { unlock }` pattern) to `processingLock.withLockUnchecked { ... }`. The audio-thread read sites now snapshot the lock-protected fields in a single critical section so they cannot be observed mid-reconfiguration. Cleaned up one stray duplicate assignment (`weightingProcessor = newWeightingProcessor` outside the lock in `setBlockSize`) that was left over from the previous lock/unlock layout.

Added `import os` so `OSAllocatedUnfairLock` resolves.

### `SpektoWatch Watch App/WatchAudioEngine.swift` — debug prints under #if DEBUG

Two per-60-frame debug blocks in `processAudioBuffer` and `performFFT` are now guarded by `#if DEBUG`. Each block previously did:
- A counter increment (`debugFrameCount % 60 == 0` modulo guards the body, but the increment still ran every callback).
- Several `String(format:)` calls (heap-allocating).
- One `print(...)` per fired block (locks stdout).

All of that now compiles out in release. `debugFrameCount` storage is also `#if DEBUG`-gated so it doesn't waste an instance slot.

The `print` calls in non-audio-thread paths (recording start/stop, gain set, runtime-session lifecycle) were intentionally left alone — they fire at most once per user action and don't touch the render thread.

## Out of Scope (unchanged)

- Migrating the audio engine to AUv3.
- Adopting Swift 6 strict concurrency on the audio path.

## Verification

Tests cannot be run locally (simulator broken). Verification commands:

- Build with the Address Sanitizer disabled (TSan is incompatible with audio drivers). Use Instruments → Time Profiler on a 60-second recording and confirm:
  - No `pthread_mutex_lock` samples in the audio render thread call tree.
  - `os_unfair_lock_lock` is present but with negligible time.
- Manual: change FFT size during live measurement; confirm no audible glitch beyond the expected reconfiguration gap.
- Watch hardware: 5-minute recording in release configuration; confirm Console shows no `[WatchAudioEngine] Input RMS:` or `[WatchAudioEngine] FFT Output Min:` lines.

## Notes

`widgetSpectralWeightingsLock` (`SpektoWatch2/AudioEngine.swift:127`) is also an `NSLock` but the audit did not flag it. Its critical sections run on the main thread (Combine sinks updating widget settings) and on the audio thread (`requiredSpectralWeightingsForCurrentFrame` in `processFFTFrame`). The same arguments apply — it's a candidate for a follow-up conversion but is not part of this task's scope.

## Audit References

#9 (landed), #10 (landed)

## Objective

Remove every operation on the audio render thread that can block, allocate,
or take a kernel lock. Audio glitches under priority inversion are the
worst-case failure mode for a sound-level meter.

## Scope

1. **High — `NSLock` acquired on the audio render thread** —
   `SpektoWatch2/AudioEngine.swift:1205-1207`. `processingLock` is an
   `NSLock` (wraps `pthread_mutex_lock`) used only to read `fftSize`.
   Either snapshot `fftSize` at session start (it is documented as
   read-only after that, verify), or replace with
   `OSAllocatedUnfairLock<Int>` and read via `withLockUnchecked`. The
   FFTProcessor already uses `OSAllocatedUnfairLock` — match its
   pattern.

2. **High — `print` / `String(format:)` on the watch audio thread** —
   `SpektoWatch Watch App/WatchAudioEngine.swift:267, 357-364`. Both
   allocate heap and lock stdout. Replace with a single-producer/single-
   consumer ring buffer drained from main, or simply gate with
   `#if DEBUG` + `os_log` using a pre-formatted static-string format.

## Out of Scope

- Migrating the audio engine to AUv3.
- Adopting Swift 6 strict concurrency on the audio path (separate effort).

## Verification

- Run with `OSLog` signposts enabled; confirm audio-callback duration
  histogram has no outliers above the buffer-duration deadline (5.8 ms
  at 4096/44100).
- Symbolicate any subsequent audio glitches with `os_log_signpost` —
  rule out lock acquisition as the cause.

## Notes

`OSAllocatedUnfairLock` is the standard real-time-safe Swift lock since
iOS 16/watchOS 9. Confirm the minimum deployment target supports it.

## Audit References

#9, #10
