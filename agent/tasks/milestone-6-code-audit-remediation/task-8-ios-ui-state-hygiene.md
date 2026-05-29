# Task 8: iOS UI State Hygiene

Status: completed
Created: 2026-05-18
Updated: 2026-05-29
Milestone: `milestone-6-code-audit-remediation`

## Status Summary

| Sub-item | Source finding | Result |
|---|---|---|
| 1. `DashboardViewModel` nested `ObservableObject` | Audit #30 (Critical) | DEFERRED — verification reversal (see below); perf concern real but is a structural refactor |
| 2. `WidgetSize.height` zero-clamp + Codable migration | Audit #37 (High) | **LANDED** — `WidgetConfiguration.swift:36-94`, `DashboardManager.swift:136-149` |
| 3. `MaskingSuggestionView` preview ref | Audit #41 (Medium) | DEFERRED — verification reversal (see below) |
| 4. `onChange` re-entrancy on mic-source fallback | Audit #42 (Medium) | **LANDED** — `DashboardViewModel.swift:92-115` (different guard than the audit suggested; same effect) |

2 of 4 landed, 2 deferred as verification reversals.

## Verification Reversals

### #30 — `DashboardViewModel` nested `ObservableObject` stale-UI claim

The audit asserted: "WidgetDropDelegate mutates `dashboardManager.widgets` directly, bypassing the forwarder — `objectWillChange` on the view model is never triggered, potentially leaving UI stale."

Trace:
1. `WidgetDropDelegate.dropEntered` mutates the `@Binding var items` (= `viewModel.dashboardManager.widgets`).
2. That `@Published` setter fires `dashboardManager.objectWillChange`.
3. The forwarder sink at `DashboardViewModel.swift:28-32` (`dashboardManager.objectWillChange.sink { self.objectWillChange.send() }`) catches it.
4. `ModularDashboardView` body recomputes via its `@StateObject viewModel` observation.

The forwarder DOES catch drop-delegate mutations. The "UI stays stale after drag-and-drop" claim is wrong.

The audit's secondary point — that every per-widget change triggers a full `ModularDashboardView` body recomputation — is true and is a real performance concern, but addressing it is a structural refactor (lift `DashboardManager` to a sibling `@ObservedObject`, or migrate to `@Observable` with iOS 17+ macro). Out of scope for this remediation milestone. Tracked as a future perf cleanup.

### #41 — `MaskingSuggestionView` cached `preview` reference

The audit claimed the cached `@ObservedObject private var preview` becomes stale if `MaskingEngine` is recreated. In practice:

- `MaskingSuggestionView` is presented only from `MaskingEntryWidget.acquisitionOrSuggestionSheet` (single call site).
- The same `engine` instance is passed every presentation.
- SwiftUI re-runs the struct's `init` whenever the parent view tree rebuilds, so `self.preview = engine.previewPlayer` re-fetches the current player even if the engine changed.

The audit's proposed fix — "access `engine.previewPlayer` directly in `body`" — does not actually work as suggested: `engine.previewPlayer` is itself an `ObservableObject`, and without an `@ObservedObject` wrapper SwiftUI would NOT re-render when `previewPlayer.isPlaying` changed. The current cache-via-`@ObservedObject` pattern is the correct one for the actual call shape.

Deferred as not-a-real-bug.

## What Landed

### `SpektoWatch2/WidgetConfiguration.swift:36-94` — zero-clamp + Codable migration

`WidgetSize.rows` is now backed by a private `_rows` field. The public getter returns the value; the setter and the `init(columns:rows:)` initializer both clamp via `max(WidgetSize.minimumRows, newValue)` (`minimumRows = 0.5`). A custom `init(from: Decoder)` decodes the legacy JSON key `rows` and applies the same clamp, so any persisted dashboard with a corrupt `rows == 0` value is upgraded transparently on load. `encode(to:)` keeps the JSON key as `rows` for round-trip compatibility.

This stops the failure mode where a zero-height widget asks `MetalKit` for a zero-sized drawable and kills the draw loop with a validation error.

### `SpektoWatch2/DashboardManager.swift:136-149` — defensive resize clamp

`resizeWidget` now reconstructs the incoming `WidgetSize` via the clamping initializer before assigning. Belt-and-braces alongside the `rows` setter clamp — explicit at the mutation site, and the debug log prints the clamped value.

### `SpektoWatch2/DashboardViewModel.swift:92-115` — onChange re-entrancy guard

Added `guard audioEngine.activeMicrophoneSource != newSource else { return }` at the top of `handleMicrophoneSourceChange`. Prevents the spurious second invocation in the watch-unreachable fallback flow:

