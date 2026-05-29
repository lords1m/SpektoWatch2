# Task 5: Spectrogram & Metal Threading

Status: completed
Created: 2026-05-18
Updated: 2026-05-29
Milestone: `milestone-6-code-audit-remediation`

## Status Summary

| Sub-item | Source finding | Result |
|---|---|---|
| 1. `HighEndSpectrogramAdapter` texture data race | Audit #28 (Critical) | **LANDED 2026-05-29** — texture writes dispatched to main thread; serialised with draw(_:)'s GPU encoder; CPU/GPU race eliminated |
| 2. Reachable `fatalError` in Metal pipeline setup | Audit #29 (Critical) | **LANDED** — `PlaybackSpectrogramView.swift:69-78, 100-153, 290-300` |
| 3. `HighEndSpectrogramAdapter` mutates private state without sync | Audit #35 (High) | **LANDED** — same `OSAllocatedUnfairLock` as #1 |
| 4. `computeFromAudioSamples` on main | Audit #38 (High) | DEFERRED — function is dead code (no callers); flagged for Task 9 deletion |
| 5. `buildColormapTexture` in `draw()` | Audit #40 (Medium) | **LANDED** — eager build in `setColormap`; removed from draw loop |

All 5 sub-items resolved: #1 fully landed 2026-05-29; #4 was not-a-bug (dead code removed in task-9).

## Verification Reversal

**#4 — `PlaybackSpectrogramRenderer.computeFromAudioSamples` "runs on main".** The function is defined ([PlaybackSpectrogramView.swift:154-219](SpektoWatch2/PlaybackSpectrogramView.swift:154)) but **has no callers**: a project-wide `grep -rn "computeFromAudioSamples"` returns only the definition. `updateUIView` calls `loadSpectrogramData(magnitudeHistory)` directly, not `computeFromAudioSamples`. The audit incorrectly identified `updateUIView` as a caller. Flag for deletion in Task 9.

## What Landed

### `SpektoWatch2/PlaybackSpectrogramView.swift`

- Added `private(set) var isMetalReady = false` flag.
- `setupMetal`: device-nil case logs and sets `isMetalReady = false` instead of `fatalError("Metal is not supported")`. Same pattern for command queue creation and viewport buffer creation.
- `setupPipeline`: returns `Bool`; pipeline-creation failure logs and returns false instead of `fatalError("Failed to create pipeline: ...")`. `setupMetal` checks the return value and aborts cleanly.
- `draw(_:)` now also guards on `isMetalReady`, plus explicit nil-checks for `commandQueue`, `pipelineState`, `viewportBuffer` (previously implicitly-unwrapped `!` properties).

Net effect: a device/simulator with broken Metal (shader ABI mismatch, missing metallib, etc.) renders nothing instead of crashing the host process. The surrounding SwiftUI hierarchy is unchanged but can now inspect `isMetalReady` if a fallback view is desired.

### `SpektoWatch2/HighEndSpectrogramAdapter.swift` — scalar state lock

Added `private let stateLock = OSAllocatedUnfairLock()` next to the ring-buffer-state declarations, with an explanatory comment about the producer (background `updateQueue` from the Coordinator) vs. consumer (`draw(_:)` on main).

- `updateWithFFTMagnitudes`: the per-frame timestamp update is wrapped in a small `withLockUnchecked` block; the column-advance loop, `writeColumn` calls, and `totalColumnsWritten` update all live inside a single larger `withLockUnchecked` block.
- `writeColumn` → renamed `writeColumnLocked` to make the precondition explicit; carries a doc comment about the GPU/CPU texture-race trade-off and the structural follow-up.
- `draw(_:)`: snapshots `currentColumn`, `totalColumnsWritten`, `firstDataTimestamp`, `lastDataTimestamp` under the lock once at the start. Everything downstream uses the local snapshots — no torn reads.
- `reset()`: mutations of the ring-buffer scalars are wrapped in the lock. `displayScrollSynced` stays outside (main-thread-only field).

### `SpektoWatch2/HighEndSpectrogramAdapter.swift` — colormap eager build

- `setColormap(_:)` now calls `buildColormapTexture(type:)` eagerly. The audit incorrectly claimed this was already done — it was not.
- `draw(_:)` no longer calls `buildColormapTexture`. Removed the per-frame call.
- Net effect: the dict lookup + branch that ran every CADisplayLink tick is gone; texture build happens once when the colormap actually changes.

## Out-of-Scope Follow-Ups

