# Task 1: Cancellation Test Race Fix

Status: pending
Created: 2026-05-25

## Goal

Stop three cancellation tests from passing for the wrong reason on fast
hosts. Today `task.cancel()` is called with no cooperative suspension
afterwards, so the detached task can complete entirely before the
cancellation flag is observed.

## Source

- TT-2 (Critical) — `agent/reports/2026-05-24-code-review-synthesis.md`
  lines ~347–357.
- TT-3 (High) — same report, lines ~359–365.

Files:
- `SpektoWatch2Tests/PDFReportGeneratorTests.swift` lines ~390–413
- `SpektoWatch2Tests/StoredDataProviderTests.swift` lines ~58–75
- `SpektoWatch2Tests/CSVExporterTests.swift` lines ~379–402

## Sub-items

- **Sub-1**: Insert `await Task.yield()` immediately after `task.cancel()`
  so the detached task gets a scheduling slot before the assertion.
- **Sub-2**: Increase the fixture size used by these three tests to
  ~10 K frames (or whatever the production `loadBroadbandValues` /
  `CSVExporter.export` loop body needs to span multiple cancellation
  checks — at 256-frame check intervals that's >40 windows).
- **Sub-3**: Add a `catch { XCTFail("Unexpected error: \(error)") }`
  fallback inside the test's `do/catch`, so non-`CancellationError`
  failures stop being silently swallowed.
- **Sub-4**: Verify the timing assertion (`< 0.5 s`) is measured from
  task start, not from `cancel()` — adjust the bound if needed.

## Acceptance

- All three tests fail loudly if the production code stops honoring
  cancellation. Confirmed by mutation: temporarily commenting out the
  `try Task.checkCancellation()` inside `PDFReportGenerator` /
  `CSVExporter` / `StoredDataProvider` makes the tests fail.
- iOS test target build green; tests run green when production code is
  correct.

Milestone: `milestone-18-test-tooling-debt`
