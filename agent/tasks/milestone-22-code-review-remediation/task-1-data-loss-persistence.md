# Task 1: Data-Loss & Persistence Fixes

Status: code_complete (pending macOS build + simulator tests)
Created: 2026-11-24
Milestone: `milestone-22-code-review-remediation`
Owns: DL-1 … DL-14

## Goal

No user-visible action, crash, or decode failure may destroy a recording,
calibration, dashboard, or masking profile.

## Steps

1. **DL-1 — playback during recording.** In `RecordingsListView`/
   `RecordingDetailView`, disable opening playback while
   `audioEngine.isRecordingToFile` (show a toast "Aufnahme läuft"). Defence in
   depth: `PlaybackAnalyzer.start()` returns early (and logs) if recording.
   Task-4 later replaces the stop/start with a coordinator lease.
2. **DL-2 — sidecar order.** In `RecordingManager.init`, call
   `restorePendingSoftDeletesFromSidecarIfNeeded()` **before**
   `loadRecordings()`, or pass sidecar file names into the orphan sweep's
   referenced set. Prefer the latter (robust to future reordering).
3. **DL-3 — ack on persist.** Make `saveRecordings()` `throws` (or return
   `Bool`); `addRecording`/`ingestWatchRecording` propagate failure (metadata
   load failed, encode/write error, file move error). `WatchConnectivityManager`
   sends `recordingSynced` only on success; on failure leave staged files for
   retry.
4. **DL-4 — crash-safe `.spekto`.** Reader: when header `frameCount == 0` or
   CRC is 0, derive count = `(fileSize − dataOffset) / frameSize` (floor) and
   mark the result `recovered`. Writer: rewrite header `frameCount` every N
   frames (e.g. every 10 s) via positional write. Launch: re-catalog recovered
   files instead of deleting (coordinate with `RecordingOrphanCleanup`).
5. **DL-5 — partial writes.** On write error, `truncate` to last good offset,
   set a `writeFailed` flag, stop appending, surface error to
   `RecordingWriterCoordinator`.
6. **DL-6 — untrusted counts.** Validate `frameCount` against file size before
   `Int(...)`; in `decodeSeekIndex` check `count <= (data.count − 12) / 8`
   before `reserveCapacity`. Throw `.corrupt` instead of trapping.
7. **DL-7 — undo commit.** Remove commit from `onDisappear`; commit on the
   sheet's `onDismiss` and on `scenePhase == .background`.
8. **DL-8 — dashboard decode.** Decode widgets element-wise with a
   `LossyDecodable` wrapper that drops unknown types; map legacy German raw
   values via a migration table; keep `configurationLoadFailed` only for
   *structurally* unreadable files and in that case back the file up to
   `dashboard.corrupt-<date>.json` then allow saves.
9. **DL-9 — masking profiles.** Same pattern: on decode failure, back up file,
   set `loadFailed`, refuse `save()` until user resets; log write errors.
10. **DL-10 — calibration override.** Add a non-persisted
    `calibrationOverride: Float?` used by the DSP path; `PlaybackAnalyzer`
    sets/clears that instead of `calibrationOffset`.
11. **DL-11 — JSON NaN.** Sanitise non-finite values to `NSNull()` before
    `JSONSerialization` (shared helper also used by CSV).
12. **DL-12 — frame lookup.** `StoredDataProvider` binary-searches stored frame
    timestamps (seek index already holds them) instead of `time·fps`.
13. **DL-13 — unaligned reads.** Replace `bindMemory` with
    `loadUnaligned(fromByteOffset:as:)` / `copyBytes` into `[Float]`.
14. **DL-14 — photo picker.** Capture `onPick` strongly in the
    `loadObject` closure; drop `[weak self]`.

## Regression tests (SpektoWatch2Tests)

- `RecordingPersistenceDurabilityTests`: soft-delete + simulated kill +
  relaunch keeps files (DL-2); save failure → `ingestWatchRecording` false (DL-3).
- `MeasurementDataReaderTests`: header frameCount 0 with N frames → N
  recovered (DL-4); truncated/huge counts throw, not trap (DL-6).
- `DashboardManagerTests`: one unknown widget type → others load, saves work (DL-8).
- `MaskingProfileManagerTests`: corrupt JSON → backup created, file untouched (DL-9).
- `CSVExporterTests`: NaN/Inf frame exports as null (DL-11).
- `StoredDataProviderTests`: dropped frames → time lookup returns correct frame (DL-12).

## Acceptance

All tests above green on simulator; DL-1/DL-7 manually verified (task-8).