1. User picks `.appleWatch` → `selectedMicrophoneSource = .appleWatch` → `onChange` fires.
2. `applyMicrophoneSourceSelection(.appleWatch)` detects unreachable, rolls back: `selectedMicrophoneSource = .iPhone`.
3. That rollback re-triggers `onChange` with `newSource = .iPhone`.
4. Without this guard: `restartActiveMeasurementForSelectedSource(.iPhone)` would tear down and restart the already-running-on-iPhone engine.

Note: the audit's suggested guard `newSource != selectedMicrophoneSource` doesn't actually work in SwiftUI's `onChange(of:_:)` — by the time the closure body runs, the property has already been updated, so the two are always equal. The active-source guard checks the actual condition we want to avoid (engine already on the requested source) and is the correct mechanism.

## Out of Scope (unchanged)

- Migrating any view to the `@Observable` macro (iOS 17+ — separate effort).
- Visual design changes.
- The `DashboardViewModel` nested-observable structural refactor (deferred from #30).

## Verification

Tests cannot be run locally (simulator broken). Verification:

- Round-trip a hand-crafted dashboard JSON with `rows: 0`: load via `JSONDecoder`, confirm decoded `WidgetSize.rows == 0.5`.
- Manual: drag-and-drop a widget on the dashboard, confirm the new order persists across an app restart.
- Manual: with watch off (or out of range), tap "Apple Watch" as the mic source — confirm the unreachable-alert appears, source rolls back to iPhone, AND `restartActiveMeasurementForSelectedSource` is NOT invoked (verify via breakpoint or signpost; the engine should not restart).

## Follow-ups

- Future perf cycle: address #30's body-recompute granularity by either lifting `DashboardManager` to a top-level `@ObservedObject` in the view tree or adopting `@Observable`.

## Audit References

#30 (deferred — verification reversal), #37 (landed), #41 (deferred — verification reversal), #42 (landed via active-source guard)

## Objective

Fix the SwiftUI state-management correctness bugs that cause stale UI,
extraneous re-renders, and a Metal-texture crash on corrupt widget
configurations.

## Scope

1. **Critical — `DashboardViewModel` holds nested `ObservableObject` as
   `@Published`** — `SpektoWatch2/DashboardViewModel.swift:7`. SwiftUI
   does not recursively observe nested observables; the manual
   `objectWillChange` forwarder triggers full-dashboard re-renders, and
   `WidgetDropDelegate` mutates `dashboardManager.widgets` directly,
   bypassing the forwarder and leaving the UI stale after drag-and-drop.
   Either:
   - Flatten: lift `DashboardManager` state into `DashboardViewModel`
     and remove the inner reference, OR
   - Hoist: pass `DashboardManager` to views as a separate
     `@ObservedObject`/`@StateObject` so SwiftUI observes it directly.
   The hoist option is smaller in diff size — prefer it unless the
   manager turns out to need view-model methods.

2. **High — `WidgetSize.height` can be zero** —
   `SpektoWatch2/WidgetConfiguration.swift:43`. If a corrupt or legacy
   save has `rows == 0`, height = 0 and the Metal view in
   `WidgetCardView` is asked for a zero-sized texture, killing the draw
   loop. Clamp `rows` to ≥ 0.5 in both `WidgetSize.height` and
   `DashboardManager.resizeWidget`. Add a `Codable` migration that
   coerces zero to the default during decode.

3. **Medium — `MaskingSuggestionView` caches `engine.previewPlayer`
   separately** — `SpektoWatch2/Masking/MaskingSuggestionView.swift:16,23`.
   Replace the `@ObservedObject private var preview` stored property
   with direct access (`engine.previewPlayer`) inside `body`. Removes
   the stale-reference risk if `MaskingEngine` is recreated.

4. **Medium — `onChange(of: selectedMicrophoneSource)` re-entrancy** —
   `SpektoWatch2/ModularDashboardView.swift:181`. Add a self-equality
   guard at the top of `handleMicrophoneSourceChange(_:)` mirroring the
   one in the Combine sink, so the watch-unreachable fallback path
   doesn't fire `restartActiveMeasurementForSelectedSource` twice.

## Out of Scope

- Migrating any view to `@Observable` macro (iOS 17+ — separate effort,
  larger refactor).
- Visual design changes.

## Verification

- Manual: drag-and-drop a widget on the dashboard, confirm the new
  order persists across an app restart.
- Manual: load a hand-crafted JSON with `rows: 0` into the dashboard,
  confirm the widget renders at minimum size rather than disappearing
  or crashing.
- Manual: trigger a watch-unreachable fallback (turn off the watch
  during measurement) while on iPhone mic, confirm
  `restartActiveMeasurementForSelectedSource` is invoked at most once
  (verify via breakpoint or log).

## Audit References

#30, #37, #41, #42
