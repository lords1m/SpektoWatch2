# Performance Budget (Step 1)

This document defines the hard performance targets and release gates for SpektoWatch2.

## Scope

- iOS app (`SpektoWatch2`)
- watchOS companion (`SpektoWatch Watch App`)
Core realtime paths:
- `Audio capture and FFT processing`
- `Spectrogram rendering (Metal)`
- `Watch connectivity updates`

## Reference Devices

- iPhone reference: iPhone 12 class or newer
- Apple Watch reference: Series 7 class or newer

If a weaker target device is added, budgets must be updated explicitly.

## Test Scenarios

- `S1 Idle`: app open, no recording, no test tone
- `S2 Live`: microphone capture + spectrogram visible
- `S3 Live+Record`: microphone capture + file recording + spectrogram visible
- `S4 Live+Watch`: microphone capture + watch sync active + spectrogram visible
- `S5 Stress`: all active (capture + record + watch sync + widgets visible)

All gates below apply to release builds on physical devices with screen brightness at 50% and Low Power Mode off unless noted.

## iPhone Budget

### Realtime Quality

- Frame rate (`S2-S5`): >= 58 FPS average, no visible sustained stutter
- Frame time (`S2-S5`): p95 <= 17.2 ms, p99 <= 20 ms
- Audio XRuns / dropouts (`S2-S5`): 0 tolerated
- End-to-end audio-to-visual latency (`S2-S5`): <= 120 ms p95

### CPU / GPU

- CPU total (`S2`): <= 15%
- CPU total (`S3-S5`): <= 22%
- GPU (`S2`): <= 35%
- GPU (`S3-S5`): <= 45%

### Memory

- App RSS steady-state (`S2` after 3 min): <= 150 MB
- App RSS steady-state (`S5` after 5 min): <= 180 MB
- Memory growth over 10 min in `S5`: <= 10 MB
- Crashes or jetsam: 0 tolerated

### Power / Thermal

- Battery drain (`S2`, 30 min): <= 12%
- Battery drain (`S5`, 30 min): <= 18%
- Thermal state in `S5`: must not remain in `.serious` for > 60 s, must never hit `.critical`

## Apple Watch Budget

### UI and Update Smoothness

- Widget/dashboard refresh cadence (`S4-S5`): >= 1 update/sec under normal conditions
- Perceived UI stutter in watch dashboard: none sustained > 2 s

### Resource Use

- Watch app CPU (`S4`): <= 25%
- Watch app memory steady-state (`S4` after 3 min): <= 60 MB
- Battery drain (`S4`, 30 min active session): <= 10%

## Connectivity Budget (Phone <-> Watch)

- Transfer latency for live level updates (`S4`): p95 <= 300 ms
- Update loss rate during 10 min run (`S4`): <= 1%
- Backpressure behavior: if overloaded, degrade update frequency before affecting audio path

## Degradation Rules (Must Have)

When limits are approached, quality must degrade in this order:

1. Reduce watch update rate/batching
2. Reduce spectrogram history length (`timeColumns`)
3. Disable interpolation
4. Reduce vertical bins (`frequencyBins`)
5. Increase hop size

Audio integrity (no dropouts) is always higher priority than visual fidelity.

## Release Gates

A release is blocked if any of the following occurs in baseline validation:

- Any audio dropout/XRun in `S2-S5`
- Any metric exceeds budget by > 10%
- Memory leak trend above allowed growth
- Persistent thermal throttling in normal ambient conditions

## Measurement Source of Truth

- Instruments: Time Profiler, Metal System Trace, Allocations, Energy Log
- Xcode Metrics Organizer for trend checks
In-app signposts around:
- `Audio callback and FFT processing`
- `Spectrogram upload/render stage`
- `Watch payload send/receive`

## Ownership and Update Policy

- Budget owner: app performance maintainer
- Update frequency: whenever FFT/render/config defaults change, or when a new minimum device target is introduced
- Any budget change requires a note explaining tradeoff and user impact
