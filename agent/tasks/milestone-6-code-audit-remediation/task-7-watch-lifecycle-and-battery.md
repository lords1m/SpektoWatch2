# Task 7: Watch Lifecycle & Battery

Status: completed
Created: 2026-05-18
Updated: 2026-05-19
Milestone: `milestone-6-code-audit-remediation`

## Status Summary

| Sub-item | Source finding | Result |
|---|---|---|
| 1. Stop audio engine on background / wrist drop | Audit #31 (High) | **LANDED** — `WatchAudioEngine.swift:399-440`, `SpektoWatchApp.swift:24-37` |
| 2. (Folded from Task 3) Coalesce main-thread hop per audio callback | Audit #39 (Medium) | **LANDED** — `WatchAudioEngine.swift:50-62, 327-355` (5 Hz coalescing via `OSAllocatedUnfairLock`) |
| 3. (Folded from Task 3) `frames.removeFirst()` O(n) per frame | Audit #32 (Medium) | **LANDED** — new `Shared/RingBuffer.swift` used by `WatchSpectrogramView` and `WatchSpectrogramWidget` |

All three sub-items landed. No deferrals.

## What Landed

### `SpektoWatch Watch App/WatchAudioEngine.swift` — runtime-session and scene-phase handling

Both `extendedRuntimeSession(_:didInvalidateWith:)` and `extendedRuntimeSessionWillExpire(_:)` now call `stopRecording()` when `isRecording` is true. Previously these just printed — when the session expired (~2 min self-recorded session limit on watchOS), the audio tap kept running with no session backing it, draining battery silently.

Added `handleSceneBackgrounded()` for the SwiftUI scene observer to call. It refuses to stop the engine when a `WKExtendedRuntimeSession` is in the `.running` state — that's the system intentionally keeping the audio tap alive, and killing it from a wrist-drop would defeat the entire watch recording feature. Outside of that window (e.g., session was rejected, expired, or the user backgrounded without recording yet) the engine stops.

### `SpektoWatch Watch App/SpektoWatchApp.swift` — scenePhase observer

Added `@Environment(\.scenePhase)` and a `.onChange(of: scenePhase)` modifier on the `WindowGroup`. On `.background`, calls `audioEngine.handleSceneBackgrounded()`. Per the audit, this does NOT auto-resume on `.active` — the user must explicitly restart.

### `SpektoWatch Watch App/WatchAudioEngine.swift` — live-data flush coalescing

Added `liveDataLock` (`OSAllocatedUnfairLock`), `pendingLiveData`, `isLiveDataFlushScheduled`, and a 200 ms flush interval. `processAudioBuffer` now calls `scheduleLiveDataFlush(data)` instead of `DispatchQueue.main.async { self.currentSpectrogramData = data; ... }`. The flush is scheduled at most once per 200 ms; subsequent frames overwrite `pendingLiveData` and drop without scheduling another flush. On main, `flushPendingLiveData` copies the latest data into the two `@Published` properties.

Net effect: instead of ~11 main-thread hops per second each carrying a 1024-element `[Float]` copy, the watch UI gets ~5 updates per second. Imperceptible visually, measurable in battery telemetry.

### New file: `Shared/RingBuffer.swift`

Generic fixed-capacity FIFO with O(1) append-and-drop-oldest. `inOrder()` returns the contents oldest-first so the existing Canvas rendering loops keep working without restructuring. No external dependency required (the project does not pull in swift-collections).

### `SpektoWatch Watch App/WatchSpectrogramView.swift` and `WatchSpectrogramWidget.swift`

- `frames` storage switched from `[[Float]]` to `RingBuffer<[Float]>(capacity: maxFrames)`.
- `frames.removeFirst()` calls deleted (the ring buffer handles capacity in `append`).
- Canvas iteration now uses `frames.inOrder()` (returns an `[Element]` snapshot).
- `maxFrames` lifted to a `static let` so it can be referenced in the `@State` initializer.

The `inOrder()` snapshot allocation per render is intentional: it makes the consumer safe against concurrent mutation and avoids exposing the ring's internal indexing. At 5 Hz (post-coalescing) with capacity 60 / 40 frames of 1024 floats, this is one allocation per frame at well under main-thread budget. The previous code allocated more on every `removeFirst()` (which copies the tail).

## Out of Scope (unchanged)

- Recording-while-backgrounded via a workout session category (separate future milestone — requires HealthKit entitlement and a different UX).
- Battery telemetry surfaced in-app.

## Verification

Tests cannot be run locally (simulator broken). Verification:

- Manual hardware: start measurement, lower wrist for 30 s, confirm via Console:
  - `[WatchAudioEngine] RuntimeSession will expire` is followed by `[WatchAudioEngine] Stopping...` within a few seconds, OR
  - On scenePhase `.background` (no extended session), the engine stops within 1 s.
- Battery: 10-minute session followed by 10 minutes of wrist-down — battery delta should be dominated by the active session, not by the post-session idle window.
- Manual: open the watch UI during an active recording, confirm the spectrogram still appears live (~5 Hz visual update rate is well above the human perception threshold for a meter display).
- Manual: hold the watch in front of a sweeping-tone source, confirm the spectrogram visibly scrolls without flicker (ring-buffer correctness check — wrong ordering would manifest as repeated columns or visual jumps).

## Audit References

#31 (landed), #32 (landed, folded from Task 3), #39 (landed, folded from Task 3)

## Objective

Stop the watch audio engine when the user lowers their wrist or the app
backgrounds outside of a valid `WKExtendedRuntimeSession` window.
Currently the tap can keep running after the session is invalidated,
draining battery indefinitely.

## Scope

1. **High — Watch audio engine never stopped on background** —
   `SpektoWatch Watch App/WatchAudioEngine.swift`. Observe
   `scenePhase` (or `WKExtensionDelegate.applicationWillResignActive`
   on older watchOS) and call `stopRecording()` when:
   - `scenePhase == .background` AND no `WKExtendedRuntimeSession` is
     currently `.running`, OR
   - The `WKExtendedRuntimeSession` delegate reports
     `expirationHandler` / invalidation.

   Document the lifecycle in code comments at the top of
   `WatchAudioEngine.swift`. Resume on `.active` only if the user had
   recording in progress and explicitly requested resume (do NOT auto-
   resume; the user may have lowered the wrist to deliberately pause).

## Out of Scope

- Recording-while-backgrounded via a workout session category (separate
  future milestone — requires HealthKit entitlement and a different UX).
- Battery telemetry surfaced in-app.

## Verification

- Manual hardware: start measurement, lower wrist for 30 s, confirm via
  Console that the audio tap is removed within 5 s of going inactive.
- Battery: 10-minute session followed by 10 minutes of wrist-down,
  confirm battery delta is dominated by the active session.
- Confirm the `WKExtendedRuntimeSession` is invalidated cleanly (no
  Console errors).

## Audit References

#31
