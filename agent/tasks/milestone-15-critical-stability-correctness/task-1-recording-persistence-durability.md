# Task 1: Recording Persistence Durability

Status: completed
Created: 2026-05-23
Completed: 2026-05-24

## Outcome

All three sub-items landed code-side (Sub-1 and Sub-3 had already
landed in prior sessions; Sub-2 + tests landed 2026-05-24 via two
parallel subagents).

- Sub-1 (sidecar): present in `RecordingManager.swift` —
  `pendingSoftDeleteSidecarURL`, `writePendingSoftDeleteSidecar`,
  `restorePendingSoftDeletesFromSidecarIfNeeded`,
  `clearPendingSoftDeleteSidecar`. Corrupt-sidecar path logs and
  discards.
- Sub-2 (throwing writes): `MeasurementDataWriter.writeHeader` and
  `updateFrameCount` now use `try fileHandle.write(contentsOf:)`.
  The async frame-write path catches errors, NSLogs, and increments
  `droppedFrameCount` instead of `frameCount` so the header stays
  consistent with on-disk bytes. Header-write failure now propagates
  out of `init` per spec.
- Sub-3 (strict UUID decode): `Recording.init(from:)` requires `id`
  via `try container.decode(UUID.self, forKey: .id)`.
  `RecordingManager.loadRecordings` wraps each entry in
  `FailableRecording` so a single bad row is logged and skipped
  rather than aborting the whole load.

New file: `SpektoWatch2Tests/RecordingPersistenceDurabilityTests.swift`
(5 XCTest cases — sidecar round-trip, sidecar-on-commit cleanup,
corrupt-sidecar tolerance, throwing-header init, strict-UUID decode).
Tests instantiate real `RecordingManager` against
`Documents/Recordings` with backup/restore of any pre-existing
metadata in tearDown (matches existing repo pattern; M18 will
address the broader isolation gap).

## Hardware acceptance pending

- Manual smoke test on hardware: delete a recording, force-quit
  during the snackbar window, relaunch; confirm recording is
  restored and "Rückgängig" affordance fires.
- New test file requires manual addition to the `SpektoWatch2Tests`
  target in Xcode (project uses individual file references, not a
  folder reference).


Milestone: `milestone-15-critical-stability-correctness`
Source: 2026-05-23 code review — Persistence #1, #5, #7

## Goal

Close three independent persistence-integrity bugs that can lose or
silently corrupt user data. All three share the same root cause:
swallowed errors / in-memory-only state that doesn't survive process
death.

## Scope

### Sub-1: Soft-delete sidecar (Persistence #1, **Critical**)

`RecordingManager.softDeleteRecordings(ids:)` removes the entries from
`recordings` and immediately calls `saveRecordings()`, which writes
the updated metadata to `recordings_metadata_v2.json`. The pending
batch lives only in `pendingSoftDeletes: [UUID: Recording]`. If the
app is killed before the 5-second commit timer fires, the metadata
no longer references the deleted recordings but the audio +
measurement + photo files remain on disk — orphaned with no recovery
path.

**Fix:** introduce
`Recordings/.pending-soft-deletes.json` written atomically inside
`softDeleteRecordings` (after the metadata write). The sidecar carries
the full pending batch (id + timestamp + serialized `Recording`).

On `RecordingManager.init` / `loadRecordings`:
- If the sidecar exists, re-insert the contained recordings into
  `recordings` and the in-memory `pendingSoftDeletes`.
- Restart the commit timer for the remaining window (or commit
  immediately if `Date.now - sidecar.timestamp > 5s`).
- After the next `commitPendingSoftDeletes`, delete the sidecar.

Corrupt sidecar → log via `Logger.recording`, discard, continue.

### Sub-2: Throwing header write (Persistence #5, **High**)

`MeasurementDataWriter.writeHeader` uses the non-throwing
`FileHandle.write(_:)` (line 168). Disk-full / stale-fd errors are
silently dropped; the writer returns success, and the close-time
`updateFrameCount` writes into a partially-written or zero-byte file
that is unparseable on the next `MeasurementDataReader` open.

**Fix:** replace with `try fileHandle.write(contentsOf: header)`
(iOS 13.4+). Throw the error up through `MeasurementDataWriter.init`
so callers can fall back to "audio file only, no measurement data"
recording instead of producing a corrupt `.spekto`.

Also apply the same migration to `updateFrameCount` and any other
`fileHandle.write(_:)` call in the writer.

### Sub-3: Strict UUID decode (Persistence #7, **High**)

`Recording.init(from:)` line 167 mints a fresh `UUID()` if the `id`
key is missing. Every metadata reload of a corrupt or hand-edited
file produces a new ID → `updateRecording`, `deleteRecordings`, and
any external reference (e.g., URL bookmarks) break silently.

**Fix:** decode `id` with `try container.decode(UUID.self, forKey: .id)`
(non-optional). `RecordingManager.loadRecordings()` catches the per-row
decode failure, logs the offending entry, skips it, and continues with
the rest — preferable to corrupting the working set with random IDs.

## Acceptance

- [ ] Sidecar round-trip unit test in `SpektoWatch2Tests/`:
  - softDelete 2 recordings → sidecar exists → simulate kill (drop
    manager, instantiate fresh) → recordings restored, sidecar still
    present, pending timer re-armed.
  - softDelete → commit → sidecar removed → fresh manager shows
    deletion as permanent.
- [ ] Sidecar corruption test: hand-write invalid JSON → fresh
  manager loads cleanly (no recordings restored, log emitted).
- [ ] Throwing-header test: writer constructed against a read-only
  URL → init throws, no `.spekto` file produced.
- [ ] Recording decode test: metadata missing `id` → that entry is
  skipped, neighboring entries decode normally.
- [ ] No regression on `RecordingManagerTests`.

## Files

- `SpektoWatch2/RecordingManager.swift`
- `SpektoWatch2/MeasurementDataWriter.swift`
- `SpektoWatch2/Models/Recording.swift`
- New: `SpektoWatch2Tests/RecordingPersistenceDurabilityTests.swift`

## Verification

- iOS build green.
- All new tests pass.
- Manual smoke test (hardware or simulator when available):
  delete a recording, force-quit during the snackbar window, relaunch;
  recording is restored and "Rückgängig" affordance fires.
