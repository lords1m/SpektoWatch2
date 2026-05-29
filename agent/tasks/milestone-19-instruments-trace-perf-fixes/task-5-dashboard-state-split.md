# Task 5: Split Audio State from Dashboard Layout State

Status: completed
Created: 2026-05-29
Priority: P2

## Problem

The 2026-05-29 trace shows **31 samples** of
`ModularDashboardView.mainBody.getter` and **47 samples** of
`ButtonBehavior.body.getter` — buttons in the dashboard re-evaluate their
body on every audio frame update.

Contributing hot frames:
- `DashboardManager.activeLayoutIndex.getter` — 7 samples
- `DashboardManager.isEditMode.getter` — 6 samples
- `DashboardManager.layouts.getter` — 11 samples
- `DashboardLayout.init(from:)` — 8 samples (re-decode from JSON?)

Root cause: `DashboardManager` (or `LiveAcousticState`) publishes audio-
frame data (level, spectrogram, FFT) as `@Published`/`@Observable`
properties on the same object that also owns `activeLayoutIndex`,
`isEditMode`, and `layouts`. SwiftUI's observation system marks the entire
object dirty on every audio callback, triggering re-evaluation of the
entire dashboard view tree including buttons, layout selectors, and the
header bar.

Note: M13 task-4 introduced `LiveAcousticState` to separate live audio
data from `AudioEngine`. This task adds the corresponding **view-side
guard** — ensuring `ModularDashboardView` and `DashboardManager` getters
are not in the dependency graph of audio-frame updates.

## Acceptance

- `ModularDashboardView.mainBody.getter` does not appear in Time Profiler
  samples caused solely by audio callbacks (no user interaction) in a
  re-trace; it appears only when layout/edit state actually changes.
- `ButtonBehavior.body.getter` drops below 5 samples in a 76-second
  re-trace under steady audio without user interaction.
- `DashboardManager.activeLayoutIndex`, `isEditMode`, and `layouts`
  changes are not triggered by audio-frame publishes.
- iOS build succeeds; edit mode, layout switching, and widget add/remove
  work correctly.

## Implementation notes

- Audit `DashboardManager`: identify which `@Published` / `@Observable`
  properties carry audio data vs. layout/edit data.
- If audio data is still flowing through `DashboardManager` (rather than
  `LiveAcousticState`), move it to `LiveAcousticState` (M13 task-4
  already created the seam; verify all callsites are migrated).
- In `ModularDashboardView`, ensure the view observes `LiveAcousticState`
  only for the audio sub-views (widget content) and observes
  `DashboardManager` only for layout/edit state. Use separate `@State`
  or `@Environment` paths for each.
- For `ButtonBehavior`: buttons in the header / toolbar observe
  `DashboardManager.isEditMode` and `activeLayoutIndex`. Wrap those
  sub-views with `.equatable()` or extract them into dedicated views
  with `Equatable` conformance so SwiftUI skips body re-evaluation when
  the value has not changed.
- Check if `DashboardLayout.init(from:)` is being called during each
  render cycle — this indicates JSON re-decoding on every update (see
  also task-1 for the launch-time version of this bug).

Milestone: `milestone-19-instruments-trace-perf-fixes`
Source: 2026-05-29 Instruments trace — 31 ModularDashboardView + 47
ButtonBehavior samples from audio-frame updates
