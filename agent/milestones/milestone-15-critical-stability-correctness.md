# Milestone 15: Critical Stability & Correctness Fixes

Status: in_progress
Created: 2026-05-23
Priority: high
Estimated: 1.5 weeks

## Goal

Close the highest-severity findings from the 2026-05-23 multi-agent
code review. Six binary outcomes for acceptance:

1. **No data loss when the app is killed during the soft-delete undo
   window.** The pending-delete batch survives process death and is
   either recoverable on next launch or has been committed.
2. **No file I/O, no `NSLock`, no unguarded buffer mutations on the
   AVAudioInputNode tap thread.** The audio render path performs only
   real-time-safe operations under `OSAllocatedUnfairLock`.
3. **Watch and iOS agree on calibrated dB SPL within ±0.5 dB** for the
   same input signal across the broadband level and the spectrogram
   visual.
4. **Long recordings (≥ 1 hour) export to PDF and CSV without blocking
   the main thread or exhausting memory.** Playback opens the
   recording-detail view without an eager full-history load.
5. **PDF time-average third-octave levels are energy-correct** (linear
   power averaging, not arithmetic dB averaging).
6. **`LCpeak` is actually computed from the C-weighted spectrum**, not
   from the raw broadband sample.

Source: `agent/reports/2026-05-23-code-review-synthesis.md` (the
consolidated 5-subagent review, to be written as part of task-9).

## Why now

The review surfaced three classes of bug that are user-visible:

- **Data loss on soft-delete.** `RecordingsListView` was rewritten last
  session to add a 5-second undo window. The implementation removes
  recordings from the metadata file immediately, holding only an
  in-memory `pendingSoftDeletes` buffer. If iOS terminates the app
  during the 5 seconds (background eviction, force-quit, crash), the
  metadata is gone but the audio + measurement files are orphaned —
  unrecoverable.

- **Watch / phone calibration disagreement.** `WatchAudioEngine` uses
  the wrong DFT variant (`vDSP_DFT_zop` with zeroed imaginary input
  but a normalization that matches `vDSP_DFT_zrop`) and the wrong dB
  conversion flag for DCT magnitudes (`vDSP_vdbcon` flag 1 = 10·log10
  = power convention, applied to amplitude-domain values). Together
  the watch reads ~12 dB lower than iOS for the same physical input.

- **Real-time safety regressions on the audio thread.** Three
  violations slipped past M6 task-6's NSLock cleanup: a missed
  `NSLock` on `widgetSpectralWeightingsLock`, per-frame file-system
  calls in `setupMeasurementDataFileIfNeeded`, and unguarded mutation
  of the FFT sample buffer.

- **Main-thread freezes on export / playback of long recordings.**
  PDF + CSV generation runs synchronously on `@MainActor` with O(n)
  per-frame disk reads. `StoredDataProvider.bootstrap` eagerly loads
  the entire spectrogram history into memory — a 1-hour recording at
  25 fps × 2049 bins ≈ 7.4 GB.

- **PDF report bar charts are wrong.** Third-octave bands are
  arithmetically averaged in the dB domain instead of energy-averaged.
  Any recording with significant dynamic range produces visibly
  incorrect bars on the printed report users hand to clients.

- **`LCpeak` is misnamed.** The metric is computed from the raw
  broadband sample peak with calibration offset added, not from the
  C-weighted spectrum. Users reading the C-peak number in CSV exports
  or PDFs are reading a label, not the underlying number.

## Scope (tasks)

1. **Recording persistence durability.** Sidecar file for pending soft
   deletes; throwing `FileHandle.write(contentsOf:)` in
   `MeasurementDataWriter.writeHeader`; reject missing-id `Recording`
   decode instead of minting a new UUID.
2. **Audio-thread real-time safety.** Remove
   `setupMeasurementDataFileIfNeeded` from the per-frame path; migrate
   `widgetSpectralWeightingsLock` from `NSLock` to
   `OSAllocatedUnfairLock`; guard `sampleBuffer` mutations in
   `processSamples` under `processingLock`.
3. **Watch DSP calibration parity.** Switch `WatchAudioEngine` to
   `vDSP_DFT_zrop_CreateSetup` (real-optimized) with matching
   normalization; fix `performVisualDCT` to use 20·log10. Acceptance
   test: 1 kHz tone reads within ±0.5 dB on both platforms.
