# Milestone 13: Architecture Hygiene

Status: in_progress
Started: 2026-05-21
Priority: medium
Estimated: 3 weeks

## Goal

Address the five structural pressures identified in
`agent/reports/2026-05-21-architecture-review.md` that will become
friction at the next size step:

1. AudioEngine god-object (1761 LOC, 30+ `@Published`).
2. No dependency-injection layer (7 root `@EnvironmentObject`).
3. DSP entangled with view bodies.
4. Persistence split across 4 overlapping layers.
5. Watch ↔ iOS protocol with no version byte and no state envelope.

This milestone covers the **CLI-doable subset**: A1 (AudioEngine
decomposition), A4 (kernel math extraction), A5 (watch protocol
versioning), A6 (RecordingDetailView split), A7 (AppServices
injection), A8 (persistence registry).

Routed elsewhere, not re-tracked here:
- **A2 — App Group entitlements** stays under `M6 task-4`. Manual
  Xcode + Developer Portal work.
- **A3 — ToneGenerator NSLock + module extract** stays under
  `M11 task-1`.

Deferred as backlog (not in this milestone):
- A9 dedupe `WatchConnectivityManager`.
- A10 localization stance.
- A11 file/type rename pairs.
- A12 move `Shared/LoudnessCalculatorView.swift` out of Shared.
- A13 extract widget-body constants.
- A14 AudioEngine tests via protocol abstraction (depends on A1).

## Why

The architecture review identifies that the same patterns that
worked at the 5-feature scale of M1-M4 are producing friction now
at the 11-widget + watch + complications + recording + reports
scale of M5-M12:

- M12 task-8 had to remove `@ObservedObject` from `WidgetCardView`
  because AudioEngine's 15 Hz publish was re-rendering every card.
  That fix masked the disease.
- M12 spectrum "negative offset" bug came from band aggregation
  living in two places (AudioEngine + the widget Canvas closure).
- M12 watch faces 4a/4b/4c hardcoded phosphor because there's no
  way to send design tokens across the protocol.

The longer these patterns persist, the more expensive each new
widget / face / feature gets to land.

## Scope (tasks)

1. **AppServices injection layer (A7).** Replace 7
   `.environmentObject(...)` calls in `SpektoWatch2App` with one
   `AppServices` container. Pure refactor. Enables easier test setup.
2. **RecordingDetailView split (A6).** 1496 LOC → 5-6 files <300
   LOC each. Pure mechanical refactor.
3. **AudioEngine decomposition phase 1 — CalibrationProvider (A1
   partial).** Extract `calibrationOffset` + device-specific
   defaults + persistence into a separate ObservableObject.
4. **AudioEngine decomposition phase 2 — LiveAcousticState (A1
   partial).** Extract `currentLevel`, `currentPeakLevel`,
   `levelHistory`, `currentOctaveBands*`, `currentSpectrum` into a
   child ObservableObject so views can subscribe granularly.
5. **AudioEngine decomposition phase 3 — RecordingCoordinator (A1
   partial).** Extract recording start/stop + `recordingDuration`
   ticker into a separate type.
6. **Kernel math extraction (A4).** Move spectrum band
   aggregation, history clamping, and axis-tick computation out of
   view bodies into `Managers/`. Start with the spectrum band path
   (M12 bug site) and the LAF history path.
7. **Watch protocol version byte + state envelope (A5).** Add
   one-byte version prefix to `SpectrogramData.toBinaryData()`.
   Define `WatchAppState` envelope for non-audio state (active
   preset, recording state, tone state, design accent, theme).
   Reject mismatched versions gracefully.
8. **Persistence registry (A8).** Single declared inventory of
   UserDefaults / AppGroup / @AppStorage keys + their versions +
   migration rules. Migrate existing keys to use the registry.
9. **Acceptance.** Verify each refactor preserves behavior. Write
   handoff report. No new features in this milestone — pure
   structural work.

## Non-Goals

- Closing M6 task-4 App Group entitlements (manual Xcode work;
  routed there).
- Fixing ToneGenerator NSLock (routed to M11).
- Adding new features, widgets, or watch faces.
- Reworking the audio frame-processing hot path
  (`AudioEngine.processAudioBuffer`).
- Cross-target dedupe (`WatchConnectivityManager` consolidation
  — A9, backlog).
- Localization sweep (A10, backlog).
- File renames (A11, backlog).
- Tests for AudioEngine via protocol abstraction (A14, depends on
  A1, deferred to a follow-up milestone).

## Acceptance

- All eight refactor tasks land without behavior regressions.
- Build green on both iOS and watchOS targets.
- All existing snapshot + unit tests pass.
- Architecture review's structural pressures 1, 3, 4, 5
  substantially reduced (pressure 2 closed by task-1).
- Handoff report at `agent/reports/<date>-milestone-13-acceptance.md`
  documents what changed, what was deferred, and what the next
  architectural step is.

## Risk register

- **AudioEngine refactor (tasks 3/4/5)** touches the most
  performance-sensitive code in the app. Each phase must be
  independently shippable and verified on hardware before the
  next phase lands. If a phase regresses LAF computation or
  level metering, revert that phase and reassess.
- **Watch protocol versioning (task 7)** must remain
  backward-readable for at least one version. Otherwise a paired
  watch on an older build will silently fail to display data.
- **Persistence registry (task 8)** must not invalidate existing
  user data. Test cold-launch with simulated pre-M13 UserDefaults
  state before shipping.

## Files in this bundle

- This milestone file.
- 9 task files under `agent/tasks/milestone-13-architecture-hygiene/`.
- The architecture review (source design) at
  `agent/reports/2026-05-21-architecture-review.md`.
