# Task 7: Acceptance And Compatibility

Status: completed  
Created: 2026-05-11  
Completed: 2026-05-11  
Milestone: `milestone-2-performance-stabilization-watch-architecture`

## Objective

Close the milestone with compatibility checks, acceptance evidence, and updated
ACP state.

## Scope

- Run targeted automated tests.
- Verify existing `.spekto` files remain readable.
- Document manual acceptance against an external sound level meter if hardware
  is available.
- Update ACP task statuses and produce a handoff report.

## Acceptance

- The targeted automated test set passes, or failures are triaged with file and
  behavior references.
- Existing recording compatibility is verified.
- Manual acceptance is documented or blocked by missing physical hardware.
- `agent/progress.yaml` reflects the next milestone or task.

## Non-Goals

- Do not expand into masking implementation.
- Do not redesign reporting/export flows.

## Acceptance Evidence

Automated compile gate:

```sh
xcodebuild build-for-testing -project SpektoWatch2.xcodeproj -scheme SpektoWatch2 -testPlan SpektoWatch2 -destination "platform=iOS Simulator,name=iPhone 12 mini,OS=26.3.1"
```

Result: `TEST BUILD SUCCEEDED`.

Targeted runtime test attempt:

```sh
xcodebuild test-without-building -project SpektoWatch2.xcodeproj -scheme SpektoWatch2 -testPlan SpektoWatch2 -destination "platform=iOS Simulator,name=iPhone 12 mini,OS=26.3.1" -only-testing:SpektoWatch2Tests/WatchConnectivityTests -only-testing:SpektoWatch2Tests/AudioEngineTests -only-testing:SpektoWatch2Tests/FFTProcessorTests -only-testing:SpektoWatch2Tests/MeasurementDataIOTests -only-testing:SpektoWatch2Tests/PerformanceProfilingTests
```

Result: blocked before test execution. CoreSimulator failed to enumerate the
requested simulator:

- `CoreSimulatorService connection became invalid`
- `Unable to discover any Simulator runtimes`
- `Unable to find a device matching ... iPhone 12 mini, OS 26.3.1`

This is consistent with the simulator blocker documented in task 1.

## Compatibility

No committed `.spekto` fixture files were found in the workspace with:

```sh
rg --files -g "*.spekto"
```

Added `MeasurementDataIOTests.testReaderPreservesLegacyVersionOneSpektoFiles`,
which builds a synthetic v1 `.spekto` measurement file and verifies that
`MeasurementDataReader` preserves the legacy header/frame contract:

- version 1 is accepted
- full FFT is absent
- metric keys round-trip
- Z/A/C third-octave bands remain readable
- `fullFFT` remains empty for v1 files

The new compatibility test is compile-verified by the build-for-testing gate.
Runtime execution remains blocked by CoreSimulator availability.

## Manual Acceptance

Manual acceptance against a physical sound level meter, physical iPhone, and
Apple Watch was not run in this environment. Hardware acceptance remains a
follow-up:

- compare built-in iPhone readings against an external sound level meter
- record and reopen a measurement
- confirm recording UI remains smooth
- confirm Apple Watch wearable-source updates at least once per second

## Handoff Report

Created `agent/reports/2026-05-11-milestone-2-acceptance.md`.
