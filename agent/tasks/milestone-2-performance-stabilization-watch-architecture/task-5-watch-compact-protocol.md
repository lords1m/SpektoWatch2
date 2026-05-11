# Task 5: Watch Compact Protocol

Status: completed  
Created: 2026-05-11  
Completed: 2026-05-11  
Milestone: `milestone-2-performance-stabilization-watch-architecture`

## Objective

Make the watch communication path explicit, compact, and safe for at least
one-second live updates.

## Scope

- Document or implement typed watch control/status messages.
- Preserve processed metrics or compact spectrogram payloads.
- Ensure raw audio transfer is not reintroduced.
- Define update-rate expectations for wearable-source mode.

## Acceptance

- Watch live data path updates at least once per second in the intended source
  mode.
- Watch payloads remain compact and typed.
- Tests or protocol-level checks cover encoding/decoding where practical.
- `WatchConnectivityTests` pass or any environment limitation is documented.

## Non-Goals

- No continuous raw audio transfer.
- No standalone recording implementation unless required by the compact protocol
  boundary.

## Implementation Notes

Added `WatchConnectivityProtocol` as the shared boundary for watch messages:

- control messages now use explicit typed factories and parsers for recording
  start/stop, gain, microphone source, frequency weighting, and dashboard config
- binary live-data packets use a typed spectrogram header and compact
  `SpectrogramData` serialization
- wearable-source live updates document a maximum data age of one second, with
  adaptive send intervals between 0.1 seconds and 0.5 seconds

Both watch connectivity managers now build and decode messages through the
shared protocol helper. The dashboard config reachable-send path now uses the
same typed `watchDashboardConfig` message shape as the queued path.

The watch-side audio path continues to send processed `SpectrogramData` only;
no raw audio transfer was added.

Added `WatchConnectivityTests` coverage for:

- typed control message factories and parsers
- compact spectrogram packet header and round-trip decoding
- unknown binary packet rejection
- live-update policy staying within the one-second freshness requirement

## Validation

Compile gate:

```sh
xcodebuild build-for-testing -project SpektoWatch2.xcodeproj -scheme SpektoWatch2 -testPlan SpektoWatch2 -destination "platform=iOS Simulator,name=iPhone 12 mini,OS=26.3.1"
```

Result: `TEST BUILD SUCCEEDED`.

Runtime targeted tests were not rerun because task 1 established that
CoreSimulator launch currently fails before producing unit-test results. Run the
new `WatchConnectivityTests` once simulator launch is healthy.
