# Task 1: AppServices injection layer

Status: pending
Created: 2026-05-21
Milestone: `milestone-13-architecture-hygiene`
Source finding: A7 in `2026-05-21-architecture-review.md`

## Goal

Replace the 7 hand-wired `.environmentObject(...)` calls in
`SpektoWatch2App` with a single `AppServices` container. Reduces
boilerplate for adding the next service and gives tests one type to
construct instead of seven.

## Scope

- New `SpektoWatch2/AppServices.swift` — a `final class
  AppServices: ObservableObject` holding the existing managers
  (`BandstopFilterManager`, `WatchConnectivityManager`,
  `RecordingManager`, `FFTConfiguration`, audio engine,
  `MaskingEngine`, `MaskingProfileManager`).
- `SpektoWatch2App.body` constructs one `AppServices` and pushes
  one `@EnvironmentObject` instead of seven.
- Existing consumer views keep their `@EnvironmentObject` for the
  specific service they need — `AppServices` is the producer, not
  a service locator. Migration is incremental.
- Add a convenience initializer
  `AppServices.testFixture(audioEngine: AudioEngine = …)` for
  test scaffolding (replaces the hand-graph in
  `SpektoWatch2Tests/SnapshotTestSupport.swift`).

## Non-Goals

- Changing how individual views consume services (no
  `@Environment(\.appServices)` migration in this task).
- Defining service protocols / abstractions (that's task A14,
  deferred backlog).

## Acceptance

- `SpektoWatch2App.body` shows one `AppServices` construction +
  one `.environmentObject(services)` (services may still spread
  their individual managers downstream — see Non-Goals).
- iOS + watchOS builds green.
- All existing tests pass.
- SnapshotTestSupport uses `AppServices.testFixture(...)`.
