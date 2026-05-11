# Task 6: Watch Wearable Source Controls

Status: completed  
Created: 2026-05-11  
Completed: 2026-05-11  
Milestone: `milestone-2-performance-stabilization-watch-architecture`

## Objective

Prioritize Apple Watch microphone as a wearable source and allow watch-driven
recording control.

## Scope

- Confirm current watch microphone source flow.
- Ensure watch can start and stop phone recordings where supported.
- Keep companion display behavior intact.
- Keep standalone watch recording as a secondary follow-up, not the primary
  deliverable for this milestone.

## Acceptance

- Watch wearable-source path is clearly represented in code and tests/docs.
- Watch start/stop control semantics are explicit.
- Phone recording state remains consistent with watch control actions.
- No raw audio transfer is introduced.

## Non-Goals

- No watch complication implementation in this milestone unless all performance
  and transport tasks are complete.
- No full standalone watch persistence redesign.

## Implementation Notes

Watch-originated recording controls now carry an optional microphone source:

- source-qualified start/stop messages can identify `.appleWatch` as the
  wearable source while older unqualified messages remain valid
- watch record buttons request wearable start/stop, set the watch source
  explicitly, and continue to use processed `SpectrogramData` packets only
- iOS message handling forwards the requested source through the existing
  recording command notifications

`DashboardViewModel` now mirrors watch-originated source changes, treats
Apple Watch start commands as wearable-source live mode, and does not start the
iPhone microphone for that mode. File recording stops remain protected from
watch stop commands.

`AudioEngine` now has an explicit wearable live mode:

- `activeMicrophoneSource` records whether the running live path is iPhone or
  Apple Watch
- `startWearableLiveMode()` marks the dashboard as running without opening
  iPhone audio capture
- `ingestWearableSpectrogramData(_:)` feeds compact watch spectrogram packets
  into existing dashboard state, level history, spectrum, octave bands, and
  high-rate spectrogram subscribers

Standalone watch persistence remains out of scope.

Added focused tests for:

- source-qualified watch start/stop protocol messages
- wearable live mode state
- ingestion of compact Apple Watch spectrogram data into phone dashboard state

## Validation

Compile gate:

```sh
xcodebuild build-for-testing -project SpektoWatch2.xcodeproj -scheme SpektoWatch2 -testPlan SpektoWatch2 -destination "platform=iOS Simulator,name=iPhone 12 mini,OS=26.3.1"
```

Result: `TEST BUILD SUCCEEDED`.

Runtime targeted tests were not rerun because task 1 established that
CoreSimulator launch currently fails before producing unit-test results. Run the
new `WatchConnectivityTests` and `AudioEngineTests` cases once simulator launch
is healthy.
