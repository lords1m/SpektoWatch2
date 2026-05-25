# Task 10: Persistence / Export Edge Cases (PE-1 … PE-4)

Status: completed
Created: 2026-05-24
Completed: 2026-05-24
Milestone: `milestone-15-critical-stability-correctness`
Source: 2026-05-24 code review — Persistence findings PE-1, PE-2, PE-3, PE-4
  (`agent/reports/2026-05-24-code-review-synthesis.md`)

## Outcome

All four PE items resolved 2026-05-24:

- **PE-1.** `MeasurementDataReader.readFrame` now computes the byte
  offset via `UInt64.multipliedReportingOverflow` and
  `addingReportingOverflow` and throws `invalidFrameIndex` on
  either overflow. Bounds guard tightened to also reject negative
  `frameSize`. Path is defensive against corrupt headers with
  pathological `frameCount`; realistic exposure on well-formed
  files is unreachable because the `index < frameCount` guard
  fires first.
- **PE-2.** Both export paths clean up the partial temp file on
  cancellation / throw. `PDFReportGenerator.generateReport` and
  `CSVExporter.export` use a local `exportSucceeded` flag + `defer
  { try? FileManager.default.removeItem(at: outputURL) }`.
  Regression tests added:
  `PDFReportGeneratorTests.testPDFGenerationCleansUpTempFileOnCancellation`,
  `CSVExporterTests.testCSVExportCleansUpTempFileOnCancellation`.
- **PE-3.** Decision: **keep C-locale numeric format and `;`
  delimiter unchanged.** Rationale: round-trip with R, Python,
  MATLAB consumers (the primary downstream use); Excel-DE imports
  the file correctly via the semicolon delimiter without locale
  conversion of values themselves; silent locale switching would
  break existing analysis pipelines. Decision recorded inline in
  `CSVExporter.export` comment + this task file. No code change to
  output format.
- **PE-4.** Audit complete. `MeasurementDataReader` and
  `MeasurementDataWriter` both close the underlying `FileHandle`
  in `deinit`; init failures release stored properties before
  rethrowing (Swift class-init semantics) so the partially
  initialised handle is closed. `CSVExporter` closes its
  `OutputStream` via `defer`. `JSONMeasurementExporter` uses
  `Data.write(to:)` (no handle). `PDFReportGenerator` instantiates
  the reader as a `let` local that goes out of scope at function
  exit. No leak surface found.

## Goal

Close the four persistence / export edge cases surfaced in the
2026-05-24 review so M15 can close cleanly.

## Scope

### PE-1 — `MeasurementDataReader.readFrame` integer overflow

The current implementation multiplies `frameCount * bytesPerFrame`
in `Int` arithmetic. On pathological frame sizes (very large bin
counts or very long recordings) this can overflow before the bounds
check. Switch the arithmetic to `Int64` (or `UInt64`) with an
overflow-checked multiply, and return a typed error rather than
faulting.

### PE-2 — Export temp-file cleanup

`createPDFReport` / `createCSVExport` write to a temporary URL and
hand the result back to the share sheet. On cancellation or
mid-export failure the temp file is currently orphaned. Wrap the
detached task in a `defer` (or a structured cleanup helper) that
removes the temp file if the export did not complete successfully.

### PE-3 — CSV locale

CSV output currently uses `String(format:)` with the C locale,
which produces `.` decimals regardless of user locale. The product
question is whether German / EU users (the primary audience) expect
`,` decimals. This was deferred in M6 task-2 pending a product
decision. Re-surface the question, decide, and either:
- Switch to `NumberFormatter` with `Locale.current`, plus delimiter
  switch to `;` to stay Excel-compatible, OR
- Document the C-locale decision explicitly in the CSV header
  comment + handoff report and close the finding.

### PE-4 — File descriptor leak

Audit the export and reader paths for `FileHandle` /
`MeasurementDataReader` instances that can leak on error branches.
Convert each owner to a `defer { try? handle.close() }` pattern or
use the `read(contentsOf:)` convenience where the file is small
enough.

## Acceptance

- [ ] PE-1 overflow-safe arithmetic + typed error in
      `MeasurementDataReader.readFrame`; unit test covers the
      boundary fixture.
- [ ] PE-2 temp files deleted on cancellation / failure in both
      PDF and CSV export paths; test covers the cancellation branch.
- [ ] PE-3 decision documented in this task file + acceptance
      report. Code matches the decision.
- [ ] PE-4 file-descriptor audit complete; any `close()` paths
      missing on error branches fixed.
- [ ] M15 acceptance handoff
      (`agent/reports/2026-05-24-milestone-15-acceptance.md`)
      updated with PE-1…PE-4 verdicts; M15 → completed in
      `agent/progress.yaml`.

## Out of scope

- Re-running the M15 binary outcomes (covered by task-9).
- Watch / SwiftUI / test-tooling findings (M16 / M17 / M18).
