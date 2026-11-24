# Full Code Review — 2026-11-24

Scope: all production Swift (~32k LOC) in `SpektoWatch2/`, `Shared/`,
`SpektoWatch Watch App/`, `SpektoWatch Complications/`, `SpektoWatch2Widget/`.
Test targets, design files and Python scripts were not reviewed. Six parallel
read-only reviewers each read one subsystem in full; the highest-severity
findings were re-verified by hand. Line numbers are as of commit `9c4a1d0`
and will drift — search by symbol.

Remediation is tracked in
[milestone-22-code-review-remediation](../milestones/milestone-22-code-review-remediation.md).
Every finding below has a stable ID and is assigned to exactly one task.

Severity: **H** high · **M** medium · **L** low. ✔ = re-verified by hand.

## Data loss & persistence → task-1

| ID | Sev | Location | Defect |
|---|---|---|---|
| DL-1 ✔ | H | `PlaybackAnalyzer.swift:67` | `start()` calls `engine.stopLiveMode()` during an active file recording → writers closed, recording never added to the list. → fixed (M22 task-1, pending macOS verification) |
| DL-2 ✔ | H | `RecordingManager.swift:54-55` | `loadRecordings()` (orphan sweep) runs before `restorePendingSoftDeletesFromSidecarIfNeeded()` → soft-deleted files are deleted, then metadata restored pointing at nothing. → fixed (M22 task-1, pending macOS verification) |
| DL-3 | M | `RecordingManager.swift` `ingestWatchRecording` / `addRecording` | Always returns `true`; "synced" ack sent even if save/move failed. → fixed (M22 task-1, pending macOS verification) |
| DL-4 | M | `Shared/MeasurementDataWriter.swift` `close()` | `frameCount`/seek index/CRC only written at close → crash leaves header with 0 frames, reader returns empty. → fixed (M22 task-1, pending macOS verification) |
| DL-5 | L | `MeasurementDataWriter.swift` write path | Partial write failure misaligns all later frames vs seek index. → fixed (M22 task-1, pending macOS verification) |
| DL-6 | L | `MeasurementDataReader.swift`, `MeasurementDataV3Support.swift` `decodeSeekIndex` | `Int(header.frameCount)` traps ≥2^63; `reserveCapacity` from untrusted count before bounds check. → fixed (M22 task-1, pending macOS verification) |
| DL-7 | M | `Views/RecordingsListView.swift:97` | `onDisappear` fires on push to detail → pending deletes committed while undo toast visible. → fixed (M22 task-1, pending macOS verification) |
| DL-8 | M | `DashboardManager.swift:136-139`, `WidgetConfiguration.swift` | One undecodable widget fails whole v2 decode; `configurationLoadFailed` then silently blocks all saves. → fixed (M22 task-1, pending macOS verification) |
| DL-9 ✔ | M | `Masking/MaskingProfileManager.swift:38` | `try?` decode → empty list → next `save()` overwrites `profiles.json`; write errors swallowed. → fixed (M22 task-1, pending macOS verification) |
| DL-10 | L | `AudioEngine.swift:206` via `PlaybackAnalyzer` | Playback writes the recording's calibration into the persisted `calibrationOffset`; crash mid-playback replaces user calibration. → fixed (M22 task-1, pending macOS verification) |
| DL-11 | L | `CSVExporter.swift:146` (`JSONMeasurementExporter`) | `JSONSerialization` raises ObjC exception on NaN/Inf → crash on export. → fixed (M22 task-1, pending macOS verification) |
| DL-12 | L | `StoredDataProvider.swift:86, 308` | Frame index = `time·fps`, but writer drops frames under back-pressure → scrubbing maps to wrong frames. → fixed (M22 task-1, pending macOS verification) |
| DL-13 | L | `Shared/SpectrogramData.swift:215-259` | Float arrays read via `bindMemory` at unaligned offsets (UB). → fixed (M22 task-1, pending macOS verification) |
| DL-14 | M | `Views/PhotoPickerView.swift:39` ✔ | `[weak self]` coordinator may be freed before `loadObject` returns → picked photo silently dropped. → fixed (M22 task-1, pending macOS verification) |

## WatchConnectivity transfer pipeline → task-2

