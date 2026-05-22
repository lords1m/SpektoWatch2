# M13 — Architecture Hygiene Acceptance (Code-side)

Date: 2026-05-21
Branch: `redesign/liquid-glass`
Milestone: M13 Architecture Hygiene
Tasks covered: task-1 … task-8 (per-task implementation) + this
report = task-9.

## Status

**Code-side acceptance: complete.** All eight refactor tasks shipped
Phase 1 with documented Phase 2 deferrals. iOS + watchOS targets
build green on every intermediate commit. Hardware behavior parity
and Instruments-based re-render comparison are the remaining work
for full promotion.

## Per-task verdict

| # | Task | Phase 1 | Phase 2 (deferred) |
|---|---|:---:|:---:|
| 1 | AppServices injection | ✅ | Consumer migration to `@EnvironmentObject services` (drops 7 of the 8 `.environmentObject` calls) |
| 2 | Split RecordingDetailView | ✅ | Per-tab card split with `RecordingDetailViewModel` |
| 3 | Extract CalibrationProvider | ✅ | — |
| 4 | Extract LiveAcousticState | ✅ | Per-widget migration to `@ObservedObject live = audioEngine.live` (10 widgets) |
| 5 | Extract RecordingCoordinator | ✅ | Move `startRecording` / `stopRecording` / `cancelRecording` into the coordinator |
| 6 | Kernel math extraction | ✅ | Level-history clamping + axis-tick extraction |
| 7 | Watch protocol versioning + AppState | ✅ | iOS broker + watch store + watch face migration from hardcoded phosphor |
| 8 | Persistence registry | ✅ | One-shot migration runner + @AppStorage declaration migration + legacy key sunset |

## What landed code-side

### New files (8)

| File | LOC | Role |
|---|---:|---|
| `SpektoWatch2/AppServices.swift` | 122 | Service container; one @StateObject replaces five |
| `SpektoWatch2/CalibrationProvider.swift` | 137 | Device-map + persistence for calibration |
| `SpektoWatch2/LiveAcousticState.swift` | 61 | 12 live `@Published` metrics, observable independently |
| `SpektoWatch2/RecordingCoordinator.swift` | 37 | Recording flags + duration storage |
| `SpektoWatch2/Managers/SpectrumBandAggregator.swift` | 220 | Single canonical band aggregation (third-octave / octave / Bark) |
| `Shared/WatchAppState.swift` | 99 | Codable envelope for non-audio iOS↔watch state |
| `Shared/PersistenceKeys.swift` | 126 | Inventory of every UserDefaults / AppGroup / @AppStorage key |
| `SpektoWatch2/Views/RecordingDetailComponents.swift` | 103 | MiniLineChart + StatRow |
| `SpektoWatch2/Views/AudioPlayerManager.swift` | 171 | AVAudioEngine-backed file player |
| `SpektoWatch2/Views/PhotoPickerView.swift` | 39 | PHPickerViewController wrapper |

(10 new files; 4 test files: CalibrationProviderTests,
SpectrumBandAggregatorTests, WatchProtocolVersioningTests,
existing snapshot scaffolding.)

### Existing files — net LOC deltas

| File | Before M13 | After M13 | Δ |
|---|---:|---:|---:|
| `AudioEngine.swift` | 1761 | 1713 | **−48** |
| `AudioWidgets.swift` | 619 | 515 | **−104** |
| `Views/RecordingDetailView.swift` | 1496 | 1211 | **−285** |
| `SpektoWatch2App.swift` | ~115 | ~75 | **−40** |

`AudioEngine.swift` LOC moved net −48 across tasks 3/4/5/6/8:
- task-3: −70 (CalibrationProvider device map + statics)
- task-4: +62 (12 computed forwarders + Combine bridge)
- task-5: +37 (3 computed forwarders + 2 subscriptions)
- task-6: −77 (band aggregation routed to aggregator)
- task-8: ±0 (string-literal replacements, no count change)

The forwarders in tasks 4 and 5 are intentionally deletable code
once Phase 2 (consumer migration to child observables) lands. At
that point AudioEngine drops a further ~100 LOC.

### Architectural pressures from the review

| # | Pressure | Status after M13 |
|---|---|---|
| 1 | AudioEngine god-object | **Partially reduced**: state extracted to CalibrationProvider, LiveAcousticState, RecordingCoordinator. Lifecycle (AVAudioEngine setup, frame processing hot path, watch ingest) still on the engine. Total LOC down ~50 today; further ~100 LOC drop unlocked by Phase 2. |
| 2 | No DI layer | **Resolved**: AppServices owns the graph; one @StateObject root in SpektoWatch2App. (Consumer-side migration to `services.x` is the Phase 2 polish.) |
| 3 | DSP entangled with view bodies | **Partially resolved**: spectrum band aggregation (the M12 bug site) lives in one place — SpectrumBandAggregator. Level-history and waterfall view-body math deferred. |
| 4 | Persistence split across layers | **Inventoried**: every key documented in PersistenceKeys.swift with tier + schema version + sunset rule. Migration runner consolidation deferred. |
| 5 | Watch protocol no versioning | **Resolved (schema-byte)**: every SpectrogramData payload carries a UInt8 version; mismatches reject cleanly. Envelope (`WatchAppState`) defined for non-audio state; consumption pending Phase 2 in task-7. |

### Test coverage added

