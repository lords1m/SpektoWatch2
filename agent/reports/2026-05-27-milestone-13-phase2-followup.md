# Milestone 13 — Phase 2 follow-up (2026-05-27)

Addendum to `agent/reports/2026-05-21-milestone-13-acceptance.md`.
Documents the cross-task Phase 2 / forwarder-deletion work that
landed since 2026-05-21, plus updated M13 status.

## Branch

`redesign/liquid-glass` (unchanged).

## Scope

Two task-specific Phase 2 efforts completed code-side:

- **task-4 — LiveAcousticState**: full Phase 2 widget migration +
  liveBridge removal + forwarder deletion.
- **task-5 — RecordingCoordinator**: Phase 1.5 forwarder deletion +
  audio-thread mirror sinks. Phase 2 (start/stop orchestration into
  the coordinator) routed to backlog.

No other M13 task touched.

## task-4 — LiveAcousticState Phase 2

Closed code-side over multiple /acp-proceed passes (2026-05-25 →
2026-05-27).

### Widget migrations (7 widgets + 1 helper)

Every non-deactivated widget that previously held
`@ObservedObject var audioEngine: AudioEngine` migrated to observe
`LiveAcousticState` directly. Engine settings (`engineStatus`,
`frequencyWeighting`, `timeWeighting`, `scrollSpeed`,
`spectrogramFrequencySmoothing`) tracked in `@State` via `.onReceive`
on stored `Published<…>.Publisher` projections — widgets no longer
re-render on every 15 Hz live tick via the engine's
`objectWillChange`.

| Widget                                       | Migration |
|----------------------------------------------|-----------|
| `LevelMeterWidget` (AudioWidgets.swift)      | 2026-05-25 |
| `FrequencySpectrumWidget` (AudioWidgets.swift) | 2026-05-25 |
| `SingleValueWidget`                          | 2026-05-27 |
| `LevelHistoryWidget` (LAFGraphWidget.swift)  | 2026-05-27 |
| `LevelHistoryView` (LAFGraphView.swift)      | 2026-05-27 |
| `WaterfallWidget` (WaterfallView.swift)      | 2026-05-27 |
| `SpectrogramWidget`                          | 2026-05-27 |
| `CardMetaReader` (WidgetCardView.swift)      | 2026-05-27 |
| `OctaveBandWidget`                           | dead code (skipped) |
| `PhaseMeterWidget`                           | deactivated (skipped) |

### Bridge + forwarder removal

- `liveBridge` (the `live.objectWillChange` → `engine.objectWillChange`
  sink) deleted from `AudioEngine`. With every widget observing
  `LiveAcousticState` directly, the bridge had no live consumers.
- All external read sites for the 17 live properties migrated from
  `audioEngine.X` to `audioEngine.live.X`: AudioWidgets ×13,
  ControlBarView ×2, WaterfallView ×1.
- All AudioEngine internal writers / readers migrated from
  `self.X` to `self.live.X`.
- All 17 computed forwarders on AudioEngine deleted.

### LOC delta

| File                         | Phase-1 end | After Phase-2 | Delta |
|------------------------------|------------:|--------------:|------:|
| AudioEngine.swift            | 1753        | 1921          | +168  |
| LiveAcousticState.swift      | 61 (new)    | 61            |   0   |

AudioEngine net-grew from Phase-1 baseline (+168) because the
LiveAcousticState extraction added storage + bridge + 17 forwarders
in Phase 1; the Phase 2 cleanup recovered 75 LOC (1996 → 1921) by
removing those forwarders + the bridge but did not return AudioEngine
to its pre-task-4 size. Net win is **architectural**, not LOC: 17
`@Published` properties + their objectWillChange path live on a
focused state object; widget re-render breadth is bounded by what
each widget actually observes, not "everything the engine touches".

## task-5 — RecordingCoordinator Phase 1.5

- 3 computed forwarders (`isRecordingToFile`, `isMeasurementRecording`,
  `recordingDuration`) deleted from AudioEngine.
- Audio-thread mirror locks (`audioThreadIsRecordingToFile`,
  `audioThreadIsMeasurementRecording`) now updated via Combine sinks
  on `recording.$isRecordingToFile` / `$isMeasurementRecording`,
  replacing the former forwarder-setter side effects with functional
  parity.
- All external call sites migrated to `audioEngine.recording.X`:
  DashboardViewModel ×3, ControlBarView ×7.
- AudioEngine internal writers/readers migrated to
  `self.recording.X` / `recording.X`.
- `recordingBridge` (republishes `recording.objectWillChange` on
  the engine) **kept**: PlayPauseButton, RecordStopButton, and other
  views still observe `audioEngine` for recording-state changes.
  Deleting the bridge would require those views to add their own
  `@ObservedObject var recording: RecordingCoordinator` and is out
  of scope for this pass.

