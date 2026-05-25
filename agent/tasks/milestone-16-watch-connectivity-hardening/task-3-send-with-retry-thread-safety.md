# Task 3: sendWithRetry Thread Safety

Status: completed
Created: 2026-05-25
Completed: 2026-05-25

## Outcome

`SpektoWatch2/WatchConnectivityManager.swift` only. The watch-side
`Shared/WatchConnectivityManager.swift` has no `sendWithRetry` /
`messageQueue` — no change required there.

- **Sub-1**: `sendWithRetry` body wrapped in
  `DispatchQueue.main.async { [weak self] in ... }`. All
  `messageQueue.append` and the initial `processQueue()` call now
  run on main regardless of caller thread.
- **Sub-2**: `dispatchPrecondition(condition: .onQueue(.main))` added
  at the top of `processQueue()` and `handleMessageError()` to make
  the main-only invariant explicit. Existing reply/error handler blocks
  already dispatch to main — unchanged.
- **Sub-3 (call-site audit)**:
  - `DashboardViewModel` call sites are SwiftUI / view-model, main-bound.
  - `WatchDashboardSettingsView.sendWatchDashboardConfig` is a SwiftUI
    view action, main-bound.
  - `AudioEngine.frequencyWeighting.didSet` (line 341) can fire off-main;
    the `main.async` wrap now makes this safe without needing to change
    AudioEngine.
- **Sub-4**: Watch-side `Shared/WatchConnectivityManager.swift` — no
  `sendWithRetry`, `messageQueue`, or `isProcessingQueue` found.
  No watch-side change needed.

iOS build: `BUILD SUCCEEDED`.

## Hardware acceptance pending

Connectivity smoke: send gain / recording-start / dashboard-config
while the watch foregrounds / backgrounds rapidly; confirm no
duplicate messages or double-remove.

Milestone: `milestone-16-watch-connectivity-hardening`
Source: WA-3 High — `agent/reports/2026-05-24-code-review-synthesis.md`