- `SpektoWatch2Tests/CalibrationProviderTests.swift` — 5 cases:
  three known device IDs, two unknown fallback, default constant,
  `resolveStartupOffset` saved-value + missing-version paths.
- `SpektoWatch2Tests/SpectrumBandAggregatorTests.swift` — 7 cases
  including an explicit **M12 regression guard** (uniform spectrum
  must produce band level above per-bin level, proving sum-of-power
  not mean-of-power).
- `SpektoWatch2Tests/WatchProtocolVersioningTests.swift` — 7 cases:
  SpectrogramData round-trip + version byte rejection + empty
  payload + WatchAppState envelope round-trip + schema bump
  rejection + protocol message builder + malformed envelope
  rejection.

19 new tests total. Existing test suites untouched.

## Hardware verification — what task-9 acceptance still needs

These cannot be closed from CLI. Each item maps to a checkbox in
task-9.md:

1. **Cold-launch parity.** Existing dashboards, layouts,
   calibration, design tokens, active preset all load correctly
   from pre-M13 UserDefaults state. The persistence registry
   migration is bit-identical to pre-M13 reads/writes, so this
   should pass — but it must be verified on a real device that
   has user-tuned settings.
2. **Audio correctness.** LAF / LAeq / LCpeak values at a known
   reference signal match pre-M13 within the expected calibration
   tolerance. The CalibrationProvider extraction does not change
   any math; the LiveAcousticState extraction reuses the same
   storage; the band aggregation centralisation routes both call
   sites through the same code path that already shipped the M12
   fix. Risk class: low. Acceptance: regression compare against
   a calibrated source.
3. **Widget render parity.** Every widget renders identically.
   The objectWillChange bridges in tasks 4/5 mean existing
   widgets still re-render on live ticks. Visual diff against
   pre-M13 screenshots recommended.
4. **Recording flow.** Start → record → stop → playback works
   end-to-end. The `isMeasurementRecording` didSet logic moved to
   a Combine subscription with `dropFirst()` semantics; verify
   the writer still opens/closes correctly mid-session.
5. **Watch ↔ iOS pairing.** Spectrogram payload with the new
   version byte parses on the watch. An older-build watch
   talking to a new-build iOS sees the unknown version and
   continues gracefully (logged warning, no crash).
6. **Instruments re-render comparison.** Hook Instruments to
   measure WidgetCardView re-render count under live audio.
   Today the bridge in task-4 republishes live state, so the
   count should be near-identical to pre-M13. After Phase 2
   widget migration, the count should drop measurably.

## Risk register

Each Phase 1 extraction has a specific risk to verify on hardware:

| Task | Risk |
|---|---|
| 3 (Calibration) | UserDefaults key rename / load order change. Should be transparent; verify on a device with a saved non-default offset. |
| 4 (LiveAcousticState) | Combine bridge ordering vs. existing observers. Verify no UI freeze under live audio. |
| 5 (RecordingCoordinator) | Combine subscription semantics vs. didSet. `.dropFirst()` skips the initial false emission; the original didSet didn't fire on init either (no oldValue available for the initial assignment). Semantically equivalent — verify file-writer open/close behaves identically. |
| 6 (Band aggregator) | Output of `computeDisplayThirdOctaveBands` must match pre-M13 byte-for-byte for the same input. Math is unchanged; one routing layer added. |
| 7 (Schema version byte) | Old-build phone + new-build watch (or vice versa) — the receiver logs an unknown-version warning and ignores the frame. Should not crash. |
| 8 (Persistence registry) | Pure string-literal replacement; if a typo crept in, the corresponding setting would silently fail to persist. Spot-check each setting category after a fresh install. |

## Deliverables checklist

- [x] iOS build green at HEAD.
- [x] watchOS build green at HEAD.
- [x] All pre-M13 tests unmodified; 19 new tests added.
- [x] ACP validate passes.
- [x] Per-task `.md` files document Phase 1 + Phase 2 deferrals
  consistently.
- [x] This handoff report.
- [ ] Hardware behaviour-parity pass — gated on a hardware session.
- [ ] Instruments re-render measurement — gated on hardware.
- [ ] Promote M13 to `completed` in `progress.yaml` after hardware
  pass.

## Recommended next steps

1. **Take a hardware session.** Run the 6 verification items
   above, capture before/after Instruments traces for one
   representative dashboard layout, and write up findings as an
   addendum to this report.

2. **If hardware passes**, choose between:
   - **A. Promote M13 to completed.** Phase 2 items become a
     follow-up milestone (M14 candidate: "Architecture Phase 2 —
     migrate consumers, ship the LOC drop").
   - **B. Land selected Phase 2 items first** while the seams are
     fresh in mind. Highest-leverage picks: task-4 Phase 2 widget
     migration (real re-render breadth win + ~70 LOC drop on
     AudioEngine), task-7 Phase 2 broker + face migration (closes
     the hardcoded phosphor in watch faces).

3. **Routed elsewhere — track separately:**
   - **A2 / M6 task-4** App Group entitlements still need manual
     Xcode + Developer Portal work before any cross-target shared
     state is actually shared in production builds.
   - **A3 / M11 task-1** ToneGenerator `NSLock` on the audio
     render thread remains a known blocker.

## Action

Code-side M13 acceptance is complete. Mark task-9 as
`in_progress` (the file is now updated; hardware verification is
the only remaining work). Promotion of M13 as a milestone to
`completed` is gated on the hardware session.
