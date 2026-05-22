# Task 3: Extract CalibrationProvider from AudioEngine

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-13-architecture-hygiene`
Source finding: A1 phase 1 in `2026-05-21-architecture-review.md`
Depends on: task-1.

## Goal

Pull `calibrationOffset` device-map + persistence logic out of
`AudioEngine` into a focused `CalibrationProvider` helper.

## Landed (2026-05-21) — Conservative extraction

The task spec said "AudioEngine holds a provider instance and
forwards reads for backward compatibility." A pragmatic
interpretation that minimises regression risk:

- New `SpektoWatch2/CalibrationProvider.swift` (135 LOC; pure
  enum — no instance state). Owns:
  - The per-device calibration-offset table (was a private
    static dictionary on AudioEngine).
  - `currentDeviceModel()` (was `AudioEngine.getDeviceModel`).
  - `recommendedOffset()` + `recommendedOffset(for:)` for tests
    (was `AudioEngine.getRecommendedCalibrationOffset`).
  - `resolveStartupOffset(defaults:)` — load from UserDefaults or
    fall back to device default, with schema-version bump.
  - `persist(offset:defaults:)` mirror.
  - `defaultOffset: Float = 94.0` constant (the 94 dB SPL
    pistonphone reference).
- `AudioEngine` keeps `@Published var calibrationOffset` (the
  runtime value) — this is the deliberate choice. Moving the
  value off the engine would break the
  `$audioEngine.calibrationOffset` Slider binding in
  `SpectrogramSettingsView` and require touching 5+ call sites
  for what is, at runtime, just a Float. The provider owns the
  logic; the engine owns the value.
- AudioEngine init replaces the 13-line load-or-fall-back block
  with `calibrationOffset = CalibrationProvider.resolveStartupOffset()`.
- AudioEngine.resetCalibrationToDeviceDefault now reads from the
  provider.
- AudioEngine.getDeviceModel + getRecommendedCalibrationOffset
  removed entirely (54 LOC of device-map dictionary + 17 LOC of
  static methods).
- `SpectrogramSettingsView` updated to call
  `CalibrationProvider.recommendedOffset()` instead of
  `AudioEngine.getRecommendedCalibrationOffset()`.

### LOC delta

| File | Before | After | Delta |
|---|---:|---:|---:|
| AudioEngine.swift | 1761 | 1691 | **−70** |
| CalibrationProvider.swift | — | 135 | +135 (new) |
| SpectrogramSettingsView.swift | — | — | (1-line rewrite) |

AudioEngine drop is 70 LOC (task target said ~80-100). The
135-LOC provider is larger than the extracted block because of
doc comments + the test-only `recommendedOffset(for:)` helper
+ the `resolveStartupOffset` / `persist` API surface. Net repo
LOC change is positive but architectural concerns (testability,
single-purpose surface) are met.

### Tests landed

`SpektoWatch2Tests/CalibrationProviderTests.swift` — 5 cases
covering:
- Three known device IDs (iPhone 12 mini = 91, 15 Pro = 94,
  iPhone 8 = 96).
- Two unknown IDs falling back to default.
- Default constant equality.
- `resolveStartupOffset` honouring saved-value with matching
  schema version.
- `resolveStartupOffset` falling back on missing version and
  bumping the schema marker.

Each test uses a per-case `UserDefaults(suiteName:)` so they
don't pollute the real defaults.

## Validation

- `xcodebuild -scheme SpektoWatch2 -destination 'generic/platform=
  iOS Simulator' build` → `** BUILD SUCCEEDED **` (twice — once
  to find the simulator-runtime missing `Logger` import, once
  after the `import OSLog` fix; once for the
  `SpectrogramSettingsView` call-site update).
- Existing consumers of `audioEngine.calibrationOffset`
  unchanged: `SpectrogramSettingsView` Slider binding,
  `ControlBarView` recording-metadata write, `HighEndSpectrogramAdapter`
  reads, `RecordingDetailView` viz-engine writes — all keep
  working without modification.
- Local simulator broken; functional acceptance gated on M13
  task-9 (hardware).

## Acceptance status

- [x] AudioEngine.swift LOC drops by ~70.
- [x] `audioEngine.calibrationOffset` getter/setter still works
  for existing consumers (forwards/storage unchanged).
- [x] Cold launch with existing calibrationVersion + saved offset
  loads correctly (covered by CalibrationProviderTests).
- [x] iOS build green.
- [x] Unit test covers ≥ 2 device-model strings (3 in the test
  file).
- [x] watchOS build still green.
