# Task 2: PDF Report Baseline

Status: completed  
Created: 2026-05-12  
Completed: 2026-05-12  
Milestone: `milestone-4-export-and-reporting`

## Objective

Make generated PDF reports meet the required client-facing baseline: summary
metrics, level history, metadata, and calibration information, with clear
language that built-in microphones are approximate.

## Scope

- Review and update `PDFReportGenerator`.
- Ensure metadata includes recording name, date, duration, location when
  present, calibration offset, weighting configuration, and measurement source
  limitations.
- Keep spectrograms, notes, and photos as optional report content where already
  available.
- Extend `PDFReportGeneratorTests` for required text/content regressions.

## Implementation Checklist

- Add report copy that states built-in iPhone and Apple Watch microphone
  readings are approximate and not compliance-grade.
- Expand the configuration/calibration section so the calibration state is
  understandable even when the offset is `0.0 dB`.
- Preserve the existing two-page baseline layout and optional photo pages.
- Add or update tests that extract PDF text and assert the required report
  baseline sections are present.
- Keep report generation independent of simulator runtime availability where
  possible.

## Acceptance

- PDF output contains the required baseline sections.
- Built-in microphone reports avoid compliance-grade claims.
- Calibration state is visible even when the offset is zero or unavailable.
- Existing PDF photo behavior remains covered.
- `PDFReportGeneratorTests` build and pass where runtime tests are available.

## Non-Goals

- No branded/client-specific template editor.
- No formal standard or legal compliance wording.
- No cloud report storage.
