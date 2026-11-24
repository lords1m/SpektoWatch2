# Task 2: WatchConnectivity Transfer Pipeline

Status: pending
Created: 2026-11-24
Milestone: `milestone-22-code-review-remediation`
Owns: WC-1 … WC-6

## Goal

Every watch recording reaches the phone **exactly once**, survives
reachability flapping, and is never acknowledged before it is persisted.

## Steps

1. **WC-1 — synchronous copy.** In `session(_:didReceive file:)`, move
   `file.fileURL` into `WatchSyncStaging/<id>.<ext>` **synchronously** (inside
   the delegate call, `FileManager.moveItem`, falling back to copy), then
   dispatch the pairing/ingest bookkeeping to `transferIngestQueue` with the
   staged URL and metadata (not the `WCSessionFile`).
2. **WC-2 — dedupe transfers.** Watch: in `syncPendingRecordings`, build a set
   of recording ids from `WCSession.default.outstandingFileTransfers`
   (metadata `recordingId`) and skip those. Debounce calls (coalesce
   activation + reachability bursts, ≥ 2 s). Phone: when ingest dedupe
   short-circuits, delete the staged files.
3. **WC-3 — fallback timer.** When the first file of a pair is staged,
   schedule a `DispatchWorkItem` on `transferIngestQueue` at the staging
   timeout that runs the audio-only fallback for that id; cancel when the
   partner arrives.
4. **WC-4 — delete vs transfer.** `WatchRecordingStore.delete(id)` first
   cancels matching `outstandingFileTransfers`, then removes files. UI disables
   delete while `syncState == .syncing` unless user confirms "Übertragung
   abbrechen und löschen".
5. **WC-5 — settings merge.** Give each synced setting a `(value, updatedAt,
   origin)` envelope in `WatchAppSettingsSync`; apply an incoming key only if
   its `updatedAt` is newer than the local one. Keep wire format
   backward-compatible (missing timestamp = 0).
6. **WC-6 — transfer errors.** Implement `session(_:didFinish:error:)` on the
   watch: on error, set entry back to `.local` and log; next sync retries.

## Regression tests

- `WatchConnectivityTests` (with the existing fake session): staged file
  survives source deletion after delegate returns (WC-1); repeated
  `syncPendingRecordings` with outstanding transfer enqueues once (WC-2);
  single `.caf` ingests audio-only after timeout with no further traffic
  (WC-3); stale phone context doesn't overwrite newer watch gain (WC-5);
  failed transfer → `.local` (WC-6).

## Acceptance

Simulator tests green; hardware "exactly-once under flapping" in task-8.
