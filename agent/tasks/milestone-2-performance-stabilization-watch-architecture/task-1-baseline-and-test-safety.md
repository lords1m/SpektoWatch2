# Task 1: Baseline And Test Safety

Status: completed  
Created: 2026-05-11  
Completed: 2026-05-11  
Milestone: `milestone-2-performance-stabilization-watch-architecture`

## Objective

Establish a safe baseline before changing audio hot paths or watch transport.

## Scope

- Review current uncommitted app/test changes and avoid overwriting user work.
- Confirm the active test plan and target test commands.
- Run or document the targeted tests that are feasible in the current
  environment.
- Capture baseline performance expectations from `PERFORMANCE_REVIEW.md` and
  existing `PerformanceProfilingTests`.

## Acceptance

- Current dirty files are understood and not reverted.
- A repeatable validation command is recorded for this milestone.
- Any unavailable simulator/device requirement is documented.
- The next implementation task can start without guessing which tests protect
  the audio and recording path.

## Suggested Validation

Use `SpektoWatch2.xctestplan` when running the broad suite. At minimum, target:

- `AudioEngineTests`
- `FFTProcessorTests`
- `FrequencyWeightingTests`
- `MeasurementDataIOTests`
- `WatchConnectivityTests`
- `PerformanceProfilingTests`

## Baseline Result

Dirty files present before implementation work:

- `SpektoWatch2/Views/RecordingDetailView.swift`
- `SpektoWatch2/WaterfallDataBuilder.swift`
- `SpektoWatch2/WaterfallView.swift`
- `SpektoWatch2/WidgetCardView.swift`
- `SpektoWatch2/WidgetConfiguration.swift`
- `SpektoWatch2/WidgetPickerView.swift`
- `SpektoWatch2/WidgetSettingsView.swift`
- `SpektoWatch2Tests/IntegrationTests.swift`
- `SpektoWatch2Tests/PerformanceProfilingTests.swift`
- `.claude/`
- `AGENT.md`
- `agent/`

The root `SpektoWatch2.xctestplan` and
`.claude/worktrees/nostalgic-jackson/SpektoWatch2.xctestplan` are identical.
The plan includes `SpektoWatch2Tests` and `SpektoWatch2UITests`, enables code
coverage for `SpektoWatch2`, uses random execution ordering, and enables
timeouts.

Target destination selected for the milestone baseline:

```sh
platform=iOS Simulator,name=iPhone 12 mini,OS=26.3.1
```

Build baseline command:

```sh
xcodebuild build-for-testing -project SpektoWatch2.xcodeproj -scheme SpektoWatch2 -testPlan SpektoWatch2 -destination "platform=iOS Simulator,name=iPhone 12 mini,OS=26.3.1"
```

Result: `TEST BUILD SUCCEEDED`.

Targeted test command attempted:

```sh
xcodebuild test -project SpektoWatch2.xcodeproj -scheme SpektoWatch2 -testPlan SpektoWatch2 -destination "platform=iOS Simulator,name=iPhone 12 mini,OS=26.3.1" -only-testing:SpektoWatch2Tests/AudioEngineTests -only-testing:SpektoWatch2Tests/FFTProcessorTests -only-testing:SpektoWatch2Tests/FrequencyWeightingTests -only-testing:SpektoWatch2Tests/MeasurementDataIOTests -only-testing:SpektoWatch2Tests/WatchConnectivityTests -only-testing:SpektoWatch2Tests/PerformanceProfilingTests -resultBundlePath /private/tmp/SpektoWatch2BaselineTask1-20260511b.xcresult
```

Result: blocked before test results. The first sandboxed run could not access
CoreSimulator. The escalated run built successfully but stalled during simulator
launch and was stopped after several minutes. Xcode reported:

```text
Failed to launch app with identifier: BrandtAcoustics.SpektoWatch2
NSMachErrorDomain Code=-308 "(ipc/mig) server died"
```

Baseline conclusion: the project currently compiles for targeted tests on the
iPhone 12 mini simulator. Runtime test execution needs a healthy CoreSimulator
launch environment before it can be used as a milestone gate.
