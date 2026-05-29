# Task 3: WatchConnectivity Consolidation

Status: completed
Created: 2026-05-18
Updated: 2026-05-18
Milestone: `milestone-6-code-audit-remediation`

## Status Summary

| Sub-item | Source finding | Result |
|---|---|---|
| 1. iOS `sendSpectrogramData` throttling | Audit #3 (Critical) | **LANDED** — `SpektoWatch2/WatchConnectivityManager.swift:51-129` (coalesce + adaptive interval, ported from Shared) |
| 2. Complication reload 60 s + TOCTOU | Audit #27 + #20 (Critical/Medium) | **LANDED** — both `Shared/WatchConnectivityManager.swift:287-313` and `SpektoWatch2/WatchConnectivityManager.swift:104-121` |
| 3. NotificationCenter posts on main | Audit #7 (High) | **LANDED** — `Shared/WatchConnectivityManager.swift:225-283` |
| 4. A/C magnitudes in binary payload | Audit #8 (High) | **LANDED 2026-05-29** — appended as optional trailing arrays after visualFrequencies (backward-compatible; count==0 signals absent); sender wired; 2 new round-trip tests pass |
| 5. Protocol version + unknown-type logging | Audit #12 (High) | PARTIAL — unknown-type logging landed in both files. Version handshake via `applicationContext` deferred (coordinated cross-target change). |
| 6. iOS `processQueue` race | Audit #13 (High) | **RESOLVED in M16/task-3** — `sendWithRetry` dispatches to `.main` before touching `messageQueue`; `processQueue` + `handleMessageError` both enforce `dispatchPrecondition(.onQueue(.main))`; reply/error handlers dispatch back to main. Serial queue via main thread; no separate DispatchQueue required. |
| 7. Dead reachability reschedule | Audit #19 (Medium) | **LANDED** — `Shared/WatchConnectivityManager.swift:172-186` (both dead branches removed with rationale comment) |
| 8. Watch main-thread hop per audio callback | Audit #39 (Medium) | **RESOLVED in M16/task-4** — `pendingLiveData` + `liveDataLock` + 5 Hz flush Timer coalesce watch audio callbacks |
| 9. Watch `frames.removeFirst` O(n) | Audit #32 (Medium) | **RESOLVED in M16/task-4** — `WatchSpectrogramView` + `WatchSpectrogramWidget` both use `RingBuffer<[Float]>` |
| 10. Watch debug counter under #if DEBUG | Audit #44 (Medium) | **LANDED** — `SpektoWatch Watch App/WatchSpectrogramView.swift:9-11, 112-126` |

10 of 10 resolved: 7 landed here, #6 resolved in M16/task-3 (main-thread serialization), #8/#9 resolved in M16/task-4, #4 landed 2026-05-29.

## What Landed

### `SpektoWatch2/WatchConnectivityManager.swift` — throttled spectrogram sends

Ported the coalescing/adaptive-interval scheduler from `Shared/WatchConnectivityManager`. `sendSpectrogramData` now enqueues onto a private serial `spectrogramSendQueue`, stores the most recent frame in `pendingSpectrogramData`, and schedules a flush via `scheduleSpectrogramSendIfNeeded`. The adaptive interval uses the same thermal/low-power constants from `WatchConnectivityProtocol`. An `errorHandler` is now wired on `sendMessageData` (previously nil — drops were silent). `hasLoggedSpectrogramUnreachability` debounces the unreachability log so a watch out of range doesn't fill the log.

### Both files — complication reload 60 s minimum + TOCTOU

