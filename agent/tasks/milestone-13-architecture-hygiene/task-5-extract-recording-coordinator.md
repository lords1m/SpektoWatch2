# Task 5: Extract RecordingCoordinator from AudioEngine

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-13-architecture-hygiene`
Source finding: A1 phase 3 in `2026-05-21-architecture-review.md`
Depends on: task-4.

## Goal

Pull recording start/stop control + `recordingDuration` ticker out
of AudioEngine into a focused coordinator. Third phase of the
AudioEngine decomposition.

## Landed (2026-05-21) — Phase 1: state extraction

Same conservative-extraction pattern as task-3 (CalibrationProvider)
and task-4 (LiveAcousticState): the storage moves to a focused
type; AudioEngine keeps forwarders + bridge so existing call sites
work unchanged.

### New file

- `SpektoWatch2/RecordingCoordinator.swift` (37 LOC).
  `final class RecordingCoordinator: ObservableObject` exposing
  three `@Published` properties:
  - `isRecordingToFile: Bool`
  - `isMeasurementRecording: Bool`
  - `recordingDuration: TimeInterval`

### AudioEngine changes

- New `let recording = RecordingCoordinator()` — storage now lives
  here.
- 3 computed forwarders replace the 3 `@Published` declarations.
  Every existing read site (ControlBarView, DashboardViewModel,
  WaterfallView, the audio frame writers) and every write site
  keeps compiling unchanged.
- `recordingBridge: AnyCancellable` republishes the coordinator's
  `objectWillChange` on the engine's own — existing
  `@ObservedObject var audioEngine` consumers still update.
- `measurementRecordingSink: AnyCancellable` replaces the
  `isMeasurementRecording` didSet logic. The Combine subscription
  runs the same `setupMeasurementDataFileIfNeeded` /
  `closeMeasurementWriter` side effects when the flag flips,
  gated on `recording.isRecordingToFile` to match the original
  semantics exactly. `.dropFirst()` skips the initial-value
  emission.

### Phase 2 — Control methods (deferred)

The original task spec called for moving `startRecording()` /
`stopRecording()` / `cancelRecording()` into the coordinator
along with the duration ticker. Those methods stay on AudioEngine
because they orchestrate the AVAudioEngine session itself
(audio-session category, tap install, format negotiation,
permission flow) — moving them cleanly requires inverting the
relationship between AudioEngine and the coordinator (the
coordinator would need to call back into the engine for the
session lifecycle, or the engine would need to expose a narrow
"start/stop the AV graph" subset).

Phase 2 is a separate, larger refactor and is deferred. The state
extraction (Phase 1) is the prerequisite seam — same logic that
task-4 used.

### LOC delta

| File | Before | After | Delta |
|---|---:|---:|---:|
| AudioEngine.swift | 1753 | 1790 | **+37** |
| RecordingCoordinator.swift | — | 37 | +37 (new) |

Same pattern as task-4: AudioEngine grows because computed
forwarders + Combine wiring are more verbose than the original
`@Published` declarations. These forwarders are deletable code
once a Phase 2 effort either moves the start/stop methods into
the coordinator or migrates consumers to read
`audioEngine.recording.X` directly.

## Validation

- `xcodebuild -scheme SpektoWatch2 -destination 'generic/platform=
  iOS Simulator' build` → `** BUILD SUCCEEDED **`.
- `xcodebuild -scheme "SpektoWatch Watch App" -destination 'generic/
  platform=watchOS Simulator' build` → `** BUILD SUCCEEDED **`.
- All existing `audioEngine.isRecordingToFile` / `.isMeasurementRecording`
  / `.recordingDuration` read and write sites unchanged.
- Side-effect parity:
  - **Before**: didSet on `isMeasurementRecording` ran
    `setupMeasurementDataFileIfNeeded` / `closeMeasurementWriter`
    synchronously when the property changed, gated on
    `isRecordingToFile`.
  - **After**: Combine sink on `recording.$isMeasurementRecording`
    runs the same side effects, gated on the same flag, also
    synchronously on the publish.
- Hardware functional acceptance (does the file writer still
  close cleanly when the user toggles measurement recording
  mid-session?) gated on M13 task-9.

## Acceptance status

- [x] AudioEngine state for the three recording flags moved out.
- [x] Existing consumers keep working without migration.
- [x] iOS + watchOS builds green.
- [ ] AudioEngine LOC drops by ~150 — **not met in Phase 1**
  (+37 LOC because of forwarders). Phase 2 (moving startRecording
  / stopRecording into the coordinator, or migrating consumers
  to read `audioEngine.recording.X`) will close this.
- [ ] After this task, AudioEngine ≤ 1300 LOC — **not met**.
  Currently 1790. Phase 2 + the deletable forwarders from
  task-4 + task-5 would together approach the target.
- [ ] Hardware functional acceptance — gated on M13 task-9.

Task stays in_progress until Phase 2 lands or M13 task-9 promotes
based on hardware acceptance with the current seam.
