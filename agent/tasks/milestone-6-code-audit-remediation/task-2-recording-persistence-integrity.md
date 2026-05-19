# Task 2: Recording & Persistence Integrity

Status: partial
Created: 2026-05-18
Updated: 2026-05-18
Milestone: `milestone-6-code-audit-remediation`

## Status Summary

| Sub-item | Source finding | Result |
|---|---|---|
| 1. Delete duplicated `RecordingManager` | Audit #4 (Critical) | **LANDED** — file deleted; pbxproj already excluded it from the SpektoWatch2 app target |
| 2. Writer `frameCount` after disk write | Audit #5 (Critical) | **LANDED** — `MeasurementDataWriter.swift:122-129` |
| 3. `StoredDataProvider.bootstrap()` off main | Audit #6 (Critical) | **LANDED** — `RecordingDetailView.swift:854-907` (via `Task.detached`) |
| 4. `SaveRecordingView` filename only | Audit #17 (High) | **LANDED** — `SaveRecordingView.swift:69-75`; note: this view is never instantiated, see Task 9 |
| 5. CSV locale | Audit #14 (High) | DEFERRED — see "Deferral" below |
| 6. `CGImage` bitmap info | Audit #15 (High) | **LANDED** — `SpectrogramImageRenderer.swift:131-135` |
| 7. `PDFReportGenerator` path via manager | Audit #16 (High) | **LANDED** — `PDFReportGenerator.swift:9-23, 73-77`; helpers deleted |
| 8. `MeasurementDataReader` fd doubling | Audit #18 (High) | **LANDED** — `MeasurementDataReader.swift:15-52, 113-121` |
| 9. `RecordingDetailView` cancellable | Audit #25 (Medium) | **LANDED** — bundled with #3 via `spectrogramLoadTask` + `onDisappear` cancellation |

8 of 9 sub-items landed. 1 deferred.

## Deferral — Sub-item #5 (CSV locale)

The audit calls the CSV's `;` separator + `.` decimal a bug for DE-locale Excel. The M4 task `agent/tasks/milestone-4-export-and-reporting/task-3-csv-export-hardening.md` explicitly lists **"No localization redesign for decimal separators"** as a non-goal. Changing the decimal mark now is a measurement-output format change that needs a deliberate product decision (always-DE? always-POSIX? locale-driven and inconsistent?), not a silent bug fix.

The M4 acceptance criterion "Output opens cleanly in common spreadsheet tools" is at odds with the audit. Either the M4 verification skipped DE Excel, or the decision was deliberate. Deferring until a product-level call.

## What Landed

### `SpektoWatch2/Managers/RecordingManager.swift` — DELETED

Stale duplicate that wrote `recordings_metadata.json` non-atomically (live class uses `_v2.json`). The Xcode project's synchronized-folder exception list already excluded this file from the SpektoWatch2 app target. Tests use `@testable import SpektoWatch2` and see only the v2 class.

### `SpektoWatch2/MeasurementDataWriter.swift:122-129`

`frameCount` is now incremented INSIDE the `writeQueue.async` block, after `handle.write(...)` returns. Previously it was incremented synchronously on the calling thread before the bytes hit the file. A crash between the increment and the disk write would leave the header claiming N+1 frames while the file held N. `close()` already drains the queue via `writeQueue.sync {}` before calling `updateFrameCount`, so the count is consistent with disk contents at close time. Verified no external readers consume `writer.frameCount` mid-recording.

### `SpektoWatch2/Views/RecordingDetailView.swift:854-907` (+ `30-37, 159-163`)

`loadStoredMeasurementDataIfAvailable()` and `loadSpectrogramHistoryFallback()` now run via `Task.detached(priority: .userInitiated)`. The full-file `StoredDataProvider` bootstrap (which can be hundreds of MB / multiple seconds for long recordings) no longer blocks the main thread. State mutation hops back to main via `await MainActor.run`, with a `Task.isCancelled` guard. A shared `@State var spectrogramLoadTask` is cancelled in `onDisappear` so navigating away no longer leaves the CPU pegged or risks mutating stale view state. The `isLoadingSpectrogram` flag is set/cleared on both paths so the existing loading UI fires for the stored-data path too.

