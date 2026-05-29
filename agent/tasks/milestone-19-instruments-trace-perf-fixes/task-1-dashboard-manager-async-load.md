# Task 1: Async DashboardManager.loadConfiguration

Status: completed
Created: 2026-05-29
Priority: P0

## Problem

The 2026-05-29 Instruments trace shows a **573 ms confirmed hang** (type:
Hang, Instruments threshold 250 ms) starting at T + 1.583 s. The hang is
on the Main Thread (0x4a7c).

Call stack pinned by profiler:

```
_findStringSwitchCase                          ← AudioWidgetType raw-value switch
AudioWidgetType.init(rawValue:)
WidgetConfiguration.init(from:)
DashboardLayout.init(from:)
DashboardLayoutsState.init(from:)
DashboardManager.loadConfiguration()
DashboardManager.init()
DashboardManager.__allocating_init()
closure #1 in ContentView.body.getter          ← SwiftUI body evaluation
```

`DashboardManager.init()` calls `loadConfiguration()` synchronously. That
decodes the full JSON (layouts + widget configs + `AudioWidgetType` string
switch for every widget in every layout) **on the main thread, inside a
SwiftUI view body evaluation**. This is a launch-blocking operation.

## Acceptance

- `DashboardManager.init()` returns without blocking the main thread; the
  initial state is an empty/default value.
- `loadConfiguration()` is called from a `Task` on `@MainActor` (or a
  background task that publishes back on `@MainActor`); the decoding work
  runs off the main thread.
- The app reaches first interactive frame without a hang > 50 ms in a
  re-trace using the same 76-second Time Profiler + Hangs template.
- No regression in configuration persistence: after the async load, the
  same layouts/widgets are visible as before.
- iOS build succeeds.

## Implementation notes

- `DashboardManager` is `@MainActor`-bound (check current annotation);
  the decode itself can run in a detached `Task` or `Task.detached` and
  publish back via `MainActor.run`.
- Guard against multiple concurrent load calls with a boolean flag
  (`isLoading`) — not needed for correctness but avoids double-decode on
  fast re-enters.
- The default empty state shown before load completes should not be
  persisted — ensure `saveConfiguration()` is not called during the
  transition window.
- Add a `didFinishLoading: Bool` published property so views can show a
  skeleton / disable edit mode until load completes.

Milestone: `milestone-19-instruments-trace-perf-fixes`
Source: 2026-05-29 Instruments trace — 573 ms hang at T+1.583s
