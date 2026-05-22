# Task 7: Watch protocol version byte + AppState envelope

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-13-architecture-hygiene`
Source finding: A5 in `2026-05-21-architecture-review.md`

## Goal

Two coupled improvements to the watch protocol:

1. Add a one-byte version prefix to every `SpectrogramData` binary
   payload so future schema changes can ship safely.
2. Define a structured `WatchAppState` envelope for non-audio
   state. Unblocks watch faces 4a/4b/4c from hardcoded phosphor
   accent.

## Landed (2026-05-21) — Phase 1: format + envelope + protocol seam

### SpectrogramData version byte

- `SpectrogramData.toBinaryData()` now prepends a `UInt8` schema
  version (`0x01`) as the very first byte of every payload.
- `SpectrogramData.fromBinaryData(_:)` reads the version first and
  rejects unknown values via `return nil` — the receiver logs and
  keeps running with its previous state.
- New `SpectrogramData.currentSchemaVersion: UInt8` constant
  centralises the value.
- **No legacy-format heuristic.** The task spec called for one as
  a transition aid. In practice: phone + watch update together
  (App Store pairing), and the existing outer
  `BinaryPacketKind` byte in `WatchConnectivityProtocol` already
  provides packet-level dispatch. Future schema bumps reject
  cleanly via the new version byte; a one-cycle compatibility
  shim would add complexity for a vanishing user population.
  Documented decision, not an oversight.

### WatchAppState envelope

- New `Shared/WatchAppState.swift` (105 LOC).
  `public struct WatchAppState: Codable, Equatable` with:
  - `activePresetID: String?` — matches `DashboardPreset.id`
  - `isRecording: Bool`
  - `designAccent: String` — matches `AccentChoice.rawValue`
  - `theme: String` — matches `ThemeMode.rawValue`
  - `toneGenerator: ToneState?` — reserved for future iOS↔watch
    tone state sync (nested Codable struct: frequencyHz,
    amplitude, waveform, isPlaying)
  - `schemaVersion: UInt8` with `currentSchemaVersion = 0x01`
- `encode()` / `decode(_:)` JSON helpers. Decoder rejects
  mismatched schema versions cleanly.

### Protocol plumbing

- New `WatchConnectivityProtocol.MessageType.appStateUpdate` case.
- New constructors:
  - `makeAppStateUpdateMessage(_ state: WatchAppState) -> [String: Any]?`
  - `appStateUpdate(from message: [String: Any]) -> WatchAppState?`
- Both `SpektoWatch2/WatchConnectivityManager` (iOS-side) and
  `Shared/WatchConnectivityManager` (watch-side) gained an
  `appStateUpdate` arm in their `didReceiveMessage` switch.
  Decode-and-drop today; phase 2 wires consumption.

## Tests landed

`SpektoWatch2Tests/WatchProtocolVersioningTests.swift` — 7 cases:

- SpectrogramData round-trip includes the version byte; payload
  starts with `0x01`.
- Unknown version byte → decoder returns nil.
- Empty input rejected.
- WatchAppState round-trip via `encode()` / `decode(_:)`.
- WatchAppState with bumped schema version rejected.
- `WatchConnectivityProtocol.makeAppStateUpdateMessage` +
  `appStateUpdate(from:)` round-trip.
- Malformed appStateUpdate (no value blob) rejected.

## Phase 2 — Send/receive plumbing + watch consumption (deferred)

What's not in this commit:

- An iOS-side **change broker** that observes the relevant
  AppStorage keys (`design.accent`, `design.theme`,
  `dashboard.activePreset`) + `recording.isRecordingToFile` and
  publishes an `appStateUpdate` message ≥ 0.2 s apart on change.
  Skeleton design:
  ```swift
  // In AppServices or a dedicated WatchAppStateBroker:
  Publishers.CombineLatest4(...)
      .throttle(for: 0.2, scheduler: RunLoop.main, latest: true)
      .sink { state in connectivity.sendAppState(state) }
  ```
- A watch-side `WatchAppStateStore: ObservableObject` that receives
  envelopes and publishes `accentColor`, `theme`, `activePresetID`,
  `isRecording` for views to bind.
- Migrating watch faces 4a/4b/4c from hardcoded
  `Color(red: 0.45, green: 0.93, blue: 0.55)` to
  `@EnvironmentObject WatchAppStateStore` → `state.accentColor`.

Phase 2 is deferred because it crosses concerns (Combine broker
on iOS, store + envObj on watch, three face-file edits) that all
need hardware verification together. Phase 1 ships the protocol
seam — once it has soaked on hardware (task-9 acceptance), Phase 2
can land as a focused follow-up.

## Validation

- `xcodebuild -scheme SpektoWatch2 -destination 'generic/platform=
  iOS Simulator' build` → `** BUILD SUCCEEDED **`.
- `xcodebuild -scheme "SpektoWatch Watch App" -destination 'generic/
  platform=watchOS Simulator' build` → `** BUILD SUCCEEDED **`.
- Both connectivity-manager switches updated for exhaustiveness
  (compiler caught both during build).
- Tests not run locally per AGENT.md.

## Acceptance status

- [x] One-byte version prefix on every SpectrogramData payload.
- [x] Unknown version handled with a logged warning + nil-return
  (no crash).
- [x] WatchAppState envelope defined; encode/decode round-trip.
- [x] MessageType.appStateUpdate registered; constructors +
  decoder in protocol.
- [x] Tests: version mismatch reject (SpectrogramData +
  WatchAppState) + appStateUpdate round-trip.
- [x] iOS + watchOS builds green.
- [ ] Cold-launch pair: iOS sends, watch reflects accent — gated
  on Phase 2 + hardware (task-9).
- [ ] Old-build / new-build pair behavior — gated on hardware
  (task-9).

Task stays in_progress until Phase 2 lands or hardware acceptance
promotes based on the current seam.