### `SpektoWatch2/Views/SaveRecordingView.swift:69-75`

Stores `audioURL.lastPathComponent` and `measurementDataURL.lastPathComponent` instead of `.path`. Defends against the sandbox-container-UUID reinstall failure mode. The view itself is dead code (no instantiation anywhere in the project) — flagged for deletion in Task 9.

### `SpektoWatch2/SpectrogramImageRenderer.swift:131-135`

`CGImageAlphaInfo.last` → `.noneSkipLast`. The RGBA buffer always sets alpha = 255 (opaque); `.last` (non-premultiplied) is not in CGImage's supported pixel formats for device RGB color space, so the previous code was relying on undefined behavior. `.noneSkipLast` explicitly tells Core Graphics the alpha byte is junk.

### `SpektoWatch2/PDFReportGenerator.swift:9-23, 73-77`

PDF generator now consumes `RecordingManager.url(for:)`, `measurementURL(for:)`, and `getPhotoURL(fileName:)` instead of re-deriving `~/Documents/Recordings` itself. Deleted two private helpers (`resolveRecordingsDirectory`, `resolveRecordingURL`). The `recordingManager` parameter is no longer underscored — it's used. Eliminates the failure mode where a future change to the recordings directory silently produces blank PDF pages.

### `SpektoWatch2/MeasurementDataReader.swift:15-52, 113-121`

Header parsing now reads from the open `FileHandle` (new `readExactly` helper) instead of memory-mapping the entire file via `Data(contentsOf: ..., options: .mappedIfSafe)`. Previously two OS resources were held against the same inode for the reader's lifetime — for large recordings (hundreds of MB) this was real RSS pressure plus an extra file descriptor. The frame-read code path (`readFrame`, `forEachFrame`) is unchanged and continues to use the same handle. `bytesConsumed` is tracked explicitly so `frameStartOffset` and `header.headerSize` no longer depend on a `MeasurementDataCursor.offset`.

## Out of Scope (unchanged)

- Changing the on-disk binary format (no schema migration in this milestone).
- New export formats.
- A schema-version field — flag this as a follow-up if the format ever needs to change.

## Verification

Tests cannot be run locally (simulator broken). Verification commands for CI / a developer machine:

- `xcodebuild test -scheme SpektoWatch2 -only-testing:SpektoWatch2Tests/MeasurementDataReaderTests` — confirm header parsing still round-trips against fixtures.
- `xcodebuild test -scheme SpektoWatch2 -only-testing:SpektoWatch2Tests/RecordingManagerTests` — confirm the dead-code removal didn't break the test target.
- `xcodebuild test -scheme SpektoWatch2 -only-testing:SpektoWatch2Tests/PDFReportGeneratorTests` — confirm the URL-routing change still produces a non-empty PDF for fixtures.
- Manual: long recording (>30 min), open detail view, immediately tap back. Confirm via Instruments / Console that the load Task is cancelled and CPU returns to idle within ~1 s.
- Manual: open a recording in iOS Settings → reset content & settings, reinstall app, confirm previously-saved recordings list is still playable.

## Follow-ups

