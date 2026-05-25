# Task 6: Shared UI Screenshot Helper

Status: pending
Created: 2026-05-25

## Goal

Extract the working `capture(_:)` pattern from
`ScreenshotCatalogTests.swift` into a reusable shared base /
extension so **every** UI-test class gets the same screenshot
behavior automatically.

## Source

User request 2026-05-25: "I also want UI tests that create automatic
screenshots from what they are testing (local and cloud)."

Existing implementation: `SpektoWatch2UITests/ScreenshotCatalogTests.swift`
lines ~150–168 already does this. Promote it.

## Sub-items

- **Sub-1**: Create `SpektoWatch2UITests/UITestScreenshot.swift` —
  an `XCTestCase` extension exposing:
  - `capture(_ name: String, file: StaticString = #file, line: UInt = #line)`
  - `settle(_ duration: TimeInterval = 0.7)` (already in
    ScreenshotCatalogTests as `settleDelay`)
  - `sanitizeFilename(_:)` helper
  The function attaches an `XCTAttachment(screenshot:)` with
  `.lifetime = .keepAlways` AND writes a PNG sidecar to
  `FileManager.default.temporaryDirectory/UITestScreenshots/<class>/<test>/<name>.png`
  so the existing `capture-screenshots.py` flow keeps working.
- **Sub-2**: Encode device + iOS version into the attachment name so
  a multi-device matrix run in Xcode Cloud produces distinguishable
  artifacts. Read from `ProcessInfo.processInfo.environment` —
  `SIMULATOR_DEVICE_NAME` / `DEVICE_NAME` / `SIMULATOR_RUNTIME_VERSION`.
- **Sub-3**: Migrate `ScreenshotCatalogTests` to use the shared
  helper — delete the local `capture` / `settle` / `sanitizeFilename`
  methods. Test behavior must stay identical.
- **Sub-4**: Add automatic post-step screenshot in test teardown for
  failed tests so a failure always ships with its visual context:
  override `tearDown()` (or use `XCTContext.runActivity`) to call
  `capture("FAILURE-<test>")` when `testRun?.hasSucceeded == false`.

## Acceptance

- New file `UITestScreenshot.swift` exists in the UI test target.
- `ScreenshotCatalogTests` compiles and runs unchanged, just using
  the shared helper.
- Forcing one test to fail produces a `FAILURE-*` attachment in the
  xcresult.
- iOS UI-test target build green.

Milestone: `milestone-18-test-tooling-debt`
