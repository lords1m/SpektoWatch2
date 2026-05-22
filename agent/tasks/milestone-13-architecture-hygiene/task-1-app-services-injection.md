# Task 1: AppServices injection layer

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-13-architecture-hygiene`
Source finding: A7 in `2026-05-21-architecture-review.md`

## Goal

Replace the 7 hand-wired `.environmentObject(...)` calls in
`SpektoWatch2App` with a single `AppServices` container.

## Landed (2026-05-21)

- New `SpektoWatch2/AppServices.swift` —
  `@MainActor final class AppServices: ObservableObject` owning:
  - `BandstopFilterManager`
  - `WatchConnectivityManager`
  - `RecordingManager`
  - `FFTConfiguration`
  - `MaskingProfileManager`
  - Deferred `AudioEngine?` + `MaskingEngine?` exposed as
    `@Published` (constructed via `startAudio()`, idempotent).
- Convenience no-arg `init()` constructs every sub-service with
  its default initializer (defined inside the MainActor class so
  the MainActor-isolated sub-service inits compile cleanly).
- `AppServices.testFixture(...)` static factory for test
  scaffolding — synchronous construction including AudioEngine +
  MaskingEngine (no deferred startup); each sub-service is
  overridable for targeted tests.
- `SpektoWatch2App` refactored:
  - One `@StateObject var services = AppServices()`.
  - Body conditions on `services.audioEngine` /
    `services.maskingEngine`.
  - First-frame `services.startAudio()` replaces the old
    `engineContainer.createEngine(...)`.
  - Per-task non-goal: consumer views still pull individual
    services via `@EnvironmentObject`, so the body still calls
    `.environmentObject(...)` for each of the 7 (plus the new
    `services`). Migration to a single environment object is
    deferred to a future polish task — the producer side is
    consolidated; consumer migration would touch dozens of views
    and was explicitly out of scope.
- The old private `AudioEngineContainer` type is gone; its logic
  lives in `AppServices.startAudio()`.

## Validation

- `xcodebuild -scheme SpektoWatch2 -destination 'generic/platform=
  iOS Simulator' build` → `** BUILD SUCCEEDED **`.
- No consumer view touched; behavior is unchanged.
- Local simulator broken (AGENT.md); functional acceptance still
  gated on hardware (task-9).

## Acceptance status

- [x] `SpektoWatch2App.body` shows one `AppServices` construction.
- [x] iOS build green.
- [ ] Existing tests pass — code-side OK; can't run locally per
  AGENT.md. Will verify in Xcode Cloud / on hardware.
- [ ] `SnapshotTestSupport` uses `AppServices.testFixture(...)` —
  **deferred**: existing tests construct managers manually
  (`AudioEngineTests`, `IntegrationTests`, `PerformanceMetricsTests`,
  `PDFReportGeneratorTests` all do this). Migrating them is a
  drop-in pattern but adds churn across 5+ test files; scope it as
  a follow-up so this task stays minimal. The fixture exists and
  is documented; tests can adopt it incrementally.

## Notes for follow-up tasks

- `SpektoWatch2App.body` still calls 8 `.environmentObject(...)`
  (one new + 7 existing). To reduce this to 1, every consumer
  view's `@EnvironmentObject var foo: Foo` would need to become
  `@EnvironmentObject var services: AppServices` + reading
  `services.foo`. That's the next consolidation step.
- Test fixture migration (the deferred acceptance item) can land
  alongside any test that's modified in M13 task-3 / task-4
  (AudioEngine extracts).
