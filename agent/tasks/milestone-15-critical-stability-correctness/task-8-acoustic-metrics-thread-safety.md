# Task 8: `AcousticMetricsCalculator` Thread Safety

Status: completed
Created: 2026-05-23
Completed: 2026-05-24
Milestone: `milestone-15-critical-stability-correctness`
Source: 2026-05-23 code review — DSP M2

## Goal

`AcousticMetricsCalculator.updateMetrics` runs on the audio thread
(called from `AudioEngine.processFFTFrame`). `reset()` is called from
main (via `resetMetrics()` which dispatches main). Both mutate the
unprotected energy accumulators (`lafEnergy`, `laeqAccumulator`,
percentile histogram, etc.) without any synchronization.

This is a latent race: a concurrent `reset()` mid-`updateMetrics`
produces corrupt accumulator state (mixed-epoch energy values) and
torn Double writes on 32-bit platforms (watchOS hardware).

## Scope

### Sub-1: Add internal lock

Add a `private let lock = OSAllocatedUnfairLock()` to
`AcousticMetricsCalculator`. Wrap `updateMetrics(...)` and
`reset()` bodies in `lock.withLockUnchecked { ... }`. The lock is
held only for the duration of the accumulator update — it does not
need to cover the FFT or anything outside the calculator's own
state.

### Sub-2: Verify no nested-lock hazards

`updateMetrics` should not call back into `AudioEngine` or any
other lock-acquiring code while holding its own lock. Inspect the
implementation: it should be purely numeric/local state mutation.

If `updateMetrics` posts notifications or publishes via Combine,
those must be unlocked first (release the lock, then publish).

### Sub-3: Document the contract

Add a doc comment to the public API stating:
- `updateMetrics(...)` is real-time-safe and may be called from
  the audio thread.
- `reset()` may be called from any thread; the lock arbitrates.
- The lock is `OSAllocatedUnfairLock` to avoid priority-inversion
  on the render thread.

## Acceptance

- [ ] `AcousticMetricsCalculator` holds an `OSAllocatedUnfairLock`
  protecting all mutable state.
- [ ] `updateMetrics` and `reset` acquire the lock for the duration
  of their state mutations.
- [ ] No nested lock acquisition: the lock is not held while calling
  out to `AudioEngine`, `Combine`, or any other subsystem.
- [ ] New stress test in `SpektoWatch2Tests/AcousticMetricsCalculatorTests.swift`:
  spawn a background task that calls `updateMetrics` in a tight loop
  with realistic inputs; concurrently call `reset()` from the test
  thread; assert no crash, no torn state (post-reset accumulator
  values are coherent — either fully old or fully zero, never
  mixed).
- [ ] No regression on existing tests.
- [ ] Audio-thread latency profile unchanged (the lock is unfair +
  uncontended on the render thread, cost is sub-microsecond).

## Files

- `SpektoWatch2/Managers/AcousticMetricsCalculator.swift`
- New tests in `SpektoWatch2Tests/AcousticMetricsCalculatorTests.swift`
  (or extension of existing test file)

## Verification

- iOS + watchOS builds green.
- New stress test passes.
- Manual: long-running recording with periodic `resetMetrics` taps
  via the UI does not produce visibly wrong Leq/peak values.

## Notes

### Sub-items completed

| ID | Description | Status |
|----|-------------|--------|
| AE-1 | `AcousticMetricsCalculator` `OSAllocatedUnfairLock` | **Done** |
| AE-2 | `audioFileWriter` / `measurementWriter` lock + swap-then-close | **Done** |
| AE-3 | `RecordingCoordinator` `@Published` flag mirrors for audio thread | **Done** |
| AE-4 | `updateProcessingSampleRateIfNeeded` malloc on audio thread | **Deferred** — async-dispatch fix with re-entry guard is non-trivial; deferred to a dedicated backlog task to avoid regression |
| AE-5 | Logger / `os_log` removed from audio hot path; write errors via `lastWriteErrorLock` drained on main | **Done** |
| AE-6 | Histogram extended to 2701 bins (−130 to +140 dB) with clamping | **Done** |
| AE-7 | `fftEnergyScratch` + `lcPeakScratch` pre-allocated in `applyFFTConfiguration` / `setBlockSize` | **Done** |

### Lock design rationale

`OSAllocatedUnfairLock` (not `NSLock`/`DispatchQueue`) chosen because:
- Uncontended acquisition is sub-microsecond (avoids measurable latency on the 23 ms audio render budget).
- No priority-inversion risk on the real-time render thread (unlike `NSLock` which can yield).
- `withLockUnchecked` used on the audio thread to skip the ownership-thread assertion overhead (safe because no callout is made under the lock — pure numeric mutation).

### Stress test

`SpektoWatch2Tests/AcousticMetricsCalculatorTests.swift` covers:
- `testConcurrentUpdateAndResetDoesNotCrash`: 20 × 500-frame burst from a background `Task` interleaved with `reset()` + `getStatistics()` on the test thread. Asserts no NaN/infinity in stats post-reset (torn Double write would manifest here).
- `testTwoConcurrentUpdatersDoNotCrash`: two independent `Task.detached` loops each doing 1 000 `updateMetrics` calls simultaneously. No crash required.
- Four functional correctness tests (floor, monotonicity, min≤max, post-reset coherence, `getStatistics` consistency, LAF5 ≥ LAF95).

## Out of scope

- Refactoring the energy accumulator math.
- Adding new metrics (M14 task-3 territory for per-band Leq).
- Migrating to a `Sendable` value-type calculator (would require
  reworking all callers).
- AE-4 (`updateProcessingSampleRateIfNeeded` malloc on audio thread) — deferred, see notes above.
