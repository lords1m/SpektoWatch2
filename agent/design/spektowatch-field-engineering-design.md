# SpektoWatch Field Engineering Design

Status: draft  
Created: 2026-05-11  
Source clarification: `agent/clarifications/spektowatch-project.clarification.md`

## Purpose

This design turns the addressed SpektoWatch clarification into a durable product
and technical direction. It is the source document for the next planning step.

The next milestone should focus on performance stabilization and watch
architecture. Masking remains an important core feature later, but it is out of
scope for the next milestone.

## Product Positioning

SpektoWatch is first a field engineering tool for audio engineers and power
users. It should remain approachable on first launch, with a default interface
that does not overwhelm normal users.

The product should support two measurement trust levels:

- Built-in iPhone and Apple Watch microphones: approximate measurements, useful
  for live analysis and orientation, but not formal proof.
- External calibrated measurement microphones: future compliance-capable
  measurement mode.

The app may claim compliance only when an external calibrated measurement
microphone is used and the required calibration metadata is captured. Until the
external microphone workflow is designed, implemented, and validated, UI and
reports must avoid compliance-grade claims for built-in microphones.

## Primary Workflow

The primary user flow is:

1. Open the app.
2. Measure live sound immediately.
3. Record the measurement.
4. View the recorded measurement.
5. Add the needed analysis widgets.
6. Create a measurement protocol/report.

This means the first screen should prioritize live measurement readiness. It
should expose enough technical detail for an audio engineer without requiring
configuration before the user can see current sound levels.

## UX Language

The default UI should use consumer-friendly language with technical notation
beside it where useful.

Examples:

- "Average level (LAeq)"
- "Fast level (LAF)"
- "Peak level (LCpeak)"

Advanced acoustic terminology belongs in settings, detailed widgets, exports,
and expert-oriented panels.

## Measurement Model

The headline live metric is `LAeq`.

The first complete measurement model must support:

- A-weighting
- Z-weighting
- Fast time weighting

Calibration is optional for casual use but required for compliance-capable
measurement. The calibration state must be captured in recordings and reports
whenever it affects interpretation.

Built-in iPhone and Apple Watch microphone readings must be communicated as
approximate and not representational proof. External calibrated microphones are
the path to measurement-grade claims.

## Dashboard Design

The required first dashboard widgets are:

- Spectrogram
- Spectrum
- Level history
- Single-value metrics
- Recordings

The dashboard must support multiple saved layouts. This supports different
field workflows such as live checking, recording review, and protocol/report
preparation.

Widget settings should inherit global audio settings by default. Each widget
should also be independently configurable through overrides.

No widget is currently designated as permanently read-only. Widgets may present
engine state while still exposing relevant display or analysis settings.

## Recording And Persistence

The minimum useful saved recording is audio plus structured measurement data.

Required metadata at recording creation:

- Name
- Date
- Duration

Metadata, notes, and photos should be addable after recording. Markers/events
should be addable during recording from both iPhone and Apple Watch.

Backwards compatibility with existing `.spekto` files is very important. New
recording metadata should be versioned and optional where possible. Changes
must not break existing `MeasurementDataReader` behavior or the minimum readable
measurement frame contract.

Recording must prioritize no dropped frames over battery use or maximum spectral
detail when those goals conflict.

## Watch Design

The first watch priority is Apple Watch microphone as a wearable source. The
second priority is standalone watch recording.

The watch should be able to start and stop phone recordings, not only mirror
phone state.

The first watch-native surface should be a complication.

Watch live data must update at least once per second. The watch path must send
processed metrics or compact spectrogram data. It must not send continuous raw
audio over WatchConnectivity.

The oldest supported iPhone generation for smooth live measurement is iPhone
12. The oldest supported Apple Watch generation remains open and must be
confirmed before watch performance acceptance is finalized.

## Masking Scope

Masking is a polished core feature in the long-term product direction.

The masking workflow should eventually cover:

- Trigger acquisition
- Masking profile design
- Playback/noise generation
- Reusable saved masking profiles

For the next milestone, masking is explicitly out of scope. Performance and
watch work should not expand into masking implementation except where needed to
preserve builds and tests.

## Export And Reporting

Desired export formats:

- PDF report
- CSV data
- Raw measurement file sharing
- Spectrogram image export

PDF reports should always include:

- Summary metrics
- Level history
- Metadata
- Calibration info

Reports are client-facing documentation. Spectrograms, photos, notes, and
method notes may be added as configurable report content, but the required PDF
baseline is summary metrics, level history, metadata, and calibration info.

Because reporting scope is broad, a full export/report redesign should be a
later milestone. The next performance/watch milestone should preserve existing
export behavior.

## Privacy Design

