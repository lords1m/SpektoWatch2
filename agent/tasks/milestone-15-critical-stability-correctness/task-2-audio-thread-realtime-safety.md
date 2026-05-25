# Task 2: Audio-Thread Real-Time Safety

Status: completed
Created: 2026-05-23
Completed: 2026-05-24

## Outcome

All three sub-items landed 2026-05-24 in
`SpektoWatch2/AudioEngine.swift`.

- Sub-1 (file-I/O off render thread): the per-frame
  `setupMeasurementDataFileIfNeeded()` call inside `processFFTFrame`
  (formerly ~L1517) is deleted. Writer lifecycle is fully owned by
  the main-actor paths: `startAudioCapture` simulator branch
  (~L645), `startRealRecording` (~L1116), the live→recording
  transition (~L576), and the `measurementRecordingSink` Combine
  bridge in `RecordingCoordinator` (~L387). A disk failure at
  start-time leaves `measurementWriter == nil`; the
  `if let writer = measurementWriter` gate in `processFFTFrame`
  then short-circuits with no further allocation.
- Sub-2 (`NSLock` → `OSAllocatedUnfairLock`):
  `widgetSpectralWeightingsLock` is now an
  `OSAllocatedUnfairLock<Set<FrequencyWeighting>>`. The render-thread
  reader in `requiredSpectralWeightingsForCurrentFrame` uses
  `withLockUnchecked { $0 }`; the main-side setter
  `setWidgetSpectralWeightingRequirements(_:)` uses `withLock`.
  Negative grep on `AudioEngine.swift` confirms zero `NSLock`
  declarations remain (only two `NSLock` mentions are in comments
  describing the migration).
- Sub-3 (`sampleBuffer` mutations under `processingLock`):
  `processSamples` now wraps `append(contentsOf:)`, the dropping
  `sampleBufferOffset += samplesToDrop`, the absolute-compaction
  `removeFirst` / offset reset, and each loop iteration's
  read+copy+offset advance under `processingLock.withLockUnchecked`.
  The lock is released around `processFFTFrame` so we don't hold
  it across FFT / weighting work (which take their own snapshots).
  `hop` is hoisted out of the loop because it's now used in both
  the drop math and the loop body.

## Hardware acceptance pending

- Negative grep documented in handoff; manual stress test (start
  recording → toggle window size 10× while recording → no audio
  dropout, no crash) gated on a paired device session.


Milestone: `milestone-15-critical-stability-correctness`
Source: 2026-05-23 code review — DSP C1, C2, H4

## Goal

Close three real-time-safety violations on the AVAudioInputNode tap
callback path that slipped past M6 task-6's `NSLock` removal. All
three can produce audio glitches under load and threading races
against the configuration-change path.

## Scope

### Sub-1: Remove file-I/O from per-frame path (DSP C1, **Critical**)

`AudioEngine.processFFTFrame` calls `setupMeasurementDataFileIfNeeded()`
on every audio frame while `isRecordingToFile && isMeasurementRecording`
(~line 1517). The callee:
- allocates a `MeasurementDataWriter`
- touches `FileManager`
- writes to `UserDefaults`-adjacent state

All forbidden on the real-time audio thread (priority inversion,
unbounded latency, lock acquisition through file-system semaphores).

**Fix:** the writer is set up exactly once when recording starts. The
correct location is `startRecording` (main actor), which already
exists. Delete the per-frame check; rely on the start-side guarantee.
If the writer needs lazy initialization for any reason (e.g., it
depends on the first frame's sample rate), do it on the start-recording
hop, not in the tap callback.

### Sub-2: NSLock → OSAllocatedUnfairLock (DSP C2, **Critical**)

`AudioEngine.widgetSpectralWeightingsLock` is declared `NSLock` (~line
140). `requiredSpectralWeightingsForCurrentFrame()` is called from
`processFFTFrame` (audio thread) and acquires it. `NSLock` is
`pthread_mutex_lock` under the hood — blocking, priority-inversion
risk.

**Fix:** migrate to `OSAllocatedUnfairLock<State>` matching the
pattern already established for `processingLock` in M6 task-6. Use
the `withLockUnchecked` API for the audio-thread read path; use the
state-isolated API for the writer path on main.

Search the codebase for any other `NSLock` accessed from the audio
thread; the review found this one specifically but the audit was not
exhaustive on that surface.

### Sub-3: Guard `sampleBuffer` mutations (DSP H4, **High**)

`AudioEngine.processSamples` (called from the tap) mutates
`sampleBuffer` via `append(contentsOf:)` and the compaction loop
without holding `processingLock` (~line 1299). `applyFFTConfiguration`,
`setBlockSize`, and `setWindowFunction` reset the buffer under
`processingLock` on main. A reconfigure during a live tap callback
races on the Swift array's storage pointer.

**Fix:** wrap the `sampleBuffer` / `sampleBufferOffset` mutations in
`processSamples` under `processingLock.withLockUnchecked`. Keep the
critical section tight: only the array operations, not the downstream
FFT work which already takes its own snapshots.

## Acceptance

- [ ] Code grep confirms zero `NSLock` declarations reachable from
  the AVAudioInputNode tap path.
- [ ] Code grep confirms zero `FileManager` / `UserDefaults` calls
  inside `processFFTFrame` (and its callees) on the steady-state
  recording path.
- [ ] `sampleBuffer` and `sampleBufferOffset` mutations in
  `processSamples` are inside a `processingLock` critical section.
- [ ] Existing `AudioEngineTests`, `FFTProcessorTests`,
  `WaterfallDataBuilderTests`, `HighEndSpectrogramAdapterTests` all
  pass.
- [ ] Manual hardware stress test (documented in handoff report):
  start recording → toggle window size 10× while recording → no
  audio dropout, no crash.

## Files

- `SpektoWatch2/AudioEngine.swift`
- Possibly `SpektoWatch2/RecordingCoordinator.swift` (if writer-setup
  moves there)

## Verification

- iOS + watchOS builds green.
- Existing tests pass.
- Audio-thread negative grep (`grep -n "NSLock\|FileManager\|UserDefaults" `
  on the tap callback's transitive callees) returns empty.
- Hardware acceptance under stress documented in the handoff report.

## Risk

The per-frame `setupMeasurementDataFileIfNeeded` may have been load-
bearing for a corner case I haven't traced (e.g., late writer
construction after audio session interruption). Before deleting it,
audit every caller and the start-recording control flow to confirm the
writer is always alive whenever `isRecordingToFile` is true.
