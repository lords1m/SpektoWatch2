# Task 8: Persistence registry

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-13-architecture-hygiene`
Source finding: A8 in `2026-05-21-architecture-review.md`

## Goal

Replace the scattered UserDefaults / AppGroup / @AppStorage key
strings with a single declared inventory. Forces every key to have
a documented version + migration rule.

## Landed (2026-05-21) — Phase 1: inventory + UserDefaults migration

### New file

- `Shared/PersistenceKeys.swift` (~110 LOC). Single source of
  truth for every key name. Each entry has a doc comment
  describing its tier, schema version (where applicable), and
  sunset rule. Cross-target file so the watch + complication
  targets share the same inventory.

### Sections inventoried

- **Dashboard**: `dashboardLegacySnapshot`
  (`"DashboardConfiguration_v5"`, sunset planned),
  `dashboardLayouts` (`"DashboardLayouts_v1"`),
  `dashboardActivePreset` (mirror of @AppStorage literal).
- **Calibration**: `calibrationVersion`, `calibrationOffset`,
  `calibrationCurrentSchemaVersion = 2`.
- **Spectrogram smoothing**: `spectrogramFrequencySmoothing`,
  `spectrogramTemporalSmoothing`.
- **FFT config**: nested `PersistenceKeys.FFT` enum with
  `configVersion`, `windowFunction`, `blockSize`,
  `overlapPercent`, `showExplanations`, plus
  `currentVersion = 2`.
- **Bandstop filters**: `bandstopFilters`.
- **Watch dashboard config**: `watchDashboardConfig` (shared
  between local UserDefaults persistence and WCSession
  applicationContext payload key — intentionally one name).
- **Design tokens (@AppStorage mirrors)**: nested
  `PersistenceKeys.Design` enum listing the six `design.*`
  literals so they appear in the registry even though @AppStorage
  declarations still embed the StaticString.
- **AppGroup keys**: documented as inventory-only; canonical
  constants stay in `Shared/AppGroup.swift`
  (`ComplicationSharedKeys`) so the watch + complication targets
  keep a single import.

### Call-site migrations (8 files)

Every UserDefaults string literal that pointed at a registered key
moved to a `PersistenceKeys.*` reference:

| File | Sites |
|---|---|
| `DashboardManager.swift` | `userDefaultsKey`, `layoutsUserDefaultsKey` |
| `CalibrationProvider.swift` | `Keys.version`, `Keys.offset`, schema version constant |
| `AudioEngine.swift` | 4 sites: smoothing read+write × 2 |
| `Models/FFTConfiguration.swift` | 9 sites: 4 didSet writes + 5 load reads + version constant |
| `Managers/BandstopFilterManager.swift` | `userDefaultsKey` |
| `ControlBarView.swift` | recording-metadata snapshot read |
| `Shared/WatchWidgetConfiguration.swift` | `userDefaultsKey` |
| `SpektoWatch2/WatchConnectivityManager.swift`, `Shared/WatchConnectivityManager.swift` | applicationContext read + write |

After migration: `grep -rn '"DashboardConfiguration_v5"\|"DashboardLayouts_v1"\|"calibrationVersion"\|"calibrationOffset"\|"spectrogramFrequencySmoothing"\|"spectrogramTemporalSmoothing"\|"fft_*"\|"bandstopFilters"\|"watchDashboardConfig"' …` returns **only the registry file and CSV column headers** (false positive — different namespace).

## Phase 2 — Migration runner + @AppStorage migration + sunset (deferred)

What's not in this commit:

- **One-shot migration runner.** Each existing call site does its
  own ad-hoc upgrade check (e.g. `calibrationVersion`,
  `fft_configVersion`). The task spec calls for a single
  `PersistenceMigrator.runMigrationsIfNeeded()` invoked at app
  launch. Migration steps could declare `from: 1, to: 2` per
  key. Not landed — would touch every owning type's init.
- **@AppStorage declaration migration.** The `design.*` and
  `dashboard.activePreset` @AppStorage property wrappers still
  embed string literals. `@AppStorage` accepts a `StaticString`
  for the key, which compiles fine with a `static let` reference;
  migrating the declarations to use the registry constants is a
  drop-in change across ~12 sites but ripples through the
  TweaksPanelView, DesignTweaksSections, DesignTokensReader,
  ModularDashboardView, and DashboardHeaderView. Deferred for
  scope.
- **`DashboardConfiguration_v5` sunset.** The legacy key is still
  written by `DashboardManager.saveConfiguration` so that
  `ControlBarView` can snapshot widget metadata into recordings.
  Removal plan: migrate `ControlBarView` to read from
  `dashboardLayouts` instead → audit any other readers → stop
  writing the legacy key → ship one release cycle → delete the
  key from the registry. Tracked in the file's doc comment.

## Validation

- `xcodebuild -scheme SpektoWatch2 -destination 'generic/platform=
  iOS Simulator' build` → `** BUILD SUCCEEDED **`.
- `xcodebuild -scheme "SpektoWatch Watch App" -destination 'generic/
  platform=watchOS Simulator' build` → `** BUILD SUCCEEDED **`.
- Tests not run locally (AGENT.md); the migration is read/write
  through the same keys, so cold-launch behaviour for an existing
  user is bit-identical to pre-M13.

## Acceptance status

- [x] PersistenceKeys.swift inventory exists and covers every
  UserDefaults / AppGroup / @AppStorage key currently in use.
- [x] Every UserDefaults string-literal call site migrated to a
  registry constant.
- [x] iOS + watchOS builds green.
- [x] Removal plan for `DashboardConfiguration_v5` documented (in
  the registry file's doc comment).
- [ ] @AppStorage declarations migrated to registry constants —
  **deferred** (ripples across ~5 view files, scope kept tight).
- [ ] Single `PersistenceMigrator` migration runner — **deferred**
  (current ad-hoc version checks still work; consolidation is a
  separate refactor).
- [ ] Cold-launch with simulated pre-M13 UserDefaults state — gated
  on hardware (task-9).

Task stays in_progress pending Phase 2 + hardware acceptance.
