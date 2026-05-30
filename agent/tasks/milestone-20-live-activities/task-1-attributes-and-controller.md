# Task 1: Attributes, Controller & Wiring

Status: completed
Created: 2026-05-30
Milestone: `milestone-20-live-activities`

## What landed (2026-05-30)

### New: `Shared/MeasurementActivityAttributes.swift`
`ActivityAttributes` conformance, guarded `#if canImport(ActivityKit)` so it
compiles to nothing on watchOS (the `Shared` group is a synchronized root
group included in the watch target). Static attributes: `sessionTitle`,
`startedAt`. Dynamic `ContentState`: `currentLevel`, `peakLevel`, `weighting`,
`isPaused`.

### New: `SpektoWatch2/LiveActivity/MeasurementLiveActivityController.swift`
`@MainActor` singleton. `start(sessionTitle:weighting:startedAt:)` calls
`Activity.request`; `update(...)` throttled to 1 Hz (ActivityKit rate-limits
high cadences) with a `force` escape for state transitions;
`end()` dismisses immediately. `isAvailable` reads
`ActivityAuthorizationInfo().areActivitiesEnabled`. All failures logged via
`Logger` and swallowed — the recording path never sees an error.

### Modified: `SpektoWatch2/RecordingManager.swift`
- `startRecording`: starts the activity with the current
  `audioEngine.frequencyWeighting.rawValue`; the existing 0.1 s duration
  `Timer` now also pushes `audioEngine.live.currentLevel` /
  `.currentPeakLevel` into the controller (weak `audioEngine` capture; the
  controller's internal throttle caps the effective rate at 1 Hz).
- `stopRecording`: ends the activity.
- All ActivityKit calls wrapped in `#if canImport(ActivityKit)`.

### Modified: `SpektoWatch2.xcodeproj/project.pbxproj`
`INFOPLIST_KEY_NSSupportsLiveActivities = YES` added to the iOS app target
Debug + Release configs (next to the existing `INFOPLIST_KEY_*` settings;
the app uses `GENERATE_INFOPLIST_FILE = YES`).

### Staged (NOT compiled): `SpektoWatchLiveActivity/MeasurementLiveActivityWidget.swift`
`ActivityConfiguration` with Lock Screen view + Dynamic Island
(compact/minimal/expanded). Lives in a new top-level folder that is **not** a
synchronized group, so it is excluded from every target until the widget
extension is created (task-2).

## Validation

- `xcodebuild build -scheme SpektoWatch2 -destination "generic/platform=iOS Simulator"` → **BUILD SUCCEEDED**
- `xcodebuild build -scheme "SpektoWatch Watch App" -destination "generic/platform=watchOS Simulator"` → **BUILD SUCCEEDED** (shared file correctly excluded on watchOS)

## Notes

The controller compiles and runs in the app without the extension; the
`Activity.request` call simply has no UI to render until task-2 lands. This is
intentional — it keeps the lifecycle code testable and committed while the
target-creation step (which cannot be safely automated) is deferred to a human
in Xcode.
