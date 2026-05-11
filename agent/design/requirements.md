# SpektoWatch Requirements

## Product Intent

SpektoWatch is a mobile and wearable acoustic measurement instrument. It should
let users monitor sound levels, inspect spectral content, record measurements,
review saved sessions, and use Apple Watch as a companion display or wearable
measurement surface.

See `agent/design/project-draft.md` for the broader collaborator-facing project
brief and roadmap.

## Core Capabilities

- Capture microphone audio on iOS and process it in real time.
- Compute FFT, frequency weighting, loudness, peak, and time-weighted acoustic
  metrics.
- Render live spectrogram, waterfall, level, loudness, tone generator, and
  masking-related widgets.
- Record audio and structured measurement data.
- Persist recordings with metadata, photos, notes, and exportable reports.
- Synchronize relevant state and compact live measurement data with watchOS.
- Support Apple Watch live monitoring with local watch processing where useful.

## Architecture Notes

- The iOS app is SwiftUI-based and starts in `SpektoWatch2App`.
- `AudioEngine` owns the primary audio pipeline and published measurement state.
- `RecordingManager` owns persisted recording metadata and file movement.
- Dashboard surfaces are modular and widget-driven.
- Shared iOS/watch models live in `Shared/`.
- Watch code lives in `SpektoWatch Watch App/` and should remain optimized for
  battery, bandwidth, and small-screen scanability.

## Quality Constraints

- Avoid avoidable allocation in audio hot paths.
- Keep high-rate UI updates throttled and separate from lower-rate dashboard
  state updates.
- Do not block audio callbacks on file, UI, network, or watch transport work.
- Preserve measurement file compatibility unless a migration is explicitly
  designed and tested.
- Keep watch transfer payloads compact and typed.

## Testing Expectations

- Unit-test pure transformations, file formats, protocol encoding, and metric
  calculations.
- Use focused UI tests for user-facing workflows where regressions are likely.
- Run targeted Xcode tests before handoff when code changes touch app behavior.
- For ACP-only changes, run `./agent/scripts/acp-validate`.
