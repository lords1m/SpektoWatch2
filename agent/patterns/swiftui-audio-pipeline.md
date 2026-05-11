# Pattern: SwiftUI Audio Pipeline

Use this pattern when changing live audio, metrics, spectrogram, or dashboard
behavior.

## Principles

- Keep AVAudioEngine tap processing fast and allocation-conscious.
- Compute or buffer on non-UI paths, then publish UI-ready snapshots at bounded
  rates.
- Use Combine subjects for high-rate streams that should not trigger broad
  `ObservableObject` invalidation.
- Keep persisted measurement data changes explicit and covered by tests.
- Treat Apple Watch as a constrained peer; prefer compact processed payloads.

## Files To Check

- `SpektoWatch2/AudioEngine.swift`
- `SpektoWatch2/SpectrogramProcessor.swift`
- `SpektoWatch2/WaterfallDataBuilder.swift`
- `SpektoWatch2/MeasurementDataWriter.swift`
- `SpektoWatch2/MeasurementDataReader.swift`
- `Shared/SpectrogramData.swift`
- `Shared/WatchConnectivityManager.swift`
- `SpektoWatch Watch App/WatchAudioEngine.swift`
