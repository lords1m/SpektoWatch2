# Task 7: Watch protocol version byte + state envelope

Status: pending
Created: 2026-05-21
Milestone: `milestone-13-architecture-hygiene`
Source finding: A5 in `2026-05-21-architecture-review.md`

## Goal

Two coupled improvements to the watch protocol:

1. Add a one-byte version prefix to every binary payload so future
   schema changes can ship safely.
2. Define a structured `WatchAppState` envelope for non-audio
   state (active preset, recording state, tone state, design
   accent, theme). Unblocks watch faces 4a/4b/4c from hardcoded
   phosphor accent.

## Scope

### Versioning

- `Shared/SpectrogramData.toBinaryData()` prepends a one-byte
  version (`0x01` for current schema). New decoder rejects
  unknown versions with a logged warning and a graceful fallback
  to the last-known state.
- Defensive parsing: every reader that expects the binary payload
  must read the version byte before parsing fields.
- Test-fixture binary payloads include the version prefix.

### State envelope

- New `Shared/WatchAppState.swift`:
  ```swift
  public struct WatchAppState: Codable {
      public let activePresetID: String?
      public let isRecording: Bool
      public let toneGenerator: ToneState?  // freq, amp, waveform, playing
      public let designAccent: String       // AccentChoice.rawValue
      public let theme: String              // ThemeMode.rawValue
      public let schemaVersion: UInt8
  }
  ```
- `WatchConnectivityManager` learns one new message type
  `appStateUpdate`. Sent on accent/theme/preset/tone changes.
  Coalesced like spectrogram data (≥ 0.2 s between sends).
- Watch faces read `WatchAppState` via the connectivity manager
  and apply accent/theme. Phosphor hardcoded constants in the
  three faces are replaced by `state.accentColor`.

## Non-Goals

- Changing the `SpectrogramData` field layout itself (the existing
  binary fields stay; only the leading version byte is new).
- Adding new commands to the watch protocol beyond
  `appStateUpdate`.
- Wiring tone-generator state changes into the envelope (the iOS
  tone generator is widget-local; needs a separate plumb to push
  state into AppServices first).

## Acceptance

- Cold-launch the pair: iOS sends `appStateUpdate` with current
  accent; watch faces reflect that accent within ≤ 1 s.
- An old-build watch reading a new-build binary payload logs
  `unknown protocol version` and continues; does not crash.
- A new-build watch reading an old-build payload (no version byte)
  is detected via length / magic byte heuristic and parsed with
  the legacy path for one release cycle.
- iOS + watchOS builds green.
- WatchConnectivityTests adds at least 2 new cases (version
  mismatch reject; appStateUpdate round-trip).
