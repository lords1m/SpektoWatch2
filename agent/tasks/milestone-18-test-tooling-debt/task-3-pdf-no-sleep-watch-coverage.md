# Task 3: PDF Test Drop Thread.sleep + Watch performVisualDCT Coverage

Status: pending
Created: 2026-05-25

## Goal

Stop the basic PDF generation test from masking failures behind a
blocking `Thread.sleep` on the main runloop, and cover the watch
production `performVisualDCT` function directly.

## Source

- TT-9 (Medium) — `agent/reports/2026-05-24-code-review-synthesis.md`
  lines ~405–412.
- Coverage gap 5 — `WatchDSPParityTests` only covers a math abstraction,
  not the production `WatchAudioEngine.performVisualDCT`.

Files:
- `SpektoWatch2Tests/PDFReportGeneratorTests.swift` lines ~51–99
- `SpektoWatch2Tests/WatchDSPParityTests.swift`

## Sub-items

- **Sub-1 (TT-9)**: Replace `Thread.sleep(forTimeInterval: 0.5)` with
  an `XCTestExpectation` or `await` on the relevant publisher.
- **Sub-2 (TT-9)**: Bypass the live `RecordingManager.startRecording` /
  `stopRecording` lifecycle in the test — use `createTestRecording()`
  directly so the test doesn't depend on a microphone being present.
- **Sub-3 (gap 5)**: Extend `WatchDSPParityTests` with at least one
  test that calls the production `WatchAudioEngine.performVisualDCT`
  directly (via `@testable import` or by exposing a test-only entry
  point). Assert the 20·log10 path matches the iOS DCT pipeline within
  the existing 0.5 dB tolerance.
- **Sub-4**: If watch target can't be imported into `SpektoWatch2Tests`
  cleanly, mirror the production function body verbatim in the test
  file and add a `// MIRROR OF WatchAudioEngine.performVisualDCT — keep
  in sync` comment plus a grep-based parity check in a sub-helper.

## Acceptance

- No `Thread.sleep` in `PDFReportGeneratorTests`.
- `testGenerateBasicPDFReport` produces a PDF artifact and asserts on it.
- `WatchDSPParityTests` exercises `performVisualDCT` (production or
  mirrored body) and would fail if M15 task-3's 20·log10 fix were reverted.
- iOS test target build green.

Milestone: `milestone-18-test-tooling-debt`
