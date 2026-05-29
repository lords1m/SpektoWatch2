# Task 7: Acceptance — Instruments Re-trace

Status: pending
Created: 2026-05-29

## Procedure

Run a second 76-second Time Profiler + Hangs session (same template as
`timerun3.trace`) on the same device (iPhone 12 mini, iOS 26.4.1) after
all tasks 1–6 land. Verify each binary outcome:

1. **No launch hang.**
   - `potential-hangs` table in re-trace: zero rows, or all rows < 250 ms.
   - `DashboardManager.loadConfiguration()` not present in main-thread
     call stacks during the first 5 seconds of the session.

2. **No dynamic array growth in LevelHistoryView.**
   - `_ArrayBuffer._consumeAndCreateNew` not present in the top 100
     frames of the re-trace during steady-state audio.

3. **No per-frame CoreText layout in WaterfallView.**
   - `NSCoreTypesetter` not present in top 20 frames.
   - `WaterfallView.drawText` sample count < 3 in the 76-second session.

4. **No Metal drawable stall on main thread.**
   - `CAMetalLayerPrivateNextDrawableLocked` not present in any main-thread
     sample.
   - `HighEndSpectrogramAdapter.draw` sample count within ± 20% of expected
     steady-state GPU load.

5. **Audio frames do not trigger dashboard re-render.**
   - `ModularDashboardView.mainBody.getter` < 5 samples.
   - `ButtonBehavior.body.getter` < 5 samples.

6. **AttributeGraph dirty-propagation rate halved.**
   - `AG::Graph::propagate_dirty` < 22 samples.
   - `ForEachState.update` < 15 samples.

## Handoff report

Write `agent/reports/2026-05-29-m19-acceptance.md` with:
- Re-trace timestamp and device.
- Per-outcome pass/fail.
- Comparison table: baseline sample counts (from `timerun3.trace`)
  vs. re-trace sample counts.
- Any new regressions discovered in the re-trace.

Milestone: `milestone-19-instruments-trace-perf-fixes`
