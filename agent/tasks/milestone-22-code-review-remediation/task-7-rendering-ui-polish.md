# Task 7: Rendering, UI & Feature Polish

Status: pending
Created: 2026-11-24
Milestone: `milestone-22-code-review-remediation`
Owns: UI-1 … UI-16

Mostly independent fixes; can be interleaved with tasks 4–6. Group commits by
file.

## Steps

**Playback / recording views**
1. **UI-2.** `AudioPlayerManager`: keep `segmentStartFrame` set only when a new
   segment is scheduled; `pause()` stores `pausedFrame`; resume reschedules
   from `pausedFrame` (`stop()` + `scheduleSegment`) so `sampleTime` restarts at 0.
2. **UI-1.** `computeHistoryStreaming`: max-pool columns to
   `maxOverviewFrames` while streaming (running accumulator per output column);
   also clamp renderer texture width to `device.maxTextureWidth`.
3. **UI-5.** Once promoted, `applyWeighting` routes to
   `applyProcessorWeighting`.
4. **UI-6.** Only clear `isLoading` on the `spectralOK` path; fallback clears
   it when the recompute finishes.
5. **UI-3 / UI-4.** Draw detail tile via exact tile `start/width` mapped into
   the viewport (`localX`); request with unrounded bounds and a tolerance of
   one source column; call `requestDetailTile()` after follow-playhead recentre.

**Live spectrogram / waterfall**
6. **UI-7.** Move axis metrics into a small `@Observable` reference read only
   inside the `TimelineView`/`Canvas`; `updateUIView` early-outs when inputs
   are unchanged.
7. **UI-8.** Replace `TwoFingerPassThroughView` with a recognizer attached to
   the hosting view (`UIGestureRecognizerRepresentable` on iOS 18) or a
   SwiftUI `simultaneousGesture` with two-touch detection.
8. **UI-9.** Build waterfall dataset off-main; non-detached child task with
   `Task.checkCancellation()` in the build loop; coalesce slider rebuilds.

**Dashboard / app wiring**
9. **UI-10.** Views observe `recordingManager`, `connectivityManager`,
   `maskingEngine` directly (`@ObservedObject`), or `AppServices` forwards their
   `objectWillChange`. Remove `RecordingsListView` refresh-token workaround.
10. **UI-11.** Lab widget: `onChange(of: overlapPercent/blockSize)` →
    `audioEngine.scrollSpeed = .closest(to: fftConfig.hopSize)`; extract a
    shared helper used by `SpectrogramSettingsView` too.
11. **UI-12.** Undo toast stores source `(preset, layoutId)`; restore there, or
    commit on navigation change.
12. **UI-13.** Build the throttled publisher once in a small `@StateObject`
    model keyed by refresh rate.
13. **UI-14.** `MeasurementLiveActivityController`: on launch and in `start()`,
    end all `Activity<MeasurementActivityAttributes>.activities` not owned by
    the current recording; observe `activityStateUpdates` to clear `activity`
    on dismissal.

**Audio generators**
14. **UI-15.** Tone generator: per-sample amplitude smoothing (one-pole, ~5 ms),
    5–10 ms fade in/out on start/stop (stop completes after fade), PolyBLEP
    square/saw.
15. **UI-16.** Masking preview: set `outputVolume` before `engine.start()` and
    fade in; connect rain player with `file.processingFormat`.

## Regression tests

- `AudioPlayerManagerTests`: play 10 s → pause → resume → `currentTime ≈ 10`.
- `RecordingSpectrogramModelTests`: 10-min synthetic recording → history width
  ≤ `maxOverviewFrames`.
- `ToneGeneratorTests`: first/last 5 ms ramp; no sample step > threshold on
  amplitude change.
- `LiveActivityControllerTests` (with injectable activity provider): stale
  activities ended on start.

## Acceptance

Tests green; UI-7/UI-8/UI-9 checked in Instruments SwiftUI template and on
device (task-8).