### LOC delta

| File              | Before this pass | After | Delta |
|-------------------|-----------------:|------:|------:|
| AudioEngine.swift | 1921             | 1925  | +4    |

Near-zero because the audio-thread-mirror sinks add roughly as many
lines as the deleted forwarders had.

### task-5 Phase 2

`startRecording` / `stopRecording` orchestration into the coordinator
is **routed to backlog**, matching the M13 pattern (task-3 / task-6
/ task-7 / task-8 all completed code-side with Phase 2 deferred).
Rationale:

- The methods orchestrate the AVAudioEngine session itself (session
  category, tap install, format negotiation, permission flow,
  `startAudioCapture`, `startRealRecording`, `resetMetrics`,
  `setupRecordingFile`).
- Moving them cleanly requires either:
  - Coupling the coordinator back to AudioEngine via a weak ref, or
  - Designing a narrow start/stop AV-graph protocol the engine
    implements and the coordinator calls.
- Hardware acceptance risk is high (recording correctness across
  permission edge-cases, mid-session writer close, watch-mic source
  switching).

## Architecture pressures — updated

| Pressure | Status at 2026-05-21 | Status now |
|----------|---------------------|------------|
| 1. AudioEngine god-object — LOC ≤ 1300 | Not met (1791) | Not met (1925) — only task-5 Phase 2 can close this |
| 1. AudioEngine god-object — ≥ 12 @Published moved out | Met (12) | Met (20: 17 in LiveAcousticState + 3 in RecordingCoordinator) |
| 2. DI: SpektoWatch2App uses AppServices | Met | Met |
| 3. DSP in view bodies — band aggregation deduped | Met | Met |
| 4. Persistence registry | Met (Phase 1) | Met |
| 5. Watch protocol version byte + AppState envelope | Met (Phase 1) | Met |

## M13 task status

| Task | Status |
|------|--------|
| task-1 AppServices injection                 | completed |
| task-2 RecordingDetailView split             | completed (Phase 2 deferred to backlog) |
| task-3 CalibrationProvider                   | completed |
| task-4 LiveAcousticState                     | **completed code-side 2026-05-27** |
| task-5 RecordingCoordinator                  | **completed code-side 2026-05-27** (Phase 2 backlog) |
| task-6 Kernel math                           | completed |
| task-7 Watch protocol versioning             | completed (Phase 2 deferred) |
| task-8 Persistence registry                  | completed (Phase 2 deferred) |
| task-9 Acceptance                            | in_progress (parked: hardware-only) |

**M13 8/9 code-side complete.** Only task-9's hardware checklist
remains:

- Cold-launch parity (pre-M13 → M13 build).
- Audio correctness (LAF / LAeq / LCpeak at reference signal).
- Widget render parity across 11 types × allowed size ranges.
- Recording flow end-to-end (start / stop / save / playback).
- Watch app + iOS accent sync (faces 4a/4b/4c).
- Instruments re-render comparison (the Phase 2 win — should see
  drop in widget re-renders per second against the pre-Phase-2
  baseline).

## Validation

- `xcodebuild -scheme SpektoWatch2 -destination 'generic/platform=iOS Simulator' build` → `** BUILD SUCCEEDED **` after each landing.
- `xcodebuild -scheme "SpektoWatch Watch App" -destination 'generic/platform=watchOS Simulator' build` → `** BUILD SUCCEEDED **` after the task-5 pass.
- No new tests written this round (structural-only changes); existing test surface unchanged.

## Risks / known gaps

- **AudioEngine.swift still > 1300 LOC target.** Closing pressure 1's
  LOC criterion requires task-5 Phase 2.
- **`recordingBridge` still in place.** Functionally correct but
  carries some live-tick re-render breadth for views that observe
  `audioEngine` for recording state. Removing it requires migrating
  PlayPauseButton, RecordStopButton, and ControlBarView's main view
  to observe `RecordingCoordinator` directly.
- **Hardware acceptance** for task-4's Instruments win is the
  single biggest unblockable validation gap — gated on the
  hardware checklist under task-9. The committed-screenshot
  workaround in `agent/screenshots/` covers static UI parity but
  not the re-render measurement.

## Next architecturally

- Schedule task-5 Phase 2 (AVAudioEngine start/stop into the
  coordinator) as a new milestone or M13 follow-up. Pair it with
  PlayPauseButton / RecordStopButton migration so the
  `recordingBridge` can be deleted at the same time.
- task-9 hardware session unblocks all M13 acceptance closures
  including the Instruments re-render baseline.
- Backlog items A9–A14 still recorded as backlog with rationale.
