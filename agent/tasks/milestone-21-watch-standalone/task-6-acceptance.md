# Task 6: Acceptance (Hardware End-to-End)

Status: pending
Created: 2026-05-30
Milestone: `milestone-21-watch-standalone`

## Why this is manual

Standalone capture, persistence across relaunch, and reachability-gated sync
all require real watch hardware (mic + paired phone). The simulator cannot
validate live-audio metrics or WatchConnectivity file transfer.

## Hardware checklist

1. **Unpaired/airplane-mode capture.** Phone off or out of range: start a
   measurement on the watch — live level + spectrogram render from the watch
   mic; no UI blocks waiting for the phone. (tests [[task-1-standalone-activation]])
2. **Metric correctness.** Watch LAeq/LCpeak track the phone within ±1.0 dB on
   the same reference signal; document the achieved delta. (tests
   [[task-2-share-dsp-metrics]])
3. **Persistence across relaunch.** A standalone recording (audio + `.swr` +
   metadata) survives force-quit and relaunch and appears in the watch
   recordings list. (tests [[task-3-local-store]])
4. **On-watch management.** List, open, and delete a standalone recording on
   the watch. (tests [[task-4-recordings-ui]])
5. **Opportunistic sync.** Re-enable reachability; the recording transfers to
   the phone and appears in the iOS recordings list with matching metadata,
   exactly once. (tests [[task-5-sync-back]])

## Acceptance

- All five checklist items pass on hardware.
- Document the achieved watch↔phone metric delta.
- Promote M21 to completed once the checklist passes.