| ID | Sev | Location | Defect |
|---|---|---|---|
| WC-1 ✔ | H | `Shared/WatchConnectivityManager.swift:129-134` | `didReceive file:` hops to a queue before copying; `file.fileURL` is only valid during the callback → ingest fails intermittently, watch stuck in `.syncing`. → fixed (M22 task-2, pending macOS verification) |
| WC-2 | M | `WatchConnectivityManager.swift` `syncPendingRecordings` | Re-queues `transferFile` for every `.syncing` entry on each activation/reachability flip; no check of `outstandingFileTransfers` → duplicate multi-MB transfers; phone-side staged duplicates leak. → fixed (M22 task-2, pending macOS verification) |
| WC-3 | M | `WatchConnectivityManager.swift` staged-pair purge | Audio-only fallback only runs when an unrelated later file arrives. → fixed (M22 task-2, pending macOS verification) |
| WC-4 | M | `WatchRecordingStore.swift` delete, `WatchRecordingsView.swift` | Delete doesn't cancel in-flight transfer → phone gets `.caf` without `.swr`. → fixed (M22 task-2, pending macOS verification) |
| WC-5 | M | `Shared/WatchAppSettingsSync.swift:68-86` | Full-context re-apply: an unrelated phone push reverts gain/source changed on the watch. → fixed (M22 task-2, pending macOS verification) |
| WC-6 | L | `WatchConnectivityManager.swift` | `didFinish fileTransfer:error:` failures don't reset sync state. → fixed (M22 task-2, pending macOS verification) |

## Watch app lifecycle & configuration → task-3

| ID | Sev | Location | Defect |
|---|---|---|---|
| WL-1 ✔ | H | `SpektoWatch Watch App/Watch-Info.plist` | No `WKBackgroundModes`; `WKExtendedRuntimeSession` invalidates immediately → `didInvalidate` → `stopRecording()`. → fixed (M22 task-3, pending macOS verification) |
| WL-2 ✔ | H | `WatchRecordingStore.swift:98-122` | Files cataloged only at stop; `cleanupOrphanedFiles()` deletes partial recordings after a crash. → fixed (M22 task-3, pending macOS verification) |
| WL-3 | H | `Watch-Info.plist` `WKWatchOnly=true` + `WatchConnectivityManager.swift:172-185` | Complication fed only from phone stream, which watch-only disables → always "–"; never marked stale. → fixed (M22 task-3, pending macOS verification) |
| WL-4 | M | `WatchAudioEngine.swift:1084-1098` | Invalidation callback lacks `session === self.session` guard → stale callback stops a new recording. → fixed (M22 task-3, pending macOS verification) |
| WL-5 | M | `WatchAudioEngine.swift:570-574` | Stop from background/expiry keeps mic running as live monitoring with no runtime session. → fixed (M22 task-3, pending macOS verification) |
| WL-6 | M | `WatchAudioEngine.swift:349-387` | `.auto` source: phone freshness only re-evaluated on connectivity change; stale phone frame shown forever; subscription rebuilt per frame. → fixed (M22 task-3, pending macOS verification) |
| WL-7 | M | `WatchLevelMeterView.swift:17-115`, `WatchSpectrogramView.swift:300` | −120…0 dB scale for dB SPL values → flat line; time axis assumes 46 ms/frame at ~5 Hz updates. → fixed (M22 task-3, pending macOS verification) |

## Audio session ownership & engine state → task-4

| ID | Sev | Location | Defect |
|---|---|---|---|
| AS-1 | H | (none exist) iOS `AudioEngine`/`AudioCaptureSession`, watch `WatchAudioEngine` | No interruption / route-change / media-services-reset / `AVAudioEngineConfigurationChange` handling → engine stops while UI says running; recordings silently truncated. → fixed (M22 task-4, pending macOS verification) |
| AS-2 ✔ | H | `AudioEngine.swift:165, 1106, 1136, 1174` | `isUsingDummyData` never reset → later stops leave real mic running; synthetic audio shown as measurement; `.error` overwritten by `.running`. → fixed (M22 task-4, pending macOS verification) |
| AS-3 ✔ | H | `ToneGeneratorWidget.swift:94-99` | Tone sets `.playAndRecord/.default` over capture's `.record/.measurement` (disables measurement mode); capture start re-sets `.record` and kills tone (`isPlaying` stays true). → fixed (M22 task-4, pending macOS verification) |
| AS-4 | H | `SpektoWatch Watch App/WatchToneGenerator.swift:39-98` | Watch tone sets `.playback`, never restores → watch mic capture dies silently. → fixed (M22 task-4, pending macOS verification) |
| AS-5 | M | `PlaybackAnalyzer.swift:95`, `Masking/MaskingEngine.swift:191` | Always `startLiveMode()` on exit → forces iPhone mic on even if user was stopped or on Watch source. → fixed (M22 task-4, pending macOS verification) |
| AS-6 | H | `Masking/MaskingSuggestionView.swift` `restartPreview`, `MaskingEngine.swift:166-191` | stop→start round-trips async live mode; late `.record` lands after preview's `.playAndRecord` → silent masker, mic running. → fixed (M22 task-4, pending macOS verification) |
| AS-7 | M | `MaskingEngine.swift` failure path, `AudioEngine.swift:824` | `engineStatus` becomes `.idle` asynchronously → immediate `startLiveMode()` early-returns → capture stays off. → fixed (M22 task-4, pending macOS verification) |
| AS-8 | L | `DashboardViewModel.swift:147, 176` | Un-cancellable `asyncAfter(0.3)` restarts race on rapid source switches. → fixed (M22 task-4, pending macOS verification) |
| AS-9 | M | `ToneGeneratorWidget.swift:946-948` | `onDisappear { stop() }` likely fires when fullscreen oscilloscope cover opens (verify on device). → fixed (M22 task-4, pending macOS verification) |

