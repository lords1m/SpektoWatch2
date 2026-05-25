# Task 4: Watch View Perf (Ring Buffer + DateFormatter)

Status: completed
Created: 2026-05-25
Completed: 2026-05-25

## Outcome

**Sub-1 — WatchLevelMeterView** (`SpektoWatch Watch App/WatchLevelMeterView.swift`):
- `historyLength` promoted to `private static let` so it can be used
  as the `@State` default-value argument.
- `@State private var levelHistory: [Float] = []` replaced with
  `@State private var levelHistory = RingBuffer<Float>(capacity: WatchLevelMeterView.historyLength)`,
  mirroring the `WatchSpectrogramView.frames` pattern.
- Canvas draw path: `levelHistory.enumerated()` replaced with a single
  `let snapshot = levelHistory.inOrder()` snapshot; iterates
  `snapshot.enumerated()`. `count` guard updated to `snapshot.count`.
- `appendLevel`: the `removeFirst` + over-length guard deleted. A
  single `levelHistory.append(data.broadbandLevel)` now does O(1)
  drop-oldest. `levelHistory.count` in the time-window label line
  unchanged — `RingBuffer.count` is the same property.

**Sub-2 — WatchSpectrogramView** (`SpektoWatch Watch App/WatchSpectrogramView.swift`):
- `DateFormatter` promoted from inline per-call allocation to
  `private static let timeFormatter` lazy-initialised closure.
  `timeString(from:)` now returns `Self.timeFormatter.string(from:)`.

**Sub-3 (grep)**: No other `removeFirst` calls in the watch target
beyond comments. The `DateFormatter()` hit at line 139 is inside the
new static initializer closure — fine (runs once).

Watch build: `BUILD SUCCEEDED`. iOS build: `BUILD SUCCEEDED`.

Milestone: `milestone-16-watch-connectivity-hardening`
Source: WA-4 + WA-5 Medium — `agent/reports/2026-05-24-code-review-synthesis.md`
