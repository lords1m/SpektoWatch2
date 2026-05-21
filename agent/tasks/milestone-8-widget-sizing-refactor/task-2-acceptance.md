# Task 2: Acceptance

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-8-widget-sizing-refactor`
Depends on: task-1

## Code-side findings (2026-05-21)

Done from CLI without running the app (AGENT.md: local simulator is
broken). Runtime checks 1, 2, 5 remain gated on hardware / Xcode Cloud.

- ✅ **Check 3** (spectrogram cannot shrink < 2×2): verified in
  `DashboardManager.resizeWidget` and `WidgetCardView.handleResize`.
  Both call `proposed.clamped(min: range.min, max: range.max)` where
  `range = WidgetConfiguration.sizeRange(for: .spectrogram)`, which
  returns `(min: 2×2, max: 3×4)`.
- ✅ **Check 4** (singleValue cannot grow > 2×2): same clamp paths,
  range `(min: 1×1, max: 2×2)`.
- ✅ **Check 5 (code-side)**: drag-and-drop reorder is untouched by
  M8 — `WidgetDropDelegate` only manipulates the `widgets` array
  order, never the per-widget `size`. Runtime visual check still
  needed on hardware.
- ✅ **Check 6** (PDF / Recording decode-compat): the two decode
  sites that consume `[WidgetConfiguration]` blobs are
  `RecordingDetailView.loadPlaybackWidgets` (line 821) and
  `DashboardManager.loadConfiguration` (lines 183, 216). Both use
  `JSONDecoder().decode([WidgetConfiguration].self, from:)`, which
  routes through the M8 `WidgetConfiguration.init(from:)` →
  `WidgetSize.init(from:)`. The size decoder accepts both legacy
  `Double` and new `Int` `rows`; out-of-range values are clamped
  against the per-type range. A legacy widget with `"rows": 0.5`
  decodes to the type's `min.rows`. No throw, no crash.
- ⏳ **Check 1** (fresh dashboard): runtime; cannot verify here.
  Expected: defaults from `WidgetConfiguration.defaultSize(for:)` —
  spectrogram 3×3, levelHistory 3×2.
- ⏳ **Check 2** (existing dashboard with legacy `Double` rows):
  runtime; cannot verify here. Code-side migration path is in
  place; widgets that were on `rows: 0.5` will visibly jump to the
  per-type `min.rows` on next launch. This is intentional but worth
  calling out as a UX surprise.

## Notes

- Subtle path noticed in `DashboardManager.normalizeWidgets`:
  legacy `.octaveBands` widgets are rewritten in place to
  `.frequencyDisplay` *after* the decode-time clamp ran against the
  old type. In M8 these two types share the same size range
  (`(2×1, 3×3)`), so this is fine today. A future type-migration
  that changes the range would need to re-clamp post-normalize.

## XCTest coverage added (2026-05-21)

`SpektoWatch2Tests/WidgetSizingMigrationTests.swift` — covers check #2
("App launches cleanly with existing dashboard with legacy `Double`-row
values") as an executable test rather than code inspection:

- `testWidgetSizeDecodesLegacyHalfRow` — `"rows": 0.5` decodes,
  rounds, and clamps to `WidgetSize.absoluteMinimum`.
- `testWidgetSizeDecodesLegacyDoubleWhole` — `"rows": 2.0` decodes.
- `testWidgetSizeDecodesNewIntRows` — `"rows": 4` (Int) decodes.
- `testWidgetSizeRespectsAbsoluteMinimum` — `0×0` clamps to `1×1`.
- `testSpectrogramLegacySizeClampsUpToMin` — full `WidgetConfiguration`
  blob with `1×0.5` for a spectrogram clamps to `2×2`.
- `testSingleValueLegacySizeClampsDownToMax` — `4×6` for singleValue
  clamps to `2×2`.
- `testLegacyOctaveBandsDecodes` — backward-compat decode of the
  retired `octaveBands` type.
- `testSizeRangesAreWellFormedAndDefaultsAreInRange` — invariant:
  every type's `defaultSize` sits inside its `sizeRange`, and
  `min ≤ max` element-wise across all types.
- `testWidgetConfigurationRoundTripsThroughJSON` — encode → decode
  produces an equal value.

Will execute in Xcode Cloud once M7 task-1's package wiring is live;
runs locally on a working simulator (currently broken per AGENT.md).

## Validation maintenance (2026-05-21)

Follow-up fixes landed after inspecting the latest Xcode test diagnostics:

- `PDFReportSnapshotTests.testPDFReport_documentOutline_matchesBaseline`
  now passes a newline-joined `String` into `.lines` instead of `[String]`.
- `SnapshotTestSupport` now uses the writable source snapshot directory
  when recording snapshots, and only uses bundled snapshot resources when
  the bundled class directory contains real baselines rather than the
  placeholder `README.txt`.
- `HighEndSpectrogramAdapterTests.testInitialConfiguration` now expects
  the current 60 FPS target.
- `HighEndSpectrogramAdapterTests.testAxisMetricsCallback` now uses
  `reset()` as the deterministic callback trigger because regular data
  updates are consumed by the draw loop and may not emit metrics in
  headless test runs.
- Removed the stale manual-scroll-offset test because that API was
  already removed from `HighEndSpectrogramAdapter`.
- `PDFReportSnapshotTests` now skip on physical devices when no real
  snapshot baselines are bundled, because a device test runner cannot
  write back into the Mac source `__Snapshots__` directory. This keeps
  local hardware runs from stalling/failing on baseline recording setup.
- Added a dashboard screenshot preset for runtime acceptance:
  Layouts → `Screenshot-Preset: Widgetgrößen` replaces the current
  dashboard pages with one page per visible widget type. Each page
  contains only that widget type, repeated across every allowed
  `columns × rows` value from `WidgetConfiguration.sizeRange(for:)`.
  `WidgetSizingMigrationTests` now covers the preset layout count and
  exact size coverage.

Validation run:

- `XcodeRefreshCodeIssuesInFile` for `PDFReportSnapshotTests.swift`: clean.
- `XcodeRefreshCodeIssuesInFile` for `HighEndSpectrogramAdapterTests.swift`: clean.
- `XcodeRefreshCodeIssuesInFile` for `DashboardManager.swift` and
  `ModularDashboardView.swift`: clean.
- `BuildProject`: succeeded.
- `./agent/scripts/acp-validate`: passed.

## Outstanding (hardware-only)

- Checks 1, 5 on hardware or Xcode Cloud. (Check 2 now has XCTest
  coverage; the hardware run reduces to a visual confirmation that
  the visible clamp behaviour matches expectations.)
- Once runtime checks pass: write handoff report under
  `agent/reports/<date>-milestone-8-acceptance.md` summarizing
  observed clamp behaviour and any UX surprises from existing
  dashboards getting visibly resized on first M8 launch.

## Runtime screenshot evidence (2026-05-21)

User added `Spectowatch Widget Screenshots /` with 39 full-device PNG
captures (`1125×2436`, about 104 MB total). Treat this folder as the
current visual evidence set for widget-size acceptance and the later M9
widget audit.

Screenshot review report written:
`agent/reports/2026-05-21-widget-screenshot-review.md`.

Result: keep M8 acceptance open. The screenshot preset and hardware capture
path work, but the captures show layout issues and do not independently prove
fresh-dashboard defaults, legacy-dashboard migration, or drag-and-drop reorder.
Notable visual findings: debug overlay overlaps the header, page dots can sit
over top widget content, bottom controls obscure lower widgets, frequency
display and masking pages are mostly blank in the captured state, tone
generator presets can clip, and spektralanalyse-lab labels truncate in small
sizes.

## Objective

Verify the refactor end-to-end on a developer machine (simulator is
broken per AGENT.md — acceptance happens in Xcode Cloud or on hardware).

## Acceptance Checks

1. App launches cleanly with a fresh dashboard. Default widgets match
   the Size Matrix.
2. App launches cleanly with an existing dashboard (legacy
   `Double`-row values). All widgets render at a usable size.
3. Resize drag on the spectrogram widget cannot shrink it below 2×2.
4. Resize drag on the single-value widget cannot grow it beyond 2×2.
5. Widget reordering via drag-and-drop still works.
6. PDF export still works (widget config snapshot in `Recording.widgetConfigurations`
   is decode-compatible after the migration).

## Handoff

Once the above pass, write a short report under `agent/reports/` summarizing
which sizes were observed and any clamp surprises.
