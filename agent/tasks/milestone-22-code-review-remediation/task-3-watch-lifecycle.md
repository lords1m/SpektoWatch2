# Task 3: Watch Lifecycle & Configuration

Status: pending
Created: 2026-11-24
Milestone: `milestone-22-code-review-remediation`
Owns: WL-1 … WL-7
Blocked partly by: milestone decision **Q1** (`WKWatchOnly`)

## Goal

Watch recordings keep running in the background, survive crashes, release
the mic when they should, and the complication/level graph show real data.

## Steps

1. **WL-1 — background mode.** Declare `WKBackgroundModes` in
   `Watch-Info.plist` for the runtime mechanism the app relies on. Verify
   against current Apple docs which option permits continuous microphone
   capture with the screen off (the `audio` background mode vs. a
   `WKExtendedRuntimeSession` type) and pick one the App Review guidelines
   allow for a sound level meter. Also confirm the plist is actually the
   one wired in `project.pbxproj` (`INFOPLIST_FILE`) — there is also a root
   `SpektoWatch-Watch-App-Info.plist`. In `didInvalidateWith`, distinguish
   start failure (`error != nil` before `extendedRuntimeSessionDidStart`) from
   expiry: on start failure keep recording in foreground and show a warning
   instead of stopping.
2. **WL-4 — session identity.** Guard every `WKExtendedRuntimeSessionDelegate`
   callback with `session === self.session`.
3. **WL-2 — crash-safe catalog.** `WatchRecordingStore.beginRecording(id:)`
   writes a provisional entry (`state: .inProgress`) atomically before the
   engine starts. On launch, `.inProgress` entries / uncatalogued pairs are
   **recovered** (finalize `.caf` via `AVAudioFile` re-open, `.swr` via
   DL-4 reader recovery) and marked `.local`, not deleted. Delete only files
   that are both uncatalogued and unreadable.
4. **WL-5 — background stop.** When stop is triggered by `willExpire`,
   invalidation, or scene `.background`, fully tear down capture (remove tap,
   stop engine, deactivate session); restart live monitoring on `.active`.
5. **WL-6 — `.auto` source freshness.** On each phone frame, (re)arm a single
   `DispatchWorkItem` at `lastPhoneFrame + 2 s` that re-evaluates the source
   and falls back to the watch mic; create `phoneSpectrogramSubscription`
   only when nil.
6. **WL-3 — complication feed (after Q1).** Write `ComplicationSharedKeys` +
   `updatedAt` from the watch engine's `flushPendingLiveData` (throttled ≤ 1/min,
   plus on stop) and call `WidgetCenter.shared.reloadTimelines` sparingly.
   Views show "—" with stale styling when `now − updatedAt > 5 min` and drop
   the "LIVE" label. If Q1 = companion app, remove `WKWatchOnly` instead and
   keep the phone feed as a second writer.
7. **WL-7 — level graph.** Use 20…120 dB SPL (shared constant with iOS
   `LAFGraphView`); derive the time axis from frame timestamps, not a fixed
   46 ms. Same fix in `WatchSpectrogramView`.

## Regression tests (SpektoWatchTests)

- `WatchRecordingStoreTests`: in-progress entry + files on launch → recovered,
  not deleted (WL-2).
- `WatchAudioEngineTests`: invalidation from an old session object doesn't stop
  the current recording (WL-4); stale phone source falls back after 2 s with
  no new events (WL-6).
- Value-mapping test for level graph range (WL-7).

## Acceptance

Hardware (task-8): 30-min wrist-down background recording; force-quit
mid-recording → recording recovered; complication updates without phone.
