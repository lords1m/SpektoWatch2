# Task 1: Standalone Activation & Phone-Absent UX

Status: in_progress
Created: 2026-05-30
Milestone: `milestone-21-watch-standalone`

## Progress (2026-05-30)

Code-side landed; on-device verification deferred to [[task-6-acceptance]].

- **Persisted preference.** `PersistenceKeys.Watch.standaloneEnabled`
  (`UserDefaults.standard`, Bool). `WatchAudioEngine.standaloneEnabled` is
  `@Published private(set)`, loaded in `init`, flipped via
  `setStandaloneEnabled(_:)` (persists + re-points the idle live-data source;
  no-op while recording).
- **Phone-independent launch.** `WatchAudioEngine.init` no longer
  unconditionally subscribes to the phone spectrogram: when standalone is the
  saved preference it starts in `.standalone` and skips the subscription, so
  launch never assumes/waits on a present phone.
- **Standalone activation.** `startRecording` transitions to `.standalone`
  (vs `.wearableMic`) when the preference is set; `stopRecording` stays
  `.standalone` (clears live display) instead of reverting to `.companion`, so
  the watch does not silently flip back to phone-master while standalone.
- **User control.** `WatchDashboardView` gains a `standaloneToggle`
  (applewatch/iphone glyph) next to the record button; disabled mid-recording.
  The record button skips `requestWearableRecording{Start,Stop}` phone
  coordination when standalone.
- **No-blocking-wait audit.** `WatchConnectivityManager` send paths all guard
  `WCSession.default.isReachable` and use `sendMessage(replyHandler: nil)`
  fire-and-forget; no `DispatchSemaphore`/`.wait()` anywhere. Phone-absent =>
  sends are skipped, nothing blocks. (Audit clean — no change needed.)

Remaining for this task is hardware verification (folded into task-6):
unpaired/airplane-mode capture renders live with no UI block, and standalone
does not revert to companion.

## Goal

Let the watch operate watch-first without a reachable phone: a real
`standalone` activation path, a launch default that does not assume companion,
and an audit that nothing blocks waiting on the phone.

## Scope

- Wire `WatchOperatingMode.standalone` into `WatchAudioEngine.transition(to:)`
  so it configures the local mic + extended-runtime path (like `wearableMic`)
  but flags recordings for local persistence + later sync.
- Add a user-facing control to enter/leave standalone (settings toggle or a
  watch-first launch affordance). Do not auto-revert to `companion` on
  reachability if the user chose standalone.
- Launch should not assume a present phone: avoid synchronous reachability
  gating of first render.
- Audit `WatchConnectivity` call sites for blocking waits / spinners that hang
  when the phone is absent; make them non-blocking / best-effort.

## Acceptance

- With the phone off/out of range, the watch enters standalone and live
  level + spectrogram render from the watch mic with no UI block.
- Mode does not silently flip back to companion while standalone is active.
- Verified on hardware as part of [[task-6-acceptance]].

## Notes

Preserve the low-bandwidth processed-data rule: standalone never streams raw
audio to the phone. See [[task-5-sync-back]] for deferred file transfer.