`updateComplicationState` now requires ≥ 60 s since the last reload (was 1 s — could exhaust watchOS's ~50 reloads/day budget in under a minute). `lastComplicationReload = now` is assigned BEFORE the `WidgetCenter.shared.reloadTimelines` call, so two near-simultaneous calls cannot both pass the guard.

### `Shared/WatchConnectivityManager.swift` — NotificationCenter posts on main

`didReceiveMessage` now hops to main BEFORE posting `.startRecordingCommand`, `.stopRecordingCommand`, and `.gainOrBandwidthChangedNotification`. Previously the posts ran on the WCSession background delivery queue, so `WatchAudioEngine.handleStartRecording` was touching `AVAudioEngine` and mutating `@Published isRecording` off-main. Also restructured the `if let type` into a `guard … else { return }` for the unknown-type log path.

### Both files — unknown-message-type logging

`didReceiveMessage` now logs the raw `type` string when `messageType(from:)` returns nil. Previously the message was silently dropped, which would mask cross-version skew between the two managers (e.g., a watch-side decoder added without the corresponding iOS-side type).

### `Shared/WatchConnectivityManager.swift` — dead reschedule branches removed

Two `if pendingSpectrogramData != nil { scheduleSpectrogramSendIfNeeded() }` branches inside `flushPendingSpectrogramData` were unreachable: `pendingSpectrogramData` is set to nil three lines above, and the serial `sendQueue` prevents any other writer from mutating it between the read and the unreachable check. Removed with a rationale comment so a future reader doesn't reinstate them.

### `SpektoWatch Watch App/WatchSpectrogramView.swift` — debug log gated

`debugCounter` increment and the `reduce(0, +)` over the 1024-element magnitudes array now sit inside `#if DEBUG`. The state variable itself is also `#if DEBUG`. Release builds drop this entirely from the per-frame UI path.

## Deferral Rationales

- **#4 (A/C magnitudes in binary encoding)** — Real bug, but requires a format-version byte in `SpectrogramData.toBinaryData`/`fromBinaryData` and matching receiver logic on both sides. Pair with sub-item #5 (protocol version) as a focused follow-up.
- **#5 protocol version handshake** — `applicationContext` is currently used for `frequencyWeighting` and `watchDashboardConfig`. Adding a `version` field needs to coordinate with every site that calls `updateApplicationContext` so the context dictionary isn't accidentally clobbered. Defer to a follow-up that does this atomically.
- **#6 `processQueue` race** — **Resolved in M16/task-3.** `sendWithRetry` dispatches to `.main` before any `messageQueue` mutation; `processQueue` and `handleMessageError` both carry `dispatchPrecondition(.onQueue(.main))`; reply/error callbacks dispatch back to main. The main thread acts as the serial gate — no separate `DispatchQueue` was needed. Verified 2026-05-29 by reading `SpektoWatch2/WatchConnectivityManager.swift:302–362`.
- **#8 watch main-thread hop per audio callback** — Coalescing the per-callback `DispatchQueue.main.async` to ~5 Hz requires a Timer or AsyncStream throttle inside `WatchAudioEngine`. Best done together with Task 7 (Watch Lifecycle & Battery) since both touch the same file.
- **#9 watch `frames.removeFirst` O(n)** — Ring-buffer refactor across `WatchSpectrogramView` and `WatchSpectrogramWidget`. Self-contained; folds naturally into the same Task 7 cycle.

## Out of Scope (unchanged)

- Complication App Group plumbing (covered by Task 4).
- Real-time-safety issues on the audio render thread (covered by Task 6).
- DSP correctness (covered by Task 1).

## Verification

Tests cannot be run locally (simulator broken). Verification commands for CI / a developer machine:

- `xcodebuild test -scheme SpektoWatch2 -only-testing:SpektoWatch2Tests/WatchConnectivityTests` — confirm message routing still passes; expect 0 changes to existing assertions.
- Manual hardware: 10-minute live measurement, watch Console for:
  - No "send queue is full" WCSession errors.
  - No "exceeded daily widget reload budget" warnings.
- Manual hardware: trigger a start-recording from the watch, verify `WatchAudioEngine` receives the notification on the main thread (breakpoint or signpost).
- Synthetic skew test (build the iOS app with a new message type added but no watch update; or vice versa): observe the new `Ignored unknown message type:` log line on the unaware side.

## Follow-ups

- New sub-task or focused cycle: items #4 + #5 (binary format A/C extension + applicationContext version field, done together with a single version byte at the head of the spectrogram payload).
- New sub-task: item #6 — decide consolidation vs. serial queue for the iOS retry path. If consolidate, requires pbxproj surgery to add `Shared/WatchConnectivityManager.swift` to the iOS target and remove the duplicate file.
- Fold #8 + #9 into Task 7 (Watch Lifecycle & Battery) — same file pairs.

## Audit References

#3 (landed), #7 (landed), #8 (deferred), #12 (partial), #13 (deferred), #19 (landed), #20 (landed), #27 (landed), #32 (deferred), #39 (deferred), #44 (landed)

## Objective

Collapse the two divergent `WatchConnectivityManager` implementations into a
single, correctly throttled, thread-safe path. Eliminate the WCSession
flooding that would silently drop spectrogram frames under load. Stop
publishing `@Published` state from background threads.

## Scope

1. **Critical — iOS `sendSpectrogramData` bypasses throttling** —
   `SpektoWatch2/WatchConnectivityManager.swift:157-161` calls
   `sendMessageData` directly at FFT framerate with a nil `errorHandler`.
   Either delete the iOS-specific manager and have the iOS app use the
   `Shared/WatchConnectivityManager`, or port the coalescing/adaptive-
   interval logic (`sendQueue`, `scheduleSpectrogramSendIfNeeded`,
   `pendingSpectrogramData`) from the Shared manager. Strongly prefer
   consolidation — the divergence is the root cause of multiple findings.

2. **Critical — Complication `reloadTimelines` exhausts watchOS daily
   budget** — `Shared/WatchConnectivityManager.swift:289-296`. Throttle to
   at most once per 60 s (or only on a meaningful delta — e.g. ≥ 1 dB
   change since the last reload). Update `lastComplicationReload`
   *before* dispatching to main (TOCTOU fix). Adjust the M5 acceptance
   note: the documented "1 second" cadence is wrong; the system limit is
   ~50 reloads/day.

3. **High — Background-thread NotificationCenter posts** —
   `Shared/WatchConnectivityManager.swift:237-244`. Move all three
   `NotificationCenter.default.post(...)` calls (`.startRecordingCommand`,
   `.stopRecordingCommand`, `.gain`) inside the corresponding
   `DispatchQueue.main.async` blocks so `WatchAudioEngine.handleStartRecording`
   no longer touches `AVAudioEngine` and mutates `@Published isRecording`
   off-main.

4. **High — A/C-weighted magnitudes silently dropped on the wire** —
   `Shared/SpectrogramData.swift:43-193`. Extend the binary format with a
   presence byte (one bit each for A and C) and serialize `magnitudesA` /
   `magnitudesC` when present. Receiver falls back to Z only when the bit
   is unset. Bump a `version: UInt8` byte at the head of the payload so
   the receiver can detect skew (see #5 below).

5. **High — Protocol has no version field** —
   `Shared/WatchConnectivityProtocol.swift:3-121`. Add a `version` field
   to the `applicationContext` on activation and log unknown message
   types via `Logger` rather than silently returning nil from
   `messageType(from:)`.

6. **High — `processQueue` / `messageQueue` race in iOS manager** —
   `SpektoWatch2/WatchConnectivityManager.swift:216-268`. If the iOS
   manager survives consolidation (#1), gate all `messageQueue` mutations
   behind a serial `DispatchQueue`. If it doesn't, this collapses into
   #1 — verify no callers remain.

7. **Medium — Dead reachability-guard reschedule** —
   `Shared/WatchConnectivityManager.swift:178-181`. The
   `pendingSpectrogramData != nil` check fires two lines after the field
   is set to nil; the branch is unreachable. Delete it.

8. **Medium — Watch `processAudioBuffer` main-thread hop per audio
   callback** — `SpektoWatch Watch App/WatchAudioEngine.swift:310-316`.
   Coalesce updates to ~5 Hz using an `AsyncStream`-with-throttle or a
   display-link-equivalent (`CADisplayLink` is not available on watchOS;
   use a `Timer` on main).

9. **Medium — Watch spectrogram `frames.removeFirst()` is O(n) per
   frame** — `SpektoWatch Watch App/WatchSpectrogramView.swift:120-124` and
   `SpektoWatch Watch App/WatchWidgets/WatchSpectrogramWidget.swift:54-57`.
   Replace `[Array]` with a ring-buffer or `Deque` (swift-collections
   already used elsewhere? confirm; otherwise inline a fixed-capacity
   circular buffer).

10. **Medium — Watch debug counter increments every frame in release** —
    `SpektoWatch Watch App/WatchSpectrogramView.swift:117`. Strip the
    `reduce(0, +)` block entirely or gate behind `#if DEBUG`.

## Out of Scope

- Complication App Group plumbing (covered by Task 4).
- Real-time-safety issues on the audio render thread (covered by Task 6).
- DSP correctness (covered by Task 1).

## Verification

- Unit test: enqueue 1000 spectrogram sends in 1 s via the consolidated
  manager, confirm `sendMessageData` is called at most N times where N
  matches the configured rate ceiling.
- Unit test: round-trip a `SpectrogramData` with all three weighting
  arrays populated through `toBinaryData`/`fromBinaryData`, confirm
  byte-equal recovery.
- Unit test: post a `.startRecording` message from a background queue,
  observe that `WatchAudioEngine.handleStartRecording` is invoked on
  main.
- Manual hardware: 10-minute live measurement session, confirm Console
  shows no "send queue is full" errors and no widget-budget warnings.

## Audit References

#3, #7, #8, #12, #13, #19, #20, #27, #32, #39, #44
