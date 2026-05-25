# Task 5: Streaming `StoredDataProvider`

Status: completed
Created: 2026-05-23
Completed: 2026-05-24
Milestone: `milestone-15-critical-stability-correctness`
Source: 2026-05-23 code review — Persistence #4

## Outcome

Task 5 landed code-side on 2026-05-24.

- `StoredDataProvider` no longer exposes or eagerly fills
  `spectrogramHistory`. Startup keeps only the small `levelHistory`
  and `metricRows` eager.
- `MeasurementDataReader` gained `readFrameSummary(at:)`, which reads
  only timestamp, metrics, broadband, and third-octave data while
  skipping full-FFT payload bytes. `StoredDataProvider.bootstrap()`
  and `scrub(to:)` use that summary path.
- Added `SpectrogramFrameWindow` plus
  `StoredDataProvider.spectrogramFrames(in:)` for disk-backed full
  frame windows and `spectrogramOverview(maxFrameCount:)` for bounded
  overview loading. Both check cancellation.
- `RecordingDetailView` now requests a capped stored overview
  (`maxStoredSpectrogramOverviewFrames = 1800`) instead of falling
  back to the provider's full history. This preserves the existing
  playback/waterfall UI without loading every stored FFT frame for
  long recordings.
- Added `SpektoWatch2Tests/StoredDataProviderTests.swift` covering
  eager small-data bootstrap, disk-backed window reads, overview
  downsampling, and cancellation propagation.

## Verification

- iOS simulator build passed via XcodeBuildMCP
  (`SpektoWatch2`, Debug, iPhone 17 Pro simulator).
- Focused direct `xcodebuild test` passed:
  - `SpektoWatch2Tests/StoredDataProviderTests` (4 tests)
  - `SpektoWatch2Tests/MeasurementDataIOTests/testWriterAndReaderRoundtrip`

## Manual acceptance pending

- Open a 30+ minute recording on hardware or a stable simulator and
  confirm the detail view opens without a memory spike.
- Scrub through playback and confirm the overview spectrogram and
  waterfall stay visually usable.

## Goal

`StoredDataProvider.bootstrap()` currently loads the full spectrogram
history into memory eagerly. For a 1-hour recording at 25 fps with
2049-bin FFT (`spectrogramHistory[frameCount × fftBinCount] Float`),
that's ≈ 7.4 GB — guaranteed OOM. Even modest recordings (15 min,
512 bins) consume hundreds of MB just to open the detail view.

Memory ceiling after this task: **under 200 MB** for any recording
≤ 4 hours, irrespective of FFT size.

## Scope

### Sub-1: Identify eager fields vs lazy fields

In `StoredDataProvider.bootstrap()` (lines ~103–135):
- **Stay eager**: `levelHistory` (`frameCount × 14` Float = ~5 MB
  at 1 hour), `metricRows` (small). These are O(frames), small
  per-frame, and consumed by the level chart at startup.
- **Become lazy**: `spectrogramHistory` (`frameCount × binCount`).
  Replace with an on-demand slice API.

### Sub-2: Streaming API

Replace `var spectrogramHistory: [[Float]]` with an asynchronous
read interface:

```swift
struct SpectrogramFrameWindow {
    let startFrame: Int
    let frameCount: Int
    let bins: [[Float]]    // frameCount entries
}

func spectrogramFrames(in range: Range<Int>) async throws -> SpectrogramFrameWindow
```

Implementation: open a long-lived `MeasurementDataReader`, seek to
the requested frame, read consecutive frames into a fresh buffer,
return.

If `MeasurementDataReader` doesn't already support range reads, add
`func readFrames(in: Range<Int>) throws -> [SpectrogramFrame]` that
batches the underlying seek+read so the caller doesn't pay per-frame
seek overhead.

### Sub-3: Consumer migration in `RecordingDetailView`

Audit every reader of `provider.spectrogramHistory`:
- Spectrogram playback view (uses `currentTime` to pick a frame)
  → request a single-frame window around `currentTime`.
- Waterfall data builder (uses a window) → request the window
  matching the visible time span.
- PDF / PNG export (uses the full history) → stream-iterate via
  the same range API; export tasks (task-4) consume one window at a
  time inside the detached task.

Cache the last-requested window in a small LRU so scrubbing
forwards/backwards doesn't thrash the file system.

### Sub-4: Cancellation

The streaming reads happen inside async functions called from view
contexts that may cancel (user navigates away). Honor
`Task.checkCancellation()` between frames so a cancelled read
doesn't hold the file handle.

## Acceptance

- [ ] `StoredDataProvider` no longer exposes
  `var spectrogramHistory: [[Float]]`. Compile error on any
  consumer that hasn't migrated.
- [ ] `spectrogramFrames(in:)` reads from disk, not from memory.
- [ ] Memory test (unit): construct a `StoredDataProvider` against
  a fixture file representing 1 hour × 2049 bins (≈ 7.4 GB on disk
  if fully expanded). Open → assert resident memory delta < 50 MB
  (small fixture is acceptable; the test asserts the *shape*, not
  the absolute file size).
- [ ] Existing `RecordingDetailView` flows still render correctly:
  spectrogram playback, waterfall, PDF export, PNG export.
- [ ] iOS build green; existing tests pass.

## Files

- `SpektoWatch2/StoredDataProvider.swift`
- `SpektoWatch2/MeasurementDataReader.swift` (possibly — for the
  range read helper)
- `SpektoWatch2/Views/RecordingDetailView.swift` (consumer
  migration)
- `SpektoWatch2/SpectrogramImageRenderer.swift` and
  `SpektoWatch2/PDFReportGenerator.swift` (export consumers)
- New tests in `SpektoWatch2Tests/StoredDataProviderTests.swift`

## Verification

- iOS build green.
- Existing recording-detail tests pass.
- New memory-shape test passes.
- Manual smoke (when simulator is available): open a 30-minute
  recording, scrub through the timeline; spectrogram updates without
  perceptible lag.

## Risk

The migration touches the most complex view in the app. Regression
risk is real — the M13 task-2 `RecordingDetailView` split deferred
the per-tab card refactor because of exactly this complexity.

Mitigation: keep the existing `StoredDataProvider` API as a deprecated
shim during the transition, migrating one consumer at a time. Final
PR removes the shim only after all consumers are off
`spectrogramHistory`.

## Out of scope

- Compressing the on-disk `.spekto` format.
- Streaming `levelHistory` (small enough to keep eager).
- Background pre-fetching beyond the LRU window.
