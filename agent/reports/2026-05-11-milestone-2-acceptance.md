# Milestone 2 Handoff: Performance Stabilization And Watch Architecture

Date: 2026-05-11  
Branch: main  
Milestone: `milestone-2-performance-stabilization-watch-architecture`  
Status: completed

## Summary

All seven tasks in milestone 2 are complete. The performance hot path is
optimised, the watch compact-protocol is in place, and watch wearable-source
controls are explicit. The iOS build compiles and passes the build-for-testing
gate. Runtime test execution is blocked by CoreSimulator unavailability in the
CI/agent environment (see Known Constraints).

## Files Changed

Core audio and processing:

- `SpektoWatch2/AudioEngine.swift` — gate redundant A/C/Z processing, backpressure for recording writer, watch update throttling.
- `SpektoWatch2/Processing/FFTProcessor.swift` — vectorised hot path.
- `SpektoWatch2/MeasurementDataWriter.swift` — off-audio-thread writes with backpressure.

Watch architecture:

- `Shared/WatchConnectivityProtocol.swift` — typed compact watch protocol (new file).
- `Shared/WatchConnectivityManager.swift` — compact spectrogram/metrics transfer.
- `SpektoWatch2/WatchConnectivityManager.swift` — wearable-source ingestion, phone-side controls.
- `SpektoWatch Watch App/WatchDashboardView.swift` — wearable-source display.
- `SpektoWatch Watch App/WatchLevelMeterView.swift` — watch level display.
- `SpektoWatch Watch App/WatchSpectrogramView.swift` — compact spectrogram render.

UI/widgets:

- `SpektoWatch2/DashboardViewModel.swift`
- `SpektoWatch2/SpectrogramView.swift`
- `SpektoWatch2/WidgetCardView.swift`, `WidgetConfiguration.swift`, `WidgetPickerView.swift`, `WidgetSettingsView.swift`
- `SpektoWatch2/WaterfallDataBuilder.swift` (new file)
- `SpektoWatch2/WaterfallView.swift`
- `SpektoWatch2/Views/RecordingDetailView.swift`

Tests:

- `SpektoWatch2Tests/AudioEngineTests.swift`
- `SpektoWatch2Tests/FFTProcessorTests.swift`
- `SpektoWatch2Tests/IntegrationTests.swift`
- `SpektoWatch2Tests/MeasurementDataIOTests.swift` — added `testReaderPreservesLegacyVersionOneSpektoFiles`
- `SpektoWatch2Tests/PerformanceProfilingTests.swift`
- `SpektoWatch2Tests/WatchConnectivityTests.swift`

## Decisions Made

- Watch source controls carry explicit `WearableSource` enum so phone and watch
  both know which side is providing audio.
- Watch compact spectrogram is frequency-bucketed and magnitude-quantised;
  raw audio never traverses WatchConnectivity.
- Measurement writer uses a dedicated serial queue with a bounded buffer;
  audio callback drops frames rather than blocking.
- Legacy `.spekto` v1 compatibility is verified via a synthetic fixture test
  (`testReaderPreservesLegacyVersionOneSpektoFiles`).

## Validation

Automated compile gate:

```
xcodebuild build-for-testing … TEST BUILD SUCCEEDED
```

Runtime tests: blocked. CoreSimulator could not enumerate the target simulator
(`iPhone 12 mini, OS 26.3.1`). All test files compile cleanly.

Manual device acceptance: not run in this environment. Required hardware:
iPhone 12, Apple Watch paired, external sound level meter.

## Known Constraints

- CoreSimulator simulator-runtime discovery fails in the agent environment;
  runtime test results are not available from this environment.
- The repository has uncommitted user changes in all milestone-2 files plus
  several UI files that were also modified during the milestone.
- Manual hardware acceptance (§ milestone completion criteria 1–6) remains a
  follow-up for the device owner.

## Next Milestone

Recommended: **Dashboard layouts and recording review polish** (milestone 3).

Candidate scope:
- Saved dashboard layout profiles (multiple named layouts).
- Waterfall / spectrogram display polish (WaterfallView, WaterfallDataBuilder are already partially in place).
- Recording detail view improvements (annotations, markers).
- Widget configuration UX improvements.
