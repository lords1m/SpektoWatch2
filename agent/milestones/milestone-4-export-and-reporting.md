# Milestone 4: Export And Reporting

Status: completed  
Created: 2026-05-12  
Completed: 2026-05-13  
Source design: `agent/design/spektowatch-field-engineering-design.md`

## Goal

Turn saved measurements into client-facing artifacts without weakening the
existing local-first recording model. PDF reports must include the required
baseline content from the field engineering design. CSV export must be explicit
and predictable for analysis workflows. Spectrogram image export must expose the
recorded spectral view as a shareable artifact.

## Completion Criteria

- PDF reports include summary metrics, level history, metadata, and calibration
  information.
- PDF reports clearly communicate the approximate nature of built-in iPhone and
  Apple Watch microphone readings.
- CSV export has deterministic columns, escaping, numeric formatting, and
  selected-metric behavior covered by tests.
- Spectrogram image export can generate and share a standalone image from a
  saved recording.
- Recording detail export actions expose PDF, CSV, raw measurement sharing, and
  spectrogram image export without breaking existing recording review flows.
- Existing `.spekto` files and measurement readers remain compatible.

## Manual Acceptance

1. Open a saved recording with measurement data.
2. Export a PDF report and confirm it contains summary metrics, level history,
   metadata, calibration information, and built-in microphone limitations.
3. Export CSV data and confirm it opens in a spreadsheet with stable metric and
   third-octave columns.
4. Export a spectrogram image and confirm it visually matches the saved
   recording's spectral content.
5. Share the raw measurement file where available.
6. Reopen the recording detail view and confirm playback, notes, photos, and
   widgets still work.

## Recommended Automated Validation

- `PDFReportGeneratorTests`
- `CSVExporterTests`
- New or extended tests for spectrogram image export behavior
- `MeasurementDataIOTests` as the compatibility regression gate

Use build-for-testing as the minimum gate if runtime execution is blocked by
the simulator environment.

## Tasks

- `agent/tasks/milestone-4-export-and-reporting/task-1-export-baseline-audit.md`
- `agent/tasks/milestone-4-export-and-reporting/task-2-pdf-report-baseline.md`
- `agent/tasks/milestone-4-export-and-reporting/task-3-csv-export-hardening.md`
- `agent/tasks/milestone-4-export-and-reporting/task-4-spectrogram-image-export.md`
- `agent/tasks/milestone-4-export-and-reporting/task-5-recording-detail-export-ui.md`
- `agent/tasks/milestone-4-export-and-reporting/task-6-acceptance.md`

## Explicit Non-Goals

- No compliance-grade claims for built-in iPhone or Apple Watch microphones.
- No external calibrated microphone workflow.
- No cloud upload, account system, or remote report storage.
- No masking workflow expansion.
- No measurement file format breakage.
- No watch complication or standalone watch recording work.

## Future Milestones

- External calibrated microphone and compliance workflow.
- Polished masking workflow and reusable masking profiles.
- Watch complications and standalone recording hardening.
- Report template customization and client branding.
