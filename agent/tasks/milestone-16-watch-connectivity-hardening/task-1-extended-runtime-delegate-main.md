# Task 1: Extended Runtime Delegate on Main

Status: completed
Created: 2026-05-25
Completed: 2026-05-25

## Outcome

All four sub-items landed in
`SpektoWatch Watch App/WatchAudioEngine.swift`.

- **Sub-1**: `extendedRuntimeSession(_:didInvalidateWith:)` body wrapped
  in `DispatchQueue.main.async { [weak self] in ... }`. `self.session = nil`
  moved inside the async block so it too runs on main.
- **Sub-2**: `extendedRuntimeSessionWillExpire(_:)` body wrapped in
  `DispatchQueue.main.async { [weak self] in ... }`.
- **Sub-3 (audit)**: Scene-phase entry point `handleSceneBackgrounded()`
  is called from SwiftUI's `scenePhase` observer — main, safe. The two
  `@objc` notification handlers (`handleStartRecording`,
  `handleStopRecording`) are safe because `WatchConnectivityManager`
  already wraps all command notification posts in
  `DispatchQueue.main.async` (verified in
  `Shared/WatchConnectivityManager.swift` lines 241/250). No other
  delegate-shaped entry points found touching `@Published` state off
  main.
- **Sub-4**: `dispatchPrecondition(condition: .onQueue(.main))` added at
  the top of `stopRecording()`. Consequentially, the internal
  `DispatchQueue.main.async { isRecording = false; transition() }` block
  was flattened to direct calls — they are now synchronous since the
  precondition guarantees we're already on main.

Watch build: `BUILD SUCCEEDED` (no errors, only pre-existing icon and
cblas_sgemv deprecation warnings).

## Hardware acceptance pending

Paired-device test: extended-runtime session start → expire → invalidate
cycles; confirm `isRecording` and `session` are always mutated on main
and no concurrent state tear occurs.

Milestone: `milestone-16-watch-connectivity-hardening`
Source: WA-1 Critical — `agent/reports/2026-05-24-code-review-synthesis.md`
