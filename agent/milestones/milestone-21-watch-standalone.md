# Milestone 21: Standalone Watch App

Status: pending
Created: 2026-05-30
Priority: medium
Estimated: 2.5 weeks

## Goal

Make the watch app a fully usable acoustic measurement instrument **without a
paired/reachable iPhone**: capture with the watch mic, compute correct metrics
locally, record and persist measurements to local storage that survives a
relaunch, browse/manage those recordings on the watch, and sync them back to
the phone opportunistically when reachability returns.

This realizes the `WatchOperatingMode.standalone` case that
`Shared/WatchOperatingMode.swift` already defines but documents as a Phase-4
stub ("storing locally to a `.swr` file. Phone connectivity is optional;
recordings sync on the next reachability").

## Current state (2026-05-30 baseline)

What already works:
- `WatchAudioEngine` owns its own `AVAudioEngine`, installs an input tap, and
  computes a local FFT for immediate display (`wearableMic` mode).
- `WKExtendedRuntimeSession` keeps audio alive in the background during a
  watch recording.
- Operating-mode model (`companion` / `wearableMic` / `standalone`) exists and
  the UI branches on it.
- Watch faces/complications render from `WatchAudioEngine.liveData`.

What is missing for standalone:
- **Correct local metrics.** The watch sets `levels: ["LAF": levelSPL, "LAeq":
  levelSPL]` — both are just the instantaneous broadband level, not a
  time-integrated LAeq or a real LCpeak. `AcousticMetricsCalculator`,
  `MeasurementDataWriter`, and `MeasurementDataFormat` live in the **iOS-only**
  `SpektoWatch2/` target and are not compiled into the watch.
- **Persistent recordings store.** `WatchRecordingSession` (48 LOC) writes raw
  audio to `temporaryDirectory` with no catalog, metadata, or measurement-data
  sidecar; nothing survives relaunch.
- **Standalone activation.** Mode auto-switches `companion ⇄ wearableMic` around
  recording; there is no user control to operate watch-first, and launch
  assumes companion (phone present).
- **Sync-back to phone.** `WatchConnectivityProtocol` has no file-transfer
  message; watch recordings cannot reach the phone's `RecordingManager`.
- **Watch recordings UI.** No list / detail / delete surface on the watch.

## Scope & non-goals

In scope: standalone capture → correct metrics → local persistence → on-watch
browse/manage → opportunistic sync to phone. Graceful behavior when the phone
is absent (no blocking waits/spinners).

Non-goals:
- Raw audio streaming to the phone in real time (violates the bandwidth rule;
  sync is deferred file transfer only).
- Watch-side spectrogram export / PDF reporting (phone-only).
- Re-architecting the iOS recording pipeline beyond what sharing requires.
- Apple Watch ultra-long (hour-plus) sessions / battery tuning (separate later
  milestone if needed).

## Acceptance (hardware)

1. **Unpaired/airplane-mode capture.** With the phone off or out of range,
   start a measurement on the watch: live level + spectrogram render from the
   watch mic; no UI blocks waiting for the phone.
2. **Metric correctness.** Watch LAeq/LCpeak track the phone within ±1.0 dB on
   the same reference signal (looser than the ±0.5 dB live-parity bar because
   of the watch's reduced FFT config — document the achieved delta).
3. **Persistence across relaunch.** A standalone recording (audio + `.swr`
   measurement data + metadata) survives force-quit and relaunch and appears in
   the watch recordings list.
4. **On-watch management.** List, open, and delete a standalone recording on
   the watch.
5. **Opportunistic sync.** Re-enable phone reachability; the standalone
   recording transfers to the phone and appears in the iOS recordings list with
   matching metadata, exactly once (no duplicates on repeated reachability).

## Tasks

1. task-1 — Standalone activation & phone-absent UX (mode model, launch
   default, user toggle, no-blocking-wait audit).
2. task-2 — Share DSP/metrics to the watch target (AcousticMetricsCalculator
   subset + MeasurementDataFormat into `Shared/` or watch membership; real
   LAeq/LCpeak on watch).
3. task-3 — Persistent local recordings store (catalog + metadata + `.swr`
   writer on watch; relaunch durability; extended-runtime lifecycle).
4. task-4 — Watch recordings UI (list / detail / delete).
5. task-5 — Opportunistic sync-back to phone (WCSession `transferFile` for
   audio + measurement data; new protocol message; phone-side ingest into
   `RecordingManager`; idempotent dedupe by recording id).
6. task-6 — Acceptance (hardware end-to-end per the checklist above).
