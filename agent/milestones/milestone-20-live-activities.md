# Milestone 20: Live Activities

Status: in_progress
Created: 2026-05-30
Priority: medium
Estimated: 0.5 weeks

## Goal

Add an iOS Live Activity that surfaces an active measurement session on the
Lock Screen and in the Dynamic Island: live broadband level dB(weighting),
peak, elapsed time, and recording/paused state — without the user opening
the app.

## Why now

The app already computes every metric a Live Activity needs (broadband level,
LCpeak, weighting) and has a clean recording lifecycle in `RecordingManager`.
Live Activities are a high-visibility, self-contained feature that needs no
App Group (ActivityKit runs in-process and the OS relays pushed state to the
extension). Chosen by the user as the next new code scope after the M9/M19
hardware-gated work stalled.

## Scope

- `Shared/MeasurementActivityAttributes.swift` — `ActivityAttributes`
  conformance shared by app + extension. Static: session title + start date
  (drives the auto-updating elapsed timer). Dynamic `ContentState`: level,
  peak, weighting, paused flag.
- `SpektoWatch2/LiveActivity/MeasurementLiveActivityController.swift` —
  `@MainActor` singleton owning `start` / `update` (throttled to 1 Hz) /
  `end`. Failures logged + swallowed so the recording path is never affected.
- `RecordingManager` wiring: start the activity on `startRecording`, push
  throttled metrics from the existing 0.1 s duration timer (reading
  `audioEngine.live.currentLevel` / `.currentPeakLevel`), end on
  `stopRecording`.
- `INFOPLIST_KEY_NSSupportsLiveActivities = YES` on the iOS app target
  (Debug + Release).
- `SpektoWatchLiveActivity/MeasurementLiveActivityWidget.swift` — staged
  `ActivityConfiguration` UI (Lock Screen + Dynamic Island compact / minimal
  / expanded). Not yet compiled; belongs to a widget extension target that
  must be created manually in Xcode.

## Hard prerequisite (manual, cannot be automated safely)

The Live Activity UI **must** live in a Widget Extension target. Creating an
Xcode target by editing `project.pbxproj` from text tools is high-risk
(especially with uncommitted user changes in the pbxproj), so it is left as a
manual Xcode step documented in task-2. Until that target exists, the
controller's `Activity.request` runs but there is no UI to render.

## Acceptance

- App + watchOS builds green with the controller and attributes compiled in
  (watchOS excludes the shared file via `#if canImport(ActivityKit)`).
- After the extension is created (task-2): start a recording on a device →
  Live Activity appears on the Lock Screen and Dynamic Island; level/peak
  update ~1 Hz; elapsed timer counts up; activity ends when recording stops.

## Tasks

1. task-1 — Attributes, controller, RecordingManager wiring, Info.plist key,
   staged widget UI. (code-side)
2. task-2 — Widget extension target creation + on-device acceptance. (manual
   Xcode + hardware)
