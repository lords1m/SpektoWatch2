# Task 3: CSV Export Hardening

Status: completed  
Created: 2026-05-12  
Completed: 2026-05-12  
Milestone: `milestone-4-export-and-reporting`

## Objective

Make CSV exports deterministic and robust enough for spreadsheet and analysis
workflows.

## Scope

- Review delimiter, header, metric selection, third-octave columns, encoding,
  and numeric formatting in `CSVExporter`.
- Add escaping or quoting if any exported text fields are introduced.
- Preserve existing selected-metric behavior and measurement reader
  compatibility.
- Extend `CSVExporterTests` for deterministic ordering, invalid metric
  filtering, numeric formatting, and empty/legacy reader behavior.

## Acceptance

- CSV headers are stable and documented by tests.
- Selected metrics appear in the requested order after filtering unsupported
  keys.
- Third-octave columns remain consistently labeled.
- Output opens cleanly in common spreadsheet tools.
- `CSVExporterTests` build and pass where runtime tests are available.

## Non-Goals

- No Excel `.xlsx` writer.
- No localization redesign for decimal separators.
- No changes to measurement data storage format.
