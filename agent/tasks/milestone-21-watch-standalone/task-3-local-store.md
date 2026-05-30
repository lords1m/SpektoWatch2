# Task 3: Persistent Local Recordings Store

Status: in_progress
Created: 2026-05-30
Milestone: `milestone-21-watch-standalone`

## Goal

A durable on-watch recordings store: audio + `.swr` measurement data +
metadata, catalogued so recordings survive force-quit and relaunch.

## Current gap

`WatchRecordingSession` (48 LOC) writes raw audio to `temporaryDirectory` with
no catalog, metadata, or measurement-data sidecar; nothing survives relaunch.

## Scope

- Persist recordings under a stable app-container directory (not
  `temporaryDirectory`).
- Write a `.swr` measurement-data sidecar using the shared
  `MeasurementDataFormat`/writer from [[task-2-share-dsp-metrics]].
- Maintain a catalog (recording id, title, timestamps, duration, weighting,
  sync state) that is loaded on launch.
- Manage the `WKExtendedRuntimeSession` lifecycle so a recording finalizes and
  flushes to disk cleanly if the session ends or the app is backgrounded.
- Each recording gets a stable id used later for idempotent sync dedupe.

## Acceptance

- A standalone recording (audio + `.swr` + metadata) survives force-quit and
  relaunch and reappears in the catalog — verified in [[task-6-acceptance]].
- No partial/corrupt recordings on abrupt session end.

## Notes

The catalog is the source of truth for [[task-4-recordings-ui]] (list/detail)
and [[task-5-sync-back]] (what to transfer, sync state).

## Progress (2026-05-30)

Code-side complete; durability across relaunch verified on hardware in
[[task-6-acceptance]].

- Shared the `.swr` I/O so the watch can write measurement sidecars:
  `git mv`'d `MeasurementDataFormat.swift`, `MeasurementDataWriter.swift`, and
  `MeasurementDataReader.swift` from `SpektoWatch2/` into `Shared/` (both targets
  include the `Shared/` sync group → compiles into iOS + watch, iOS behavior
  unchanged, no duplicate symbols; files are Foundation-only). This completes the
  `MeasurementDataFormat`/writer-sharing portion deferred from
  [[task-2-share-dsp-metrics]].
- New `Shared/WatchRecordingMetadata.swift`: `Codable`/`Identifiable`
  `WatchRecordingMetadata` (stable `id` UUID = file basename = sync dedupe key;
  title, createdAt, duration, sampleRate, weighting, audio/measurement file
  names, `WatchRecordingSyncState` = local/syncing/synced). Shared so the
  phone-side ingest in [[task-5-sync-back]] reuses the exact same record.
- New `SpektoWatch Watch App/WatchRecordingStore.swift`: durable catalog
  (`watch_recordings_catalog.json`) under **Application Support** (not
  `temporaryDirectory`). Loads on launch, drops entries whose audio file is
  missing (partial-write recovery), atomic catalog writes, `register`/`update`/
  `setSyncState`/`delete` + per-recording audio/measurement URLs. `@Published`
  `recordings` (newest-first) for [[task-4-recordings-ui]]. Shared singleton;
  `directory` is an immutable `let` so the audio thread can read it safely.
- Rewrote `WatchRecordingSession.swift`: stable `id`; writes `<id>.caf` +
  `<id>.swr` under the store directory; opens a `MeasurementDataWriter`
  (metricKeys LAF/LAeq/LCpeak, fps = sampleRate/bufferSize, no full-FFT payload
  to keep files small); `writeMeasurementFrame(levels:timestamp:)` projects the
  calculator dictionary onto the fixed key order; `finalize(title:)` flushes both
  files and returns durable `WatchRecordingMetadata` (idempotent — only first
  call finalizes).
- Wired `WatchAudioEngine`: standalone `startRecording` opens the session BEFORE
  `audioEngine.start()` (first frames captured); `processAudioBuffer` feeds audio
  + one measurement frame per buffer (writer dispatches disk I/O off the audio
  thread); `stopRecording` finalizes + registers in the catalog AFTER the tap is
  removed (no frame race, no double-finalize). The existing
  `WKExtendedRuntimeSession` `willExpire`/`didInvalidate` handlers already route
  to `stopRecording` on main, so an expired/missed session flushes cleanly.
  Companion/wearableMic modes keep `activeRecordingSession == nil` (phone owns
  storage). iOS + watchOS builds both green (sequential).

Remaining: hardware verification that a recording survives force-quit/relaunch
and reappears in the catalog, and that abrupt session end leaves no corrupt
files (tracked in [[task-6-acceptance]]). The recordings UI that surfaces the
catalog is [[task-4-recordings-ui]].