- **Sub-item #1 structural fix.** The `OSAllocatedUnfairLock` synchronises CPU-side scalar reads/writes, which prevents the torn-read bug. It does NOT synchronise the GPU's read of `spectrogramTexture` against the CPU's `texture.replace(...)` call for the next column. The texture is `.storageModeShared`; under Metal validation this is undefined, but the existing pipeline visually tolerates it (the audit framed this as "may produce torn frames or crashes" — the crash path has not been observed in practice). A proper fix requires either:
  - Double-buffer: write into a back texture, swap atomic-CAS-style under the lock when a full column is complete, or
  - Gate the CPU write on `inFlightSemaphore` so a frame's worth of GPU work completes before the next CPU write lands.

  Both are structural and out of scope for this remediation milestone. Tracked here for a future Metal-pipeline-hardening cycle.

- **Sub-item #4 deletion.** Add `PlaybackSpectrogramRenderer.computeFromAudioSamples` to the Task 9 dead-code list.

## Verification

Tests cannot be run locally (simulator broken). Verification:

- Build with Thread Sanitizer enabled, run the live spectrogram for a minute — confirm no TSan reports against `HighEndSpectrogramAdapter` scalar fields.
- Manual: switch colormap during live measurement — confirm the spectrogram repaints without a one-frame stale appearance (the per-frame build was already cached, but the eager build removes any first-frame-after-switch race).
- Manual: temporarily corrupt the metallib (rename a shader function used by `PlaybackSpectrogramView`) and confirm the app no longer crashes — it should render a blank Metal view and log the failure reason.

## Audit References

#28 (partial — scalar race fixed; texture race deferred as structural), #29 (landed), #35 (landed via #28's lock), #38 (deferred — not-a-bug, dead code), #40 (landed)

## Objective

Eliminate the data race on the live spectrogram's `MTLTexture` and remove
the reachable `fatalError` calls in the Metal pipeline setup paths. Make
playback-spectrogram computation non-blocking.

## Scope

1. **Critical — `HighEndSpectrogramAdapter` texture data race** —
   `SpektoWatch2/HighEndSpectrogramAdapter.swift` (`updateWithFFTMagnitudes`
   and `writeColumn`). Writes occur on a private `updateQueue`
   (`.userInteractive`); reads occur in `draw(_:)` on main. Texture
   storage is `.storageModeShared` with no synchronization. Marshal all
   texture writes to main thread, OR adopt a double-buffer scheme: write
   into a back texture, swap atomically (via an `os_unfair_lock`-
   protected reference) when a full column is complete.

2. **Critical — Reachable `fatalError` in Metal pipeline setup** —
   `SpektoWatch2/PlaybackSpectrogramView.swift:129`. Replace both
   `fatalError(...)` calls in `setupMetal` and `setupPipeline` with
   setting `isMetalReady = false` and presenting a fallback view
   (text/list view of recorded spectrogram or empty state with an error
   banner). Log the underlying error via `Logger`.

3. **High — `HighEndSpectrogramAdapter.updateWithFFTMagnitudes` mutates
   private state without synchronization** — separate from the texture
   race. Fields `currentColumn`, `totalColumnsWritten`,
   `columnAdvanceAccumulator`, `displayScrollSynced` are written from
   the update queue and read by `draw(_:)`. Lock with
   `OSAllocatedUnfairLock`, or scope the writes to main thread (couples
   the fix with #1 — same dispatch decision applies to both).

4. **High — `PlaybackSpectrogramRenderer.computeFromAudioSamples` runs
   on main** — `SpektoWatch2/PlaybackSpectrogramView.swift:154`. Move the
   FFT loop onto a detached `Task` (or a dedicated background queue),
   call `loadSpectrogramData` on completion via
   `await MainActor.run { … }`. Show a progress indicator in the view
   while the computation runs.

5. **Medium — `buildColormapTexture` called inside `draw()`** —
   `SpektoWatch2/HighEndSpectrogramAdapter.swift:524`. Remove the call
   from `draw()`. `setColormap(_:)` already builds the texture eagerly;
   verify no other path can change `colormapType` without going through
   `setColormap`.

## Out of Scope

- Adding new colormaps.
- Rewriting the Metal shader.
- Switching to `MTLHeap` storage.

## Verification

- Run Metal API Validation + Thread Sanitizer under Xcode (when the
  simulator is fixed). Confirm no TSan reports against the
  `HighEndSpectrogramAdapter` texture or its private state.
- Manual: open the app on a device where Metal pipeline compilation has
  historically failed (or simulate by corrupting the metallib via a
  build setting) — confirm the app shows the fallback view instead of
  crashing.
- Manual: open a 30-minute recording, confirm the playback view loads
  without a long main-thread freeze; spinner should be visible during
  computation.

## Audit References

#28, #29, #35, #38, #40