## Real-time & threading safety → task-5

| ID | Sev | Location | Defect |
|---|---|---|---|
| RT-1 ✔ | H | `ProcessingPipeline.swift:63-70` vs `AudioEngine.swift:~1448-1479` | `resetScratch` mutates scratch under lock on main; render thread uses it outside lock → memory corruption on FFT size change (triggered by playback start/stop). → fixed (M22 task-5, pending macOS verification) |
| RT-2 | H | `HighEndSpectrogramAdapter.swift:~535, 642, 987-1000` | Background `updateWithFFTMagnitudes` reads bins/columns/reusable buffers unlocked while main changes geometry → OOB traps, stale writes after texture rebuild. → fixed (M22 task-5, pending macOS verification) |
| RT-3 ✔ | H | `HighEndSpectrogramAdapter.swift:473 → updateTimeColumns` | Sample-rate change rebuilds Metal texture + `reset()` off main while `draw(_:)` encodes. → fixed (M22 task-5, pending macOS verification) |
| RT-4 | M | `AudioEngine.swift` `spectrogramSubject` + `WaterfallView.swift:~1503` | Published on render thread; `.onReceive` without `receive(on:)` reads SwiftUI state there. → fixed (M22 task-5, pending macOS verification) |
| RT-5 | M | `RealtimeAudioFileWriter.swift:45-74`, `AudioEngine.swift:~1300, 1532` | Render thread takes NSLocks, allocates `DispatchQueue.async` blocks, NSLogs, per-frame `map`/dict/array copies, histogram scans, builds `FFTProcessor` on SR change; writer `deinit` may close file on RT thread. → fixed (M22 task-5, pending macOS verification) |
| RT-6 | L | `WatchAudioEngine.swift:688-800` | Watch tap allocates per buffer, does `AVAudioFile` I/O under lock, reads `gain`/`recordingStartDate` unsynchronised. → fixed (M22 task-5, pending macOS verification) |
| RT-7 | L | `HighEndSpectrogramAdapter.swift:~643` | Main-thread `texture.replace` while up to 2 in-flight command buffers sample it → column tearing. → fixed (M22 task-5, pending macOS verification) |
| RT-8 | L | `Views/RecordingDetailView.swift:185`, `AudioPlayerManager.swift:75` | `@MainActor PlaybackAnalyzer.processSamples` called from background queue (traps under Swift 6). → fixed (M22 task-5, pending macOS verification) |

## Measurement correctness → task-6

