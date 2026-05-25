# Task 7: Expand UI Test Screenshot Coverage

Status: pending
Created: 2026-05-25

## Goal

Extend the auto-screenshot pattern beyond `ScreenshotCatalogTests` so
every important user flow ships a labeled screenshot per significant
state transition.

## Source

User request 2026-05-25 (Track B of M18). Builds on task-6's shared
helper.

Today the catalog test covers: dashboard default, edit mode, widget
settings, widget picker, app settings (top + bottom), recordings list,
recording detail, layouts menu / dialog, empty dashboard. **Missing**:
recording lifecycle (start → in-progress → stop), export flow (PDF +
CSV + spectrogram image with overlay states), playback-weighting
picker, dashboard preset rail across compositions, tweaks panel,
watch face previews where reachable from iOS sim.

## Sub-items

- **Sub-1**: Add `RecordingFlowScreenshotTests.swift` — drives the
  recording start button, samples 1 s of "audio" via the existing
  `-SeedTestData YES` fixture mode (or new
  `-SeedRecordingState=running` flag if needed), screenshots in-progress
  state, taps stop, screenshots the post-stop confirmation, navigates
  to the recording detail. ~5 screenshots per test.
- **Sub-2**: Add `ExportFlowScreenshotTests.swift` — opens a seeded
  recording detail, taps PDF export, screenshots the export overlay,
  taps Abbrechen, screenshots the cleared state; repeats for CSV and
  spectrogram PNG export. ~6 screenshots.
- **Sub-3**: Add `WeightingPickerScreenshotTests.swift` — cycles
  Z / A / C / Z weighting in the recording detail playback section,
  screenshots each. ~4 screenshots.
- **Sub-4**: Audit the existing `SpektoWatch2UITests.swift` and
  `WatchAppScreenshotTests.swift` — for every test that drives more
  than 2 UI states without screenshotting them, insert
  `capture("StepN-Description")` calls at the natural assertion anchors.
- **Sub-5**: Wire `XCTContext.runActivity(named:)` around each
  screenshot so the xcresult tree groups attachments per logical step.
  Names should be `NN-StepName` (e.g. `01-Dashboard-Default`,
  `02-StartRecording-Tap`) to keep filename ordering stable.
- **Sub-6**: Add a `-SeedTestData YES` recipe note in
  `SpektoWatch2UITests/README` (create the file if absent) listing
  what test data and recording state each launch arg seeds.

## Acceptance

- Three new test files in `SpektoWatch2UITests/` covering recording
  flow, export flow, weighting picker.
- Total screenshot count across the UI-test bundle ≥ 25 (currently
  ~12 from ScreenshotCatalog).
- Every test produces at least one screenshot.
- iOS UI-test target build green; tests pass on the iOS Simulator
  (or cleanly skip on hosts without microphone access where applicable).

Milestone: `milestone-18-test-tooling-debt`
