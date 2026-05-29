# Milestone 19: Instruments Trace Performance Fixes

Status: in_progress
Created: 2026-05-29
Priority: high
Estimated: 1.5 weeks

## Goal

Close every actionable finding from the 2026-05-29 Time Profiler trace
(`/Users/simeonbrandt/Documents/timerun3.trace`, 76s run on iPhone 12
mini, iOS 26.4.1). Six binary acceptance outcomes:

1. **No launch hang.** `DashboardManager.loadConfiguration()` runs off
   the main thread; the app reaches its first interactive frame without
   a blocked main thread > 50 ms.
2. **No dynamic array growth in `LevelHistoryView`.** The level buffer
   is pre-allocated to its capacity ceiling at init; zero calls to
   `_consumeAndCreateNew` are observable in a subsequent trace.
3. **No per-frame CoreText layout in `WaterfallView`.** `drawText` does
   not call `NSCoreTypesetter`; frequency labels are cached and only
   re-rendered when the label string or scale changes.
4. **No Metal drawable stall on the main thread.** `HighEndSpectrogram-
   Adapter.draw(_:)` does not block on `CAMetalLayerPrivateNextDrawable-
   Locked`; MTKView triple-buffering confirmed active.
5. **Audio frame updates do not trigger a full dashboard re-render.**
   `ModularDashboardView.mainBody` does not appear in Time Profiler
   samples caused by audio callbacks; `ButtonBehavior.body.getter` drops
   from 47 samples to < 5 in a 76s re-trace.
6. **SwiftUI AttributeGraph dirty-propagation rate halved.** `AG::Graph::
   propagate_dirty` drops below 22 samples (from 43) in a 76s re-trace.

Source: 2026-05-29 Instruments Time Profiler session analysis.

## Why now

The trace revealed a 573 ms confirmed hang at launch (P0 severity) and
five additional performance regressions measurable by sample count. These
are all code-side fixes with no hardware dependency; they can be validated
with a follow-up Instruments session on the same device.

## Tasks

| ID | Name | Priority |
|----|------|----------|
| task-1-dashboard-manager-async-load | Async DashboardManager.loadConfiguration | P0 |
| task-2-level-history-buffer-prealloc | LevelHistoryView buffer pre-allocation | P1 |
| task-3-waterfall-text-cache | WaterfallView frequency-label cache | P1 |
| task-4-metal-triple-buffer | MTKView triple-buffering + drawable off-main | P2 |
| task-5-dashboard-state-split | Split audio state from dashboard layout state | P2 |
| task-6-swiftui-equatable-guards | Equatable conformances + .equatable() guards | P3 |
| task-7-acceptance | Acceptance re-trace + binary outcome verification | — |

## Non-goals

- GPU shader optimisation (out of scope; GPU load is not flagged in trace).
- Refactoring `DashboardManager` beyond async load (covered in M13 backlog).
- Fixing the underlying `LiveAcousticState` publish frequency (already
  addressed in M13 task-4; this milestone adds the missing view-side guards).
- Watch-side performance (separate device; no data in this trace).
