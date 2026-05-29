# Task 6: SwiftUI Equatable Conformances + .equatable() Guards

Status: completed
Created: 2026-05-29
Priority: P3

## Problem

The 2026-05-29 trace shows heavy SwiftUI AttributeGraph churn with no
user interaction:

| Frame | Samples |
|-------|---------|
| `AG::LayoutDescriptor::Compare` | 70 |
| `AG::Graph::UpdateStack::update()` | 69 |
| `TimelineView.UpdateFilter.updateValue()` | 54 |
| `ButtonBehavior.body.getter` | 47 |
| `AG::Subgraph::update(unsigned int)` | 44 |
| `AG::Graph::propagate_dirty(AG::AttributeID)` | 43 |
| `ForEachState.update(view:)` | 41 |
| `DynamicViewList.updateValue()` | 29 |

`propagate_dirty` at 43 samples means the dependency graph is receiving
a write on nearly every sample interval (~1 ms), dirtying the entire
subtree. `ForEachState.update` at 41 samples indicates the widget grid
`ForEach` is rebuilding its item list each audio frame.

These are the residual graph invalidations after task-5 separates state
objects. Task-6 adds per-view short-circuit guards using `Equatable`
conformance so SwiftUI can skip body re-evaluation even when the observed
object publishes a change.

## Acceptance

- `AG::Graph::propagate_dirty` drops below 22 samples (< 50% of
  baseline 43) in a 76-second re-trace after task-5 lands.
- `ForEachState.update` drops below 15 samples.
- `TimelineView.UpdateFilter.updateValue()` drops below 20 samples, or
  is confirmed as expected (TimelineViews by design update every frame;
  the concern is only TimelineViews that do not need to be at 60 Hz).
- No visual regression in widget rendering.
- iOS build succeeds.

## Implementation notes

### ForEach widget grid
- The widget grid uses `ForEach` over the active layout's widget array.
  If the array identity/equality isn't checked by SwiftUI, any audio
  publish re-diffs the entire list. Add `Equatable` to `WidgetConfiguration`
  (and `DashboardLayout`) so `ForEach` can detect no-change.
- Use `ForEach(widgets, id: \.id)` with a stable `id` rather than
  index-based iteration to prevent full list reconstruction.

### TimelineView usage
- Audit `TimelineView` usage in the widget tree. Each `TimelineView` with
  a `.animation(.continuous)` schedule fires at display refresh rate. If
  the schedule is more frequent than needed (e.g. spectrogram fires at
  60 Hz but the data only updates at 20 Hz), change to `.periodic(seconds:
  0.05)` or an explicit refresh trigger.

### .equatable() guards
- On leaf views that show audio data (level meter value, dB readout,
  spectrogram tile): if the view body is `Equatable` on its input props,
  add `.equatable()` to let SwiftUI skip body if props are equal.
- `WidgetCardView.body.getter` appears 7 times — add `Equatable` to
  `WidgetCardView` if its displayed value is already `Equatable`.

### AG::LayoutDescriptor::Compare
- 70 samples of layout comparison suggests a view with a frequently-
  changing `frame` or `alignmentGuide`. Audit `ModularDashboardView`
  and `LevelHistoryView` for dynamic geometry reads that invalidate
  layout on every frame.

Milestone: `milestone-19-instruments-trace-perf-fixes`
Source: 2026-05-29 Instruments trace — SwiftUI AG dirty-propagation churn
