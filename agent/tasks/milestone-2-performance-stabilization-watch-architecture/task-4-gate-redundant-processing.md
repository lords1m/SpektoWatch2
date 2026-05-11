# Task 4: Gate Redundant Processing

Status: completed  
Created: 2026-05-11  
Completed: 2026-05-11  
Milestone: `milestone-2-performance-stabilization-watch-architecture`

## Objective

Avoid computing unnecessary Z/A/C tracks during live measurement when only one
display weighting is needed and recording does not require all tracks.

## Scope

- Identify where A, C, and Z processing are always computed.
- Gate full-track computation behind recording or data-consumer requirements.
- Preserve optional `SpectrogramData` behavior for absent tracks.
- Keep dashboard widgets working with global settings and per-widget overrides.

## Acceptance

- Non-recording live measurement computes only required weighting tracks.
- Measurement recording still captures required structured data.
- Watch and dashboard consumers handle optional tracks correctly.
- Targeted audio and widget-related tests pass or documented gaps are explicit.

## Non-Goals

- Do not remove support for A, C, or Z weighting.
- Do not change saved measurement compatibility.

## Implementation Notes

`AudioEngine` now computes optional A/C spectral tracks only when they are
required by an active consumer:

- Z spectral data remains the always-available baseline.
- The selected global `frequencyWeighting` is always included.
- Measurement recording includes A and C so `.spekto` output still carries all
  required third-octave sets.
- Active dashboard widget overrides can request additional A/C spectral tracks.
- `SpectrogramData.magnitudesA` and `magnitudesC` are now `nil` when those
  tracks were not computed, instead of carrying substituted Z data.

`DashboardViewModel` observes active dashboard widgets and reports spectral
weighting requirements for widgets whose own settings are enabled:

- spectrogram
- waterfall
- frequency display
- legacy octave-band display

Level-history and single-value widgets still use the existing metrics dictionary
and do not request extra spectral tracks.

Added `AudioEngineTests` coverage for:

- live Z-weighted processing omitting unrequested optional A/C tracks
- widget requirements publishing a requested optional C track

## Validation

Compile gate:

```sh
xcodebuild build-for-testing -project SpektoWatch2.xcodeproj -scheme SpektoWatch2 -testPlan SpektoWatch2 -destination "platform=iOS Simulator,name=iPhone 12 mini,OS=26.3.1"
```

Result: `TEST BUILD SUCCEEDED`.

Runtime targeted tests were not rerun because task 1 established that
CoreSimulator launch currently fails before producing unit-test results. Run the
new `AudioEngineTests` once simulator launch is healthy.
