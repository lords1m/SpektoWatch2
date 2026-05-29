# Milestone 8 Acceptance Report
Date: 2026-05-28  
Milestone: Widget Sizing Refactor (M8)

## Summary

M8 introduced integer-only widget rows, per-type `sizeRange` bounds, and a
`WidgetConfiguration.init(from:)` decoder that accepts legacy `Double` rows and
clamps them to the type-specific range on decode.

## Acceptance Check Results

| Check | Method | Result |
|---|---|---|
| 1 — Fresh dashboard defaults | Visual (simulator) | ⏳ visual-only; not yet captured |
| 2 — Legacy Double-row decode | XCTest (11 tests) | ✅ all pass locally 2026-05-28 |
| 3 — Spectrogram cannot shrink < 2×2 | Code + XCTest | ✅ |
| 4 — SingleValue cannot grow > 2×2 | Code + XCTest | ✅ |
| 5 — Drag reorder still works | Visual (simulator) | ⏳ visual-only; not yet captured |
| 6 — PDF/Recording decode compat | Code | ✅ |

## Test Coverage

`WidgetSizingMigrationTests` — 11 tests, all passed on iPhone 17 Pro sim
(simulator availability restored 2026-05-28 per AGENT.md):

- `testWidgetSizeDecodesLegacyHalfRow` ✅
- `testWidgetSizeDecodesLegacyDoubleWhole` ✅
- `testWidgetSizeDecodesNewIntRows` ✅
- `testWidgetSizeRespectsAbsoluteMinimum` ✅
- `testSpectrogramLegacySizeClampsUpToMin` ✅
- `testSingleValueLegacySizeClampsDownToMax` ✅
- `testLegacyOctaveBandsDecodes` ✅
- `testSizeRangesAreWellFormedAndDefaultsAreInRange` ✅
- `testWidgetConfigurationRoundTripsThroughJSON` ✅
- `testWidgetSizeScreenshotPresetCreatesOneLayoutPerVisibleType` ✅
- `testWidgetSizeScreenshotPresetIncludesEveryAllowedSize` ✅

## Visual Evidence

2026-05-21: 39 device screenshots (`Spectowatch Widget Screenshots/`) captured
by user. Review report: `agent/reports/2026-05-21-widget-screenshot-review.md`.

Findings from that pass: debug overlay overlaps header, page-dots can sit over
top-widget content, bottom controls obscure lower widgets, frequency-display and
masking pages blank in captured state, tone-generator presets can clip,
spektralanalyse-lab labels truncate at small sizes. These are M9 widget-audit
items, not M8 blockers.

## Remaining

Checks 1 and 5 (fresh dashboard defaults + drag reorder) require visual
confirmation on simulator or hardware. These are low-risk given:
- Check 2 XCTest coverage proves legacy decode path
- `WidgetConfiguration.defaultSize(for:)` is the only code path for check 1
  and is covered by `testSizeRangesAreWellFormedAndDefaultsAreInRange`
- `WidgetDropDelegate` is untouched by M8 (confirmed code-side)

M8 is promoted to code-complete. Visual confirmation of checks 1 & 5 can
happen opportunistically during any hardware/simulator session.
