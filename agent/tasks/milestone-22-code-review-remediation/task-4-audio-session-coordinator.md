# Task 4: Audio Session Coordinator

Status: pending
Created: 2026-11-24
Milestone: `milestone-22-code-review-remediation`
Owns: AS-1 … AS-9
Decision: **Q3** (dummy-data fallback)

## Goal

Exactly one object owns `AVAudioSession` category/mode/activation on each
platform. Every consumer (live capture, recording, tone generator, playback,
masking preview) requests a **lease**; the coordinator computes the combined
configuration, restores the previous state when a lease ends, and handles
interruptions and route/configuration changes.

## Design

```swift
@MainActor final class AudioSessionCoordinator {
    enum Client { case capture, tone, playback, maskingPreview }
    struct Lease { let id: UUID; let client: Client }
    func acquire(_ client: Client) throws -> Lease   // reconfigures if needed
    func release(_ lease: Lease)                     // restores prior config
    var events: AnyPublisher<SessionEvent, Never>    // interruptionBegan/Ended,
                                                     // routeChanged, mediaReset,
                                                     // engineConfigChanged
}
```

Configuration table: capture only → `.record/.measurement`; capture + tone →
`.playAndRecord/.measurement` + `.defaultToSpeaker`; playback/preview with
capture paused → `.playAndRecord/.default`; tone only → `.playback`. Lives in
`Shared/` with `#if os(watchOS)` differences.

## Steps

1. Implement coordinator + notification observers (`interruptionNotification`,
   `routeChangeNotification`, `mediaServicesWereResetNotification`,
   `AVAudioEngineConfigurationChange` for each engine). Inject via
   `AppServices`; watch gets its own instance.
2. **AS-1.** `AudioEngine`/`AudioCaptureSession`: on interruption began → mark
   `.interrupted`, keep recording files open, show banner; on ended with
   `.shouldResume` or config change → reinstall tap + restart engine,
   insert a gap marker in the measurement file; on media reset → rebuild
   engine. If restart fails during recording → finalize files and surface
   error. Same in `WatchAudioEngine`.
3. **AS-3 / AS-4.** Tone generators (iOS + watch) acquire `.tone` leases instead
   of calling `setCategory`; observe coordinator events to reset `isPlaying`.
4. **AS-5 / AS-6 / AS-7 / DL-1 follow-up.** Replace `stopLiveMode()` …
   `startLiveMode()` pairs in `PlaybackAnalyzer` and `MaskingEngine` with
   `audioEngine.suspendCapture() -> CaptureToken` / `resume(token)`; the token
   records whether capture was running and with which source
   (`activeMicrophoneSource`), and resume restores exactly that. Make
   `stopAudioCapture` set `engineStatus` synchronously when already on main.
   Add `MaskingEngine.updateMasker(_:)` that swaps the generator without
   touching capture; `restartPreview` uses it.
5. **AS-2.** Reset `isUsingDummyData` at every start; `stop` always stops both
   AVAudioEngine and `testGenerator`; on mic failure set `.error(...)` and do
   not overwrite it. Per Q3, the synthetic fallback runs only under
   `UITestLaunchFlags` / `#if DEBUG`.
6. **AS-8.** Replace `asyncAfter(0.3)` restarts in `DashboardViewModel` with a
   stored `Task` that is cancelled on the next request (or a generation counter).
7. **AS-9.** Verify on device whether `onDisappear` fires on `fullScreenCover`;
   if so, skip `stop()` while `showFullscreenOscilloscope` and stop on scene
   background / widget removal instead.

## Regression tests

- `AudioSessionCoordinatorTests` (inject a fake `AVAudioSession` protocol):
  lease combinations yield expected category/mode; release restores; capture +
  tone keeps `.measurement`.
- `AudioEngineStateTests`: after a simulated failed start then successful
  start, `stop` stops the real engine (AS-2); suspend/resume restores
  idle/Watch source (AS-5); interruption → `.interrupted` → resume restarts.

## Acceptance (task-8, hardware)

Phone call / Siri / headphone plug & unplug / Bluetooth connect during live
and during recording; tone + capture simultaneously; masking type switching.