| ID | Sev | Location | Defect |
|---|---|---|---|
| MC-1 | H | `SampleRingBuffer.swift:72`, `AudioEngine.swift:~1490` | Hop > FFT size: read offset clamped, frames every ~FFT samples while `dt = hop/fs` → LAF Fast up to 8× too fast. |
| MC-2 | M | `ProcessingPipeline.swift:171-182`, `SpectrumBandAggregator.swift:168` | No window power (ENBW) normalisation → Hann→Rect +4.3 dB, Hann→FlatTop −3.3 dB; bands ~1.8 dB high vs broadband. |
| MC-3 | M | `ProcessingPipeline.swift:192-201` | LCpeak = max C-weighted bin, not time-domain peak → can read below LCF. |
| MC-4 | M | `AcousticMetricsCalculator.swift:107, 254`, `SpectrogramProcessor.swift:239-256` | Band "Leq" is EMA with fixed 0.02/frame on display-smoothed dB bands → hop- and setting-dependent; persisted to files. |
| MC-5 | M | `AcousticMetricsCalculator.swift:164-201` | Broadband energy averaged over whole FFT window (≤372 ms) before 125 ms time weighting → Fast smeared, LAFmax under-reads. |
| MC-6 | L | `AcousticMetricsCalculator.swift:290`, `Shared/LoudnessCalculator.swift:104` | Phon fed A-weighted level (double equal-loudness correction); >90 phon extrapolated from zero. |
| MC-7 | M | `WatchAudioEngine.swift:55, 676, 742` | Watch: fs hard-coded 44.1 kHz; only first 2048 of ~4096 frames analysed; `dt` half real time. |
| MC-8 | M | `Masking/TriggerSpectrumAccumulator.swift:55, 92-107`, `SpectralNoveltyDetector.swift` | Assumes 86 frames/s; `captureEnd = writeHead + postFrames` reads unwritten slots. |
| MC-9 | L | `Masking/MaskerSuggestionEngine.swift` | `min(totalRMSdB, -10)` on dB SPL → suggested volume constant −10 dBFS. |
| MC-10 ✔ | L | `Masking/MaskingPreviewPlayer.swift:120-123` | `bandwidth = 1/q` (wrong Q→octave); `bands.count..<3` traps for >3 bands. |
| MC-11 | L | `LAFGraphView.swift:33-87` | Buffer not resized on 44.1→48 kHz → time axis ~8% off (plus per-frame array copy, double publish). |

## Rendering, UI & feature polish → task-7

| ID | Sev | Location | Defect |
|---|---|---|---|
| UI-1 | H | `RecordingSpectrogramModel.swift` `computeHistoryStreaming` | No column cap → recordings >~3 min exceed 16384 texture width (blank) and use ~200 MB+. |
| UI-2 ✔ | M | `Views/AudioPlayerManager.swift:273` | `seekFrame + sampleTime` after pause/scrub without rescheduling → playhead doubles (10 s → 20 s). → fixed (M22 task-4 commit, pending macOS verification) |
| UI-3 | M | `NavigableSpectrogramView.swift:~317-373` | Tile request rounded to 1/500 but drawn over exact viewport → up to ~25% misalignment at max zoom; small pans never reload. |
| UI-4 | L | `NavigableSpectrogramView.swift:~293` | Follow-playhead recentre doesn't call `requestDetailTile()`. |
| UI-5 | M | `RecordingSpectrogramModel.swift:~361-514` | After resolution promotion, A/C weighting reverts to stored 31-band overview. |
| UI-6 | L | `RecordingSpectrogramModel.swift:~307` | `isLoading` cleared while fallback recompute still running. |
| UI-7 | M | `HighEndSpectrogramAdapter.swift:~1252, 774` | Axis metrics pushed into parent `@State` at 30 Hz → full body + `updateUIView` 30×/s. |
| UI-8 | M | `WaterfallView.swift:~1656` | `TwoFingerPassThroughView.hitTest` returns nil for first touch → two-finger pan rarely begins. |
| UI-9 | L | `WaterfallView.swift:~1391`, `WaterfallPlaybackController.swift` | 720-frame dataset rebuilt on main every 120 ms; inner `Task.detached` not cancelled → stacked rebuilds. |
| UI-10 | M | `AppServices.swift:13-58` | Doesn't forward `recordingManager`/`connectivityManager`/`maskingEngine` changes → stale labels, badges, alerts. |
| UI-11 | M | `SpektralanalyseLaborWidget.swift:166, 208` | Overlap/block-size controls don't update `audioEngine.scrollSpeed`. |
| UI-12 | L | `DashboardViewModel.swift:217-240` | Undo-delete restores widget into currently shown layout. |
| UI-13 | L | `SingleValueWidget.swift:121-124` | Throttled publisher rebuilt in `body` → refresh-rate setting ineffective. |
| UI-14 | M | `LiveActivity/MeasurementLiveActivityController.swift:46-63` | Activities orphaned by crash never ended; duplicates on next recording; user dismissal not observed. |
| UI-15 | L | `ToneGeneratorWidget.swift:117-161` | No amplitude ramps (clicks); naive square/saw alias. → fixed (M22 task-4 commit, pending macOS verification) |
| UI-16 | L | `Masking/MaskingPreviewPlayer.swift` | Engine started before volume applied → full-scale burst; rain player connected with output format instead of file `processingFormat` (possible crash on mono asset — unconfirmed). |