- Open a sub-task or product decision for CSV locale (sub-item #5).
- Add `SaveRecordingView.swift` to the Task 9 dead-code purge list.
- Optional: add a schema-version field to the recording binary format so future format changes can be migrated rather than break compatibility silently.

## Audit References

#4 (landed), #5 (landed), #6 (landed), #14 (deferred), #15 (landed), #16 (landed), #17 (landed), #18 (landed), #25 (landed via #6)

## Objective

Eliminate every data-loss and data-corruption risk in the recording, on-disk
format, and export pipeline. After this task, a crash mid-recording or an
app reinstall must not silently destroy or hide user recordings.

## Scope

1. **Critical — Delete duplicated `RecordingManager`** —
   `SpektoWatch2/Managers/RecordingManager.swift` is dead code that points
   at `recordings_metadata.json` (live class uses `_v2.json`) and writes
   non-atomically. Delete the file from disk and remove its membership from
   the Xcode target. Confirm no other file references it (`grep -rn
   "Managers/RecordingManager"`).

2. **Critical — Header / file-content mismatch on crash** —
   `SpektoWatch2/MeasurementDataWriter.swift:123`. Move `frameCount += 1`
   inside the `writeQueue.async` block after `fileHandle.write(...)`
   completes. Add a barrier write of the updated header on `close()`.

3. **Critical — `StoredDataProvider.bootstrap()` blocks main thread** —
   `SpektoWatch2/StoredDataProvider.swift:116-131`. Convert to an async
   initializer (or expose a separate `load() async throws` method). Update
   the only caller in `RecordingDetailView.loadStoredMeasurementDataIfAvailable()`
   to await it from a `Task`, with a loading state shown in the UI.

4. **High — `SaveRecordingView` stores absolute sandbox path** —
   `SpektoWatch2/Views/SaveRecordingView.swift:69`. Replace `audioURL.path`
   with `audioURL.lastPathComponent` so the recording survives an app
   reinstall (sandbox container UUID changes). Audit `RecordingManager.url(for:)`
   to ensure it always reconstructs from `lastPathComponent` and the
   current container.

5. **High — CSV decimal/separator mismatch in DE locale** —
   `SpektoWatch2/CSVExporter.swift:61-63`. Use a `NumberFormatter` with
   `Locale.current` (or commit to POSIX with `.` and document). The current
   `;` separator + `.` decimal point breaks Excel in any locale that uses
   `,` as the decimal mark.

6. **High — `CGImage` bitmap-info mismatch** —
   `SpektoWatch2/SpectrogramImageRenderer.swift:131`. Replace
   `CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)` with
   `.noneSkipLast` so the bitmap info matches the actual RGBX buffer layout
   (alpha = 255, not premultiplied).

7. **High — `PDFReportGenerator` re-implements path resolution** —
   `SpektoWatch2/PDFReportGenerator.swift:271-280`. Take the resolved audio
   URL from `RecordingManager.url(for:)` and pass it to `generateReport`.
   Remove the duplicated `resolveRecordingsDirectory()` helper.

8. **High — `MeasurementDataReader` doubles file descriptors** —
   `SpektoWatch2/MeasurementDataReader.swift:18-19`. Parse the header from
   the open `FileHandle` (using `read(upToCount:)`). Drop the redundant
   `Data(contentsOf: ..., options: .mappedIfSafe)` mapping.

9. **Medium — `RecordingDetailView.loadSpectrogramHistoryFallback` is
   uncancellable** — `SpektoWatch2/Views/RecordingDetailView.swift:858-873`.
   Wrap in a stored `Task` and cancel in `onDisappear`. The Combine sink
   into `rawSpectrogramHistory` must check `Task.isCancelled` before
   writing.

## Out of Scope

- Changing the on-disk binary format (no schema migration in this
  milestone).
- New export formats.
- A schema-version field — flag this as a follow-up if the format ever
  needs to change.

## Verification

- Unit test: write 1000 frames via `MeasurementDataWriter`, kill the writer
  mid-batch (simulate by closing the file handle from a fault injection
  hook), reopen via `MeasurementDataReader`, confirm reported frame count
  equals frames actually on disk.
- Unit test: round-trip a recording through `SaveRecordingView`-equivalent
  code, mutate the sandbox container path, confirm `RecordingManager.url(for:)`
  still resolves.
- Manual: export a CSV, open in Excel with DE locale, confirm numeric
  columns parse as numbers.
- Manual: export a spectrogram PNG, open in Preview, confirm color
  rendering matches the in-app view (regression check for the bitmap-info
  fix).

## Audit References

#4, #5, #6, #14, #15, #16, #17, #18, #25
