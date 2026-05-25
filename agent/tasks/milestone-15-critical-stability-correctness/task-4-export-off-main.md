# Task 4: PDF + CSV Export Off Main with Cancellation

Status: completed
Created: 2026-05-23
Completed: 2026-05-24
Milestone: `milestone-15-critical-stability-correctness`
Source: 2026-05-23 code review — Persistence #3, #6

## Outcome

Task 4 landed code-side on 2026-05-24.

- `RecordingDetailView.createPDFReport` now pre-resolves the
  `RecordingManager` URLs on the main actor, then runs
  `PDFReportGenerator.generateReport(for:audioURL:measurementURL:photoURLs:)`
  inside `Task.detached(priority: .userInitiated)`.
- `RecordingDetailView.createCSVExport` now runs `MeasurementDataReader`
  creation and `CSVExporter.export` inside `Task.detached`, preserving a
  stable metric order from the measurement header.
- `RecordingDetailView` owns one `exportTask`, an active export kind, a
  progress overlay, and an "Abbrechen" button. Completion opens the share
  sheet; cancellation reports "Export abgebrochen"; errors use the existing
  export alert path.
- `PDFReportGenerator` and `CSVExporter` call `Task.checkCancellation()`
  in their long per-frame loops every 256 frames. The PDF generator also
  checks cancellation before and after measurement loading.
- New focused tests cover immediate cancellation for both CSV and PDF export:
  `CSVExporterTests.testCSVExportCancellationThrowsQuickly` and
  `PDFReportGeneratorTests.testPDFGenerationCancellationThrowsQuickly`.

## Verification

- iOS simulator build: passed via XcodeBuildMCP
  (`SpektoWatch2`, Debug, iPhone 17 Pro simulator).
- Targeted tests: passed via direct `xcodebuild test-without-building`:
  - `SpektoWatch2Tests/CSVExporterTests/testCSVExportCancellationThrowsQuickly`
  - `SpektoWatch2Tests/PDFReportGeneratorTests/testPDFGenerationCancellationThrowsQuickly`
- Note: the first XcodeBuildMCP `test_sim` invocation timed out at the tool
  layer after the test build succeeded; the direct rerun executed both tests
  successfully.

## Manual acceptance pending

- Manual smoke on a long recording: start a PDF export, confirm the UI
  remains responsive, tap "Abbrechen", and confirm no share sheet appears.
- Manual smoke on a long `.spekto` recording: start a CSV export, cancel, and
  confirm the cancellation alert appears.

## Goal

PDF + CSV export of a long recording (≥ 30 minutes) currently freezes
the UI for several seconds because the generation runs synchronously
on `@MainActor` with O(n) per-frame disk reads. Move this work off
the main thread and add a user-visible cancellation token.

## Scope

### Sub-1: PDF off main (Persistence #3, **Critical**)

`RecordingDetailView.createPDFReport` (line ~931) calls
`PDFReportGenerator().generateReport(for:recordingManager:)` which
is `@MainActor` and runs:
- `loadBroadbandValues` — `frameCount` seek+reads
- `loadAverageThirdOctaves` — `frameCount × bandCount` seek+reads
- `SpectrogramImageRenderer.renderSpectrogramImage` — full audio
  decode + chunked FFT

For a 5-minute recording: several seconds of frozen UI.

**Fix:**
1. Decouple `PDFReportGenerator` from `@MainActor`. Replace with
   `Sendable` data inputs (the `Recording` value type + a snapshot
   of the metadata-file URL) so generation can run from any actor.
2. Wrap the generator call in `Task.detached(priority: .userInitiated)`
   in `RecordingDetailView`.
3. Surface a progress overlay during generation with a "Abbrechen"
   button that calls `Task.cancel()`.
4. Inside the generator's per-frame loops, periodically
   `try Task.checkCancellation()` so the cancel is honored quickly.

### Sub-2: CSV off main (Persistence #3, **Critical**)

`createCSVExport` (line ~917) has the same shape — calls into
`CSVExporter().export` on main, iterating every frame via
`OutputStream`. Same fix shape as Sub-1.

### Sub-3: Cancellation in `PDFReportGenerator` reads (Persistence #6, **High**)

`loadBroadbandValues` / `loadAverageThirdOctaves` (lines ~250–288)
loop `0..<reader.frameCount` calling `readFrame(at:)`. No
cancellation hook; even with Task.cancellation the loop won't
respond until it returns.

**Fix:** add `try Task.checkCancellation()` every ~256 frames
inside each loop. Document the contract in the function header.

### Sub-4: UI plumbing

`RecordingDetailView` gains:
- `@State private var exportTask: Task<Void, Error>?`
- A modal `.sheet` or `.overlay` with progress indicator + cancel
  button while a generation task is in flight.
- Wire the cancel button to `exportTask?.cancel()`.
- Catch `CancellationError` separately from other errors so the
  user-facing toast says "Export abgebrochen" not a generic error.

## Acceptance

- [ ] `PDFReportGenerator.generateReport` is callable from a
  non-main actor (signature is `Sendable`-compatible).
- [ ] `CSVExporter.export` same.
- [ ] `RecordingDetailView.createPDFReport` and `.createCSVExport`
  run via `Task.detached`.
- [ ] Progress UI shows during export, dismisses on completion or
  cancellation.
- [ ] Cancellation responds within 500 ms on a 30-minute recording.
- [ ] Unit test: create a 1000-frame fixture, start an export, cancel
  immediately, assert the task throws `CancellationError` within the
  expected window.
- [ ] iOS build green; existing PDF / CSV tests pass.

## Files

- `SpektoWatch2/PDFReportGenerator.swift`
- `SpektoWatch2/CSVExporter.swift`
- `SpektoWatch2/Views/RecordingDetailView.swift`
- New tests in `SpektoWatch2Tests/PDFReportGeneratorTests.swift` (or
  similar) for the cancellation path.

## Verification

- iOS build green.
- New cancellation test passes.
- Manual smoke (when simulator is available): generate PDF of a 30+
  min recording — UI stays responsive throughout; cancel mid-export
  works and produces no partial file.

## Out of scope

- Streaming the `StoredDataProvider` (covered by task-5).
- Rewriting `MeasurementDataReader` for vectorized bulk reads —
  separate optimization, captured as M18 / backlog.
- New export formats.
