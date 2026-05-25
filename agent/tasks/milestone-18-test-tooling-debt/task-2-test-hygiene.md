# Task 2: Test Fixture & Teardown Hygiene

Status: pending
Created: 2026-05-25

## Goal

Eliminate four shapes of brittle test code that can corrupt user data
or hide failures: metadata backup in test body, `Float.random` in
deterministic assertions, conflated test names, and `try!` in fixture
creation.

## Source

- TT-4 (High) — `agent/reports/2026-05-24-code-review-synthesis.md`
  lines ~367–373.
- TT-7 (Medium) — same report, lines ~390–396.
- TT-8 (Medium) — same report, lines ~398–403.
- Coverage gap 3 — `createTestMeasurementFile` uses `try!`.
- Coverage gap 4 — `RecordingPersistenceDurabilityTests.tearDown` can
  hang on corrupt metadata.

Files:
- `SpektoWatch2Tests/RecordingPersistenceDurabilityTests.swift`
- `SpektoWatch2Tests/CSVExporterTests.swift`
- `SpektoWatch2Tests/StoredDataProviderTests.swift`
- `SpektoWatch2Tests/PDFReportGeneratorTests.swift`

## Sub-items

- **Sub-1 (TT-4 + gap 4)**: Move the `recordings_metadata_v2.json`
  backup/restore out of the `testRecordingDecodeWithMissingID_throws`
  body into `setUp`/`tearDown`. Prefer routing the test through
  `AppServices.testFixture(recordingManager:)` with a temp Documents
  root so concurrent tests can't cross-contaminate.
- **Sub-2 (TT-7)**: Replace `Float.random(...)` broadband values in
  `testCSVNumericFormatThreeDecimalPlaces` with a deterministic
  constant. Assert decimal precision only on columns with known values;
  drop the count-based assertion on first-column timestamps.
- **Sub-3 (TT-8)**: Rename `testBootstrapKeepsSmallMetricDataEager` to
  `testBootstrapEagerlyLoadsLevelHistoryAndMetricRows`. Add a separate
  test asserting `hasFullFFT == false` for a `fftBinCount: 0` fixture.
- **Sub-4 (gap 3)**: Replace every `try!` in `createTestMeasurementFile`
  (both `PDFReportGeneratorTests` and `CSVExporterTests`) with `try` +
  `throws` propagation so writer failures produce an XCTest failure
  instead of crashing the process.
- **Sub-5 (gap 4)**: Make `RecordingPersistenceDurabilityTests.tearDown`
  resilient — don't instantiate a fresh `RecordingManager()` for
  cleanup if `setUp` used `AppServices.testFixture` (sub-1).
  Otherwise, wrap the cleanup in a timeout / `try?`.

## Acceptance

- No `try!` in `SpektoWatch2Tests/**/*.swift` fixture helpers.
- No `Float.random` in deterministic decimal-precision assertions.
- `testBootstrap*` test names match what they assert.
- Backup/restore lives in lifecycle hooks, not test bodies.
- iOS test target build green.

Milestone: `milestone-18-test-tooling-debt`