Recordings remain fully local by design. Location metadata is optional and must
require explicit user control.

Recommended privacy copy:

> SpektoWatch uses the microphone only while measuring or recording. Recordings,
> measurement data, notes, photos, and optional location metadata stay on this
> device unless you choose to export or share them. Built-in iPhone and Apple
> Watch microphone readings are approximate; calibrated external microphones are
> required for compliance-grade measurements.

## Performance Design

Target device baseline:

- iPhone: iPhone 12
- Apple Watch: open question

Performance targets:

- Live dashboard surfaces should target 60 fps where practical.
- Watch live data must update at least once per second.
- Recording must prioritize no dropped measurement frames.
- Audio hot-path work must avoid avoidable allocation, synchronous I/O, and
  broad UI invalidation.

The next milestone should use the existing performance review as technical
input. High-priority work should include:

- Precompute constant weighting values.
- Avoid redundant A/C/Z processing when not recording.
- Vectorize scalar FFT and metric loops.
- Move measurement file writes off the audio path.
- Preserve existing measurement file compatibility.
- Keep watch transfer payloads compact and typed.

## Next Milestone Boundary

Recommended milestone name: Performance Stabilization And Watch Architecture.

The milestone is complete when:

- Live iPhone measurement and recording remain smooth on iPhone 12.
- A representative recording run has no dropped measurement frames.
- The watch microphone path streams compact processed data at least once per
  second.
- Existing recordings and `.spekto` files remain readable.
- Masking behavior is not changed except where needed to preserve builds/tests.

## Acceptance Criteria

Manual acceptance:

- Place a real sound level meter near the iPhone.
- Run SpektoWatch live measurement with the built-in iPhone microphone.
- Confirm the displayed level roughly matches the external meter.
- Start a recording, stop it, reopen the saved measurement, and verify that
  audio plus measurement data are available.
- Confirm live UI does not visibly degrade to low FPS during the recording.

Unacceptable observable failures:

- Low FPS during live measurement.
- Clearly wrong level readings.
- Dropped measurement frames during recording.
- Broken reading of existing `.spekto` files.
- Watch live data failing to update at least once per second in the target path.

Recommended automated test set:

- `AudioEngineTests`
- `FFTProcessorTests`
- `FrequencyWeightingTests`
- `MeasurementDataIOTests`
- `WatchConnectivityTests`
- `PerformanceProfilingTests`

If the full simulator suite is too expensive, run the smallest targeted
`xcodebuild` test set covering these areas and document skipped tests.

## Open Questions

- Which exact external microphone and calibration workflow will unlock
  compliance-grade claims?
- Which formal standard or standards should compliance mode target?
- What is the oldest Apple Watch generation that must support smooth live
  wearable-source measurement?
- What tolerance is acceptable when comparing built-in iPhone mic readings
  against a real sound level meter?

## Key Decisions Appendix

- SpektoWatch is field engineering first, not consumer toy first.
- The first screen must stay approachable and should not overwhelm normal users.
- Audio engineers drive the next milestone's UX and acceptance criteria.
- Default labels should be consumer-friendly with technical notation visible.
- Compliance claims are allowed only for calibrated external microphone use.
- Built-in iPhone and Apple Watch microphones produce approximate measurements.
- The primary workflow is live measurement, recording, review, analysis widgets,
  and measurement protocol/report creation.
- `LAeq` is the headline metric.
- A and Z weighting plus Fast time weighting are required first.
- Calibration is optional for casual use but required for compliance claims.
- First dashboard widgets are spectrogram, spectrum, level history,
  single-value metrics, and recordings.
- Multiple saved dashboard layouts are required.
- Widgets inherit global settings by default and may override independently.
- Recordings require audio plus structured measurement data.
- Required creation metadata is name, date, and duration.
- Notes, photos, and extra metadata can be added after recording.
- Markers/events should be addable from iPhone and Apple Watch.
- Existing `.spekto` file compatibility is very important.
- Watch microphone as wearable source is the first watch priority.
- Standalone watch recording is the second watch priority.
- Watch can start and stop phone recordings.
- The first watch-native surface is a complication.
- Watch live data updates at least once per second.
- Masking is a polished core feature later, but out of scope for the next
  milestone.
- Masking profiles should become reusable saved assets.
- Export targets include PDF, CSV, raw measurement files, and spectrogram
  images.
- PDF reports are client-facing and must include summary metrics, level history,
  metadata, and calibration info.
- iPhone 12 is the oldest defined iPhone performance target.
- Visible dashboard update target is 60 fps where practical.
- Recording prioritizes no dropped frames.
- Recordings remain fully local by design.
- Location metadata is optional and explicitly user-controlled.
- Next milestone focus is performance stabilization and watch architecture.
