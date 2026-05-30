# Task 4: Watch Recordings UI

Status: in_progress
Created: 2026-05-30
Milestone: `milestone-21-watch-standalone`

## Goal

An on-watch surface to browse and manage standalone recordings: list, detail,
and delete.

## Scope

- List view backed by the catalog from [[task-3-local-store]] (title,
  timestamp, duration, sync state indicator).
- Detail view: per-recording metrics summary (LAeq/LCpeak, duration,
  weighting) and sync status.
- Delete: remove a recording (audio + `.swr` + catalog entry) with the watch's
  standard confirmation affordance.
- Follow existing watchOS SwiftUI patterns in the watch app target.

## Acceptance

- List, open, and delete a standalone recording on the watch — verified in
  [[task-6-acceptance]].
- Deleting reflects immediately in the list and frees disk.

## Notes

Sync-state indicators come from [[task-5-sync-back]]; show "pending" vs
"synced" so the user knows what has reached the phone.

## Progress (2026-05-30)

Code-side complete; on-device list/open/delete verified in [[task-6-acceptance]].

- New `SpektoWatch Watch App/WatchRecordingsView.swift`:
  - `WatchRecordingsView` — list backed by `WatchRecordingStore.shared`
    (`@ObservedObject`, `@Published recordings`), `.carousel` list style, glass
    background, empty state. Added as a new page in `WatchContentView`'s paged
    `TabView`, wrapped in a `NavigationStack` for list → detail.
  - `WatchRecordingDetailView` — per-recording summary (LAeq, LCpeak, duration,
    weighting, sync state) on a glass card, plus a destructive Löschen button
    that routes through a `confirmationDialog` (watch-standard confirmation) →
    `store.delete(...)` (removes audio + `.swr` + catalog entry, frees disk) and
    dismisses.
  - `WatchSyncStateBadge` — colored glyph for local / syncing / synced (feeds off
    `WatchRecordingSyncState`, ready for [[task-5-sync-back]]).
  - `WatchRecordingFormat` — duration/timestamp/subtitle formatting helpers.
- Surfaced real metrics in the detail view without re-reading the `.swr`: added
  optional `laeq`/`lcPeak` to the shared `WatchRecordingMetadata` and captured
  them at finalize from the last measurement frame (LAeq is cumulative, LCpeak is
  a running max, so the final frame holds the session aggregates).
- Follows existing watch SwiftUI patterns (`WatchAppBackground`, `watchGlassCard`,
  `WatchStylePalette`). iOS + watchOS builds both green (sequential).

Remaining: on-device interaction pass (list/open/delete reflects immediately and
frees disk) in [[task-6-acceptance]]. Sync-state badges will become meaningful
once [[task-5-sync-back]] drives the state transitions.
