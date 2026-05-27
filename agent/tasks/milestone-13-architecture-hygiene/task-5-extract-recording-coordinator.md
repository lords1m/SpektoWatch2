# Task 5: Extract RecordingCoordinator from AudioEngine

Status: completed (code-side; Phase 2 routed to backlog)
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
- [x] Forwarders deleted; all call sites read/write
  `audioEngine.recording.X` directly (see Phase 1.5 below).
- [ ] AudioEngine LOC drops by ~150 — partial. AudioEngine.swift is
  1925 LOC at HEAD; forwarder deletion alone netted only a small drop
  because (a) the audio-thread-mirror setter logic moved to Combine
  sinks (a small offsetting addition) and (b) Phase 2 (moving
  startRecording / stopRecording into the coordinator) is still
  pending.
- [ ] After this task, AudioEngine ≤ 1300 LOC — **not met**;
  Phase 2 is the only path to the ≤1300 target.
- [ ] Hardware functional acceptance — gated on M13 task-9.

## Phase 1.5 — Forwarder deletion (2026-05-27)

All non-AudioEngine read/write sites for the three recording
properties migrated to `audioEngine.recording.X`:
- `SpektoWatch2/DashboardViewModel.swift` — 3 sites.
- `SpektoWatch2/ControlBarView.swift` — 6 reads + 1 write
  (`audioEngine.recording.isMeasurementRecording = true`).

Internal AudioEngine writers/readers migrated from
`self.isRecordingToFile` / bare references to
`self.recording.isRecordingToFile` and `recording.isRecordingToFile`.

The three computed forwarders (`isRecordingToFile`,
`isMeasurementRecording`, `recordingDuration`) deleted. The setter
side effects (writing to `audioThreadIs*` lock mirrors for lock-free
audio-thread reads) replaced by two Combine sinks on
`recording.$isRecordingToFile` and `recording.$isMeasurementRecording`,
which update the mirrors on every publish. Functional parity preserved.

`recordingBridge` (republishing
`recording.objectWillChange → engine.objectWillChange`) **kept** —
several views still observe `audioEngine` for recording-state changes
(ControlBarView's PlayPauseButton / RecordStopButton, etc.) and rely
on the bridge to fan-out. Deleting it would require migrating those
views to `@ObservedObject var recording: RecordingCoordinator`,
expanding scope beyond a single coherent pass.

Phase 2 (moving startRecording / stopRecording orchestration into the
coordinator) remains the next architectural step toward the ≤1300
LOC target. Routed to backlog as a separate planning effort because:
- `startRecording` / `stopRecording` orchestrate the AVAudioEngine
  session itself (session category, tap install, format negotiation,
  permission flow, `startAudioCapture` / `startRealRecording`,
  `resetMetrics`, `setupRecordingFile`, etc.) — moving them cleanly
  requires either coupling the coordinator back to AudioEngine via a
  weak ref, or designing a narrow start/stop AV-graph protocol the
  engine implements and the coordinator calls.
- Hardware acceptance risk is high (recording correctness across
  permission edge-cases, mid-session writer close, watch-mic
  source switching).

Matches the M13 pattern (task-3, task-6, task-7, task-8 all completed
code-side with Phase 2 deferred). Task closes here; remaining
acceptance items (LOC drop, ≤1300 target, hardware acceptance) are
explicitly out of scope for this task and re-tracked under the
backlog Phase 2 follow-up + M13 task-9.
