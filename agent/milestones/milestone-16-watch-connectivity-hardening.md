# Milestone 16: Watch Connectivity Hardening

Status: completed
Created: 2026-05-25
Completed: 2026-05-25
Priority: medium
Estimated: 1 week

## Goal

Close the watch-app findings from the 2026-05-24 multi-agent code-review
synthesis (`agent/reports/2026-05-24-code-review-synthesis.md`). Binary
acceptance:

1. **WKExtendedRuntimeSession delegate callbacks never mutate
   `isRecording`, `session`, or call `stopRecording()` off the main
   thread.** No race between system-delivered delegate callbacks and
   main-actor reads in `handleSceneBackgrounded` / `startRecording`.
2. **All four complication kinds reload on state change.**
   `LevelCornerWidget` ("SpektoWatchLevelCorner") is included in the
   `complicationWidgetKinds` arrays on both iOS and watch sides.
3. **`WatchConnectivityManager.sendWithRetry` is thread-safe.**
   `messageQueue` and `isProcessingQueue` mutations are guarded — no
   torn reads, no double-send, no double-remove regardless of caller
   thread.
4. **No O(n) history shifts and no per-call `DateFormatter` allocations
   in watch view bodies.** `WatchLevelMeterView` uses `RingBuffer`;
   `WatchSpectrogramView.timeString` reuses a single formatter.
5. **Schema-version mismatches in `SpectrogramData.fromBinaryData` are
   logged.** No silent data loss.

## Why now

M15 closed the iOS-side critical findings (audio-thread safety, export
off-main, calibration parity, persistence durability). The watch app
carries the remaining Critical / High items from the same review:

- **WA-1 (Critical)** — `WKExtendedRuntimeSession` delegate methods read
  `@MainActor` published state and synchronously assign `session = nil`
  off the system-delivered thread.
- **WA-2 (High)** — Corner complication added in M12 task-4d but never
  added to the reload-kinds list; it never refreshes.
- **WA-3 (High)** — iOS-side `WatchConnectivityManager.sendWithRetry`
  mutates `messageQueue` and `isProcessingQueue` from any caller
  thread; `processQueue()` runs on main via reachability callbacks.

Mediums (WA-4 / WA-5) and low (WA-6) bundle naturally because they all
touch the same files and ship together.

## Non-goals

- M17 (SwiftUI lifecycle / performance — UI-1…UI-7) and M18 (test &
  tooling debt — TT-2…TT-9 + coverage gaps). Findings for both are
  already sourced in the review report; they will be planned
  separately.
- Backlog: PE-5…PE-8.
- Hardware acceptance for M15 outcomes 3 (calibration parity) and 4
  (long-recording export). Tracked in the M15 acceptance report.
- App Group entitlement wiring (M6 task-4 remainder, requires Xcode
  Signing & Capabilities + Developer Portal action).

## Tasks

1. task-1-extended-runtime-delegate-main — WA-1
2. task-2-corner-complication-reload — WA-2
3. task-3-send-with-retry-thread-safety — WA-3
4. task-4-watch-view-perf — WA-4 + WA-5
5. task-5-schema-version-logging — WA-6
6. task-6-acceptance — verdicts + cross-cut checks

Source: `agent/reports/2026-05-24-code-review-synthesis.md`
