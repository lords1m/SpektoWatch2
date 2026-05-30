# Task 5: Opportunistic Sync-Back to Phone

Status: completed
Created: 2026-05-30
Milestone: `milestone-21-watch-standalone`

## Goal

When phone reachability returns, transfer standalone recordings (audio +
measurement data) to the phone and ingest them into the iOS
`RecordingManager`, exactly once.

## Current gap

`WatchConnectivityProtocol` has no file-transfer message; watch recordings
cannot reach the phone's `RecordingManager`.

## Scope

- Use WCSession `transferFile` (deferred, OS-queued) for the audio + `.swr`
  files — NOT real-time streaming. This respects the bandwidth rule; raw audio
  is never streamed live.
- Add a typed protocol message carrying recording metadata (id, title,
  timestamps, metrics summary) alongside the file transfer.
- Phone-side ingest: write transferred files into the iOS recordings store via
  `RecordingManager` and surface them in the iOS recordings list.
- Idempotent dedupe by recording id: repeated reachability or retried transfers
  must not create duplicates. Mark catalog entries synced on confirmed receipt.

## Acceptance

- Re-enabling reachability transfers a standalone recording to the phone; it
  appears in the iOS recordings list with matching metadata, exactly once (no
  duplicates on repeated reachability) — verified in [[task-6-acceptance]].

## Notes

NEVER reintroduce raw audio transfer over WatchConnectivity as a live stream;
this is deferred file transfer only. Reuse existing iOS readers/writers and
typed models on the phone side. Sync state feeds the indicators in
[[task-4-recordings-ui]].
