# Task 8: Persistence registry

Status: pending
Created: 2026-05-21
Milestone: `milestone-13-architecture-hygiene`
Source finding: A8 in `2026-05-21-architecture-review.md`

## Goal

Replace the scattered UserDefaults / AppGroup / @AppStorage key
strings with a single declared inventory. Forces every key to have
a documented version + migration rule.

## Scope

- New `SpektoWatch2/PersistenceRegistry.swift` (or
  `Shared/PersistenceKeys.swift` if cross-target).
- Inventory at least these existing keys (from the architecture
  review):
  - `DashboardConfiguration_v5` (legacy single-layout JSON; sunset
    plan documented).
  - `DashboardLayouts_v1` (multi-layout JSON).
  - `calibrationVersion`, `calibrationOffset`.
  - `design.theme`, `design.canvasInLight`, `design.accent`,
    `design.density`, `design.numerals`, `design.colormap`.
  - `dashboard.activePreset`.
  - Watch-related keys defined under `Shared/AppGroup.swift`.
- Each entry declares:
  - Key name (single source of truth).
  - Storage tier (standard / AppGroup / AppStorage).
  - Schema version.
  - Migration step (function pointer) from previous version, if
    any.
- Existing call sites switch from string literals to registry
  entries.
- One-shot migration runner on app launch reads the registry and
  applies any pending migrations.

## Non-Goals

- Wiring App Group entitlements (that's M6 task-4).
- Changing the persisted JSON schemas themselves — this is a
  bookkeeping refactor.
- Migrating Recording metadata (handled by RecordingManager).

## Acceptance

- Zero raw key strings remain in the codebase (`grep "v5"`,
  `grep "calibrationOffset"`, etc. return only the registry file
  + tests).
- Cold launch with simulated pre-M13 UserDefaults state loads
  every setting correctly. Test fixture committed alongside.
- iOS + watchOS builds green.
- Removal plan for `DashboardConfiguration_v5` documented (which
  release cycle drops it).