4. **Export off main with cancellation.** `createPDFReport`,
   `createCSVExport`, and any related path moved to `Task.detached`.
   `RecordingDetailView` gains a spinner + cancellation token. Test:
   1-hour recording exports without the UI thread blocking.
5. **Streaming `StoredDataProvider`.** `levelHistory` + `metricRows`
   stay eager (small); `spectrogramHistory` becomes lazy / windowed.
   `RecordingDetailView` requests slices through an asynchronous API
   instead of holding the full matrix. Memory ceiling under 200 MB on
   a 1-hour recording.
6. **PDF energy-correct dB averaging.** `loadAverageThirdOctaves`
   converts each frame's dB to linear power, accumulates, divides,
   converts back. Fixture covering a dB1 = −20, dB2 = −80 case shows
   arithmetic mean = −50 vs energy mean ≈ −23.
7. **LCpeak from the C-weighted spectrum.** Route LCpeak through the
   C-weighted FFT path, not the raw broadband sample. Audit existing
   consumers (PDF, CSV, recording metadata, watch envelope) for
   compatibility.
8. **AcousticMetricsCalculator thread safety.** Add an
   `OSAllocatedUnfairLock` around the energy accumulators + histogram
   so `reset()` (main) doesn't race `updateMetrics()` (audio thread).
9. **Acceptance.** Synthesis report under
   `agent/reports/2026-05-23-code-review-synthesis.md` capturing all
   review findings. iOS + watchOS builds green. Unit tests added for
   the soft-delete sidecar round-trip, watch DFT parity, and PDF
   energy averaging. Handoff report
   `agent/reports/<date>-milestone-15-acceptance.md` with hardware
   verification checklist.

## Non-Goals

- The full watch-connectivity hardening pass (deferred to M16).
- The SwiftUI lifecycle / performance cleanups in
  `DashboardViewModel`, `OscilloscopeView`, `WidgetSettingsView`
  (deferred to M17).
- `xcresulttool --legacy` migration and broader test infrastructure
  cleanup (deferred to M18).
- `RealtimeAudioFileWriter` unit tests (M18; the file is currently
  untracked and untested).
- DCT visual path replacement on the watch — leaves the hand-rolled
  path in place, only fixes the two correctness bugs in it.
- Touching M11 (ToneGenerator NSLock; stays routed there).
- Touching M6 task-4 entitlements (stays routed there).

## Acceptance

- All six binary outcomes above hold true.
- iOS + watchOS builds green at HEAD.
- New unit tests pass:
  - Soft-delete sidecar round-trip (write → kill simulation via fresh
    `RecordingManager` init → restored).
  - Watch DFT parity (1 kHz tone, ±0.5 dB iOS vs watch).
  - PDF energy averaging (asymmetric dB fixture).
- Existing tests: `FFTProcessorTests`,
  `WaterfallDataBuilderTests`, `HighEndSpectrogramAdapterTests`,
  `MeasurementDataIOTests`, `WatchProtocolVersioningTests`,
  `WatchConnectivityTests` all green.
- Hardware acceptance items (audio thread freeze under stress,
  long-recording export wall-clock, watch ↔ phone calibration with a
  reference SPL meter) documented in the handoff report.

## Risk register

- **task-1 sidecar.** A second persistence file introduces a new
  drift surface. Mitigation: the sidecar is single-purpose, written
  atomically, and the loader is fault-tolerant (corrupt sidecar →
  log, discard, do not block recordings list).
- **task-3 calibration parity.** Fixing the watch DFT + DCT will
  shift every existing watch reading by ~12 dB. Users with stored
  watch-only recordings see a one-time level jump. Mitigation: ship
  the fix paired with a brief release note; no migration of stored
  measurements (they were never calibrated to a reference anyway).
- **task-5 streaming provider.** Cancellation interaction with the
  existing `spectrogramLoadTask` in `RecordingDetailView` is subtle.
  Risk of UI showing stale data while a streaming read is in flight.
  Mitigation: explicit task token / view-state invalidation on the
  consumer side.
- **task-7 LCpeak.** Existing recordings have `peakLevel` baked into
  metadata. Renaming or recomputing the field changes printed values
  in old PDFs vs. new. Mitigation: write the corrected value to
  newly-saved recordings; document the boundary in the report.

## Files in this bundle

- This milestone file.
- 9 task files under `agent/tasks/milestone-15-critical-stability-correctness/`.
- Source review will be written to
  `agent/reports/2026-05-23-code-review-synthesis.md` as part of
  task-9.
