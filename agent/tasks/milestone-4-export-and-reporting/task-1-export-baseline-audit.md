# Task 1: Export Baseline Audit

Status: completed  
Created: 2026-05-12  
Completed: 2026-05-12  
Milestone: `milestone-4-export-and-reporting`

## Objective

Establish the current export behavior before changing report, CSV, or image
export code. The audit should identify existing gaps against the milestone
completion criteria and keep later implementation scoped.

## Scope

- Inspect `PDFReportGenerator`, `CSVExporter`, `SpectrogramImageRenderer`, and
  `RecordingDetailView` export actions.
- Confirm which files are in the Xcode project and test targets.
- Run the smallest practical build/test gate for current export code.
- Record current gaps and any simulator limitations in the task file or a short
  report note.

## Acceptance

- Existing PDF, CSV, and spectrogram export entry points are mapped.
- Current tests covering export behavior are identified.
- Any failing compile or test gate is documented with file references.
- The next PDF task has a concrete implementation checklist.

## Audit Results

### Export Entry Points

- `SpektoWatch2/Views/RecordingDetailView.swift`
  - Toolbar shares `recordingManager.url(for: recording)`, which is the audio
    file for the recording.
  - Overview export card exposes CSV export through `createCSVExport()`.
  - Overview export card and toolbar expose PDF generation through
    `createPDFReport()`.
  - No standalone spectrogram image export action exists yet.
  - No explicit raw measurement-data share action exists yet.
- `SpektoWatch2/PDFReportGenerator.swift`
  - Generates a temporary `report_<recording-id>.pdf`.
  - Page 1 contains title, recording metadata, summary metrics, and level
    history.
  - Page 2 contains a rendered full-recording spectrogram when audio can be
    read, averaged Z/A/C third-octave charts, and configuration fields.
  - Additional pages render attached photos.
  - Current gap: report text does not clearly state that built-in iPhone and
    Apple Watch microphone readings are approximate and not compliance-grade.
  - Current gap: calibration is present as a numeric offset, but there is no
    explicit calibration-state explanation.
- `SpektoWatch2/CSVExporter.swift`
  - Exports selected metric columns filtered against `reader.header.metricKeys`.
  - Uses semicolon-separated UTF-8 rows with three-decimal numeric formatting.
  - Includes broadband and optional Z/A/C third-octave columns.
  - Also contains `JSONMeasurementExporter`, but JSON export is not exposed in
    `RecordingDetailView`.
- `SpektoWatch2/SpectrogramImageRenderer.swift`
  - Can render a `UIImage` from an audio file using AVFoundation and vDSP.
  - Currently used by `PDFReportGenerator` for embedded report imagery.
  - Current gap: there is no file-writing/share action for standalone image
    export.

### Project And Test Coverage

- `SpektoWatch2.xcodeproj` uses `PBXFileSystemSynchronizedRootGroup` for the app
  and test folders, so source and test membership comes from the filesystem
  groups rather than explicit PBX file references.
- Existing export tests:
  - `SpektoWatch2Tests/PDFReportGeneratorTests.swift`
  - `SpektoWatch2Tests/CSVExporterTests.swift`
- Related spectrogram tests:
  - `SpektoWatch2Tests/HighEndSpectrogramAdapterTests.swift`
- Current gap: there is no focused test for standalone spectrogram image export
  output or failure behavior.

### Validation

- Initial requested command failed before compilation because the `iPhone 16`
  simulator is not installed:
  - `xcodebuild build-for-testing -project SpektoWatch2.xcodeproj -scheme SpektoWatch2 -destination "platform=iOS Simulator,name=iPhone 16,OS=latest"`
- Rerun on available iPhone 17 simulator succeeded:
  - `xcodebuild build-for-testing -project SpektoWatch2.xcodeproj -scheme SpektoWatch2 -destination "platform=iOS Simulator,id=84D1AE75-4AF0-4F66-A530-47AC897DF4E1"`
  - Result: `TEST BUILD SUCCEEDED`

## PDF Task Checklist

- Add explicit built-in microphone limitation text to generated PDF reports.
- Make calibration state readable as more than a bare offset value.
- Preserve existing title, metadata, summary table, level history, spectrogram,
  third-octave, configuration, and photo pages.
- Extend `PDFReportGeneratorTests` for the new required text/content.
- Keep report generation local and temporary-file based.

## Steps

```sh
rg -n "PDFReportGenerator|CSVExporter|SpectrogramImageRenderer|create.*Export|ShareLink|shareItems" SpektoWatch2 SpektoWatch2Tests SpektoWatchTests

xcodebuild build-for-testing \
  -project SpektoWatch2.xcodeproj \
  -scheme SpektoWatch2 \
  -destination "platform=iOS Simulator,name=iPhone 16,OS=latest"
```

## Non-Goals

- Do not redesign the export UI in this task.
- Do not change report content before the baseline is recorded.
