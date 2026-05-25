# Task 5: capture-screenshots.py Robustness

Status: pending
Created: 2026-05-25

## Goal

Stop `capture-screenshots.py` from silently reporting "Captured 0
screenshots" when Apple drops the `--legacy` xcresulttool format.

## Source

- TT-6 (High) — `agent/reports/2026-05-24-code-review-synthesis.md`
  lines ~382–388.
- Coverage gap 2 — `capture-screenshots.py` attachment-walking has no
  unit test.

File: `agent/scripts/capture-screenshots.py` lines ~140–153.

## Sub-items

- **Sub-1 (TT-6)**: Update `walk_attachments` to handle both shapes:
  ```python
  if isinstance(attachments, dict):
      values = attachments.get("_values", [])
  elif isinstance(attachments, list):
      values = attachments
  else:
      values = []
  ```
  Apply the same defensive `dict` → `list` fallback everywhere
  `_values` is read.
- **Sub-2 (gap 2)**: Add a sibling `test_capture_screenshots.py` (or
  inline `unittest.TestCase` subclass) that feeds both shapes of
  attachment JSON through `walk_attachments` and asserts the same
  paths come out. Cover: legacy dict, modern list, empty, malformed.
- **Sub-3**: Document at the top of the script how to run the unit
  test (`python3 -m unittest agent/scripts/test_capture_screenshots.py`)
  and how to invoke the screenshot extractor against a local
  `.xcresult` bundle.
- **Sub-4**: Add a single-line "ACP M18-task-5" comment near the
  fallback so the rationale isn't lost.

## Acceptance

- Unit test passes locally.
- Running the extractor against a fresh local `xcresult` from
  `xcodebuild test` produces the expected number of PNGs (matches
  the `XCTAttachment` count in `ScreenshotCatalogTests`).
- No silent zero-screenshot exit on either format.

Milestone: `milestone-18-test-tooling-debt`
