# Task 1: Widget Sizing Refactor

Status: completed
Created: 2026-05-21
Completed: 2026-05-21
Milestone: `milestone-8-widget-sizing-refactor`

## Result (2026-05-21)

- `WidgetSize.rows` now `Int`. `minimumRows: Double = 0.5` replaced by
  `absoluteMinimum: Int = 1` (hard floor against zero-sized Metal drawables).
- `WidgetSize.init(from:)` accepts both legacy `Double` and `Int` rows;
  `Double` rounded to nearest `Int`. Per-type clamping moved to
  `WidgetConfiguration.init(from:)` so the decoder knows the widget type.
- New `WidgetSize.clamped(min:max:)` helper — element-wise clamp.
- New `WidgetConfiguration.sizeRange(for:) -> (min, max)` as single
  source of truth. Defaults table moved to use it implicitly.
- `WidgetConfiguration.init(type:size:gridPosition:settings:)` now
  clamps incoming `size` to the type's range.
- `WidgetConfiguration.init(from:)` reimplemented explicitly so `type`
  is decoded before `size`, enabling correct legacy clamp.
- `DashboardManager.resizeWidget` clamps to type range (was global
  `[1,4]/≥0.5`).
- `DashboardManager.firstLaunchWidgets` now uses
  `WidgetConfiguration.defaultSize(for:)` instead of hand-rolled
  `columns: 4` (which was clamped at runtime anyway — dead value).
- `WidgetCardView.handleResize` reworked: per-edge delta computed as
  whole cells (no more 0.5 snap), clamped via type range. `range`
  read once from `WidgetConfiguration.sizeRange(for:)`.

## Acceptance check (code-side)

- `grep WidgetSize(` shows no `Double` literals in `rows:` anywhere.
- All construction sites use `Int` rows.
- Spectrogram resize cannot fall below 2×2 (clamp in `resizeWidget` +
  `handleResize`).
- SingleValue resize cannot exceed 2×2 (clamp in `resizeWidget` +
  `handleResize`).
- Legacy decode path: a persisted `WidgetSize` with `rows: 0.5` for a
  spectrogram widget rounds to `0`, gets `WidgetSize.absoluteMinimum`
  applied, then the per-type clamp in `WidgetConfiguration.init(from:)`
  bumps it to `2` (spectrogram min row). No throw, no crash.

## Outstanding (gated on hardware/Cloud)

- Runtime acceptance (task-2): real dashboard launch, resize gestures,
  legacy-load verification.

## Objective

Implement the full widget sizing refactor in one coherent change:
integer rows, per-type min/max ranges, resize clamping, legacy migration.

## Scope

1. **`SpektoWatch2/WidgetConfiguration.swift`**
   - `WidgetSize.rows`: `Double` → `Int`.
   - Drop `minimumRows: Double = 0.5`; replace with per-type min/max via
     `sizeRange(for:)`.
   - `height: CGFloat`: stays a computed property; recompute from
     `Int` rows.
   - Decoder reads legacy `Double` rows, rounds, and clamps to the
     target widget type's range (decoder needs the `type` context —
     either decoded earlier in `WidgetConfiguration.init(from:)` or
     clamping is moved up to `WidgetConfiguration`).
   - New: `static func sizeRange(for type: AudioWidgetType) -> (min:
     WidgetSize, max: WidgetSize)`.
   - `defaultSize(for:)`: reads `.min`/`.max` boundary or a sensible
     default within the range per the Size Matrix in the milestone.

2. **`SpektoWatch2/DashboardManager.swift`**
   - `resizeWidget(id:to:)`: clamp `newSize` against `sizeRange(for:
     widget.type)` before storing.
   - `firstLaunchWidgets`: `columns: 4` → `columns: 3` on both entries.
   - Any other call site that constructs `WidgetSize` directly: verify
     it produces a value within the type's range, otherwise clamp.

3. **`SpektoWatch2/WidgetCardView.swift`**
   - `handleResize(translation:edge:)`: replace `max(1, min(4, ...))`
     and `max(0.5, ...)` with clamping against `sizeRange(for:
     widget.type)`.
   - `.bottom` and `.top` cases: drop the `* 2 / 2.0` snap; round to
     `Int` directly.

4. **Migration check.** Any persisted `WidgetSize` with `rows = 0.5`
   or fractional values must decode to an `Int` ≥ type's `min.rows`
   without throwing.

## Acceptance

- `WidgetSize.rows` is `Int`; grep confirms no `Double`-typed `rows`
  remains in widget code.
- `sizeRange(for:)` is the single source of truth — `defaultSize(for:)`,
  `resizeWidget(...)`, and `handleResize(...)` all consume it.
- Spectrogram cannot shrink below 2×2; Single-Value cannot exceed 2×2
  (verified by reading the clamp call in `resizeWidget`).
- `firstLaunchWidgets` uses `columns: 3`.
- Legacy decode: a hand-rolled JSON with `"rows": 0.5` for a spectrogram
  widget decodes to `rows: 2` (the type's min).

## Non-Goals

- Picker UI changes.
- Drag/drop reorder changes.
- watchOS sizing (separate model).
- Any production-code behavior outside sizing.

## Notes

- The decoder migration requires `type` to be decoded before `size`.
  `WidgetConfiguration.CodingKeys` already encodes both; in
  `init(from:)` decode `type` first, then read raw `Double`/`Int`
  rows, clamp, and construct the final `WidgetSize`. The `WidgetSize`
  Codable init is no longer reachable via the standard path — keep
  it for safety with a fallback (e.g. clamp against a "smallest of
  any type" range = 1×1) so callers that decode a bare `WidgetSize`
  outside a `WidgetConfiguration` don't break.
