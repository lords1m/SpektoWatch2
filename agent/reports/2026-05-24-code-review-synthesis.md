# Code Review Synthesis — 2026-05-24

Five parallel subagents reviewed the full codebase across five areas. This report
consolidates 37 findings (8 Critical, 16 High, 11 Medium, 2 Low) and routes each
finding to the appropriate milestone. Findings already addressed by M15 tasks 1–6
are excluded.

---

## Summary by Area

| Area | Critical | High | Medium | Low | Total |
|------|----------|------|--------|-----|-------|
| AE — iOS Audio Engine | 3 | 4 | — | — | 7 |
| WA — Watch App | 1 | 2 | 2 | 1 | 6 |
| PE — Persistence & Export | 1 | 3 | 3 | 1 | 8 |
| UI — iOS UI/SwiftUI | 1 | 3 | 3 | — | 7 |
| TT — Tests & Tooling | 2 | 4 | 3 | — | 9 |
| **Total** | **8** | **16** | **11** | **2** | **37** |

---

## Milestone Routing

### → M15 (Critical Stability & Correctness) — must land before M15 task-9 acceptance

These findings are critical or high severity and directly affect data integrity or
real-time safety. AE-1/AE-2/AE-3 are the scope of M15 task-8; the others are new
and require either a new M15 task or being folded into task-8.

| ID | Severity | Finding |
|----|----------|---------|
| AE-1 | Critical | `AcousticMetricsCalculator` has no lock; `updateMetrics` runs on audio thread, `reset()` on main simultaneously |
| AE-2 | Critical | `measurementWriter` and `audioFileWriter` read on audio render thread without synchronization; concurrent `close()` on main → use-after-free |
| AE-3 | Critical | `RecordingCoordinator` `@Published` flags (`isRecordingToFile`, `isMeasurementRecording`) read directly on audio render thread — data race |
| PE-1 | Critical | Integer overflow in `MeasurementDataReader.readFrame`: `UInt64(index * frameSize)` multiplies in signed `Int` before cast — corrupt seek for large files |
| TT-1 | Critical | `RecordingPersistenceDurabilityTests.swift`, `WatchDSPParityTests.swift`, and `StoredDataProviderTests.swift` are not registered in `project.pbxproj` — they will never run |

### → M16 (Watch Connectivity Hardening)

| ID | Severity | Finding |
|----|----------|---------|
| WA-1 | Critical | `WKExtendedRuntimeSession` delegate callbacks read/write `isRecording` and `session` on an arbitrary background thread without hopping to main |
| WA-2 | High | `LevelCornerWidget` (`"SpektoWatchLevelCorner"`) is missing from both `complicationWidgetKinds` arrays — the corner complication never updates |
| WA-3 | High | `WatchConnectivityManager.sendWithRetry` (iOS-side) mutates `messageQueue` and `isProcessingQueue` without thread safety |
| WA-4 | Medium | `WatchLevelMeterView` still uses O(n) `removeFirst` on `[Float]` history instead of `RingBuffer` |
| WA-5 | Medium | `DateFormatter` allocated on every `timeString(from:)` call inside `WatchSpectrogramView` |
| WA-6 | Low | `SpectrogramData.fromBinaryData` rejects unknown schema version bytes silently — no log |

### → M17 (SwiftUI Lifecycle & Performance)

| ID | Severity | Finding |
|----|----------|---------|
| UI-1 | Critical | `AudioPlayerManager.play()` completion closure captures `self` strongly — prevents dealloc while audio engine drains; redundant `stop()` on dealloc race |
| UI-2 | High | `promoteSpectrogramResolutionThenApply` dispatches untracked `DispatchQueue.global.async` work — not cancelled on view dismissal |
| UI-3 | High | `applyPlaybackWeighting` dispatches untracked `DispatchQueue.global.async`; rapid weighting changes queue multiple competing mutations with no cancellation |
| UI-4 | High | `exportSpectrogramImage` uses `DispatchQueue.global` with no cancel path; share sheet presented on dismissed view hierarchy → iOS 17+ crash |
| UI-5 | Medium | `cancelActiveExport()` only cancels the task; export overlay stays visible until `CancellationError` propagates — can be several seconds |
| UI-6 | Medium | `PhotoPickerView.coordinator` calls `picker.dismiss` directly without resetting the `isPresented` binding → sheet cannot re-present after first use |
| UI-7 | Medium | `DashboardViewModel` stores `DashboardManager` as `@Published var` — SwiftUI only observes reference replacement, not nested `@Published` mutations |

### → M18 (Test & Tooling Debt)

| ID | Severity | Finding |
|----|----------|---------|
| TT-2 | Critical | `testPDFGenerationCancellationThrowsQuickly` is a false positive — cancellation check may never be reached with a 1000-frame fixture; timing assertion measures from `cancel()` not task start |
| TT-3 | High | `testSpectrogramWindowCancellationThrowsQuickly` and `testCSVExportCancellationThrowsQuickly` share the same race-condition false-positive pattern; no fallback `catch` for non-cancellation errors |
| TT-4 | High | `testRecordingDecodeWithMissingID_throws` backup/restore lives in test body not `setUp`/`tearDown` — a crash between backup and defer leaves user's real metadata gone |
| TT-5 | High | `acp-validate` required-file list only covers M1–M5 task files; deleting any M6–M15 acceptance record passes the script silently |
| TT-6 | High | `capture-screenshots.py` `walk_attachments` assumes `_values`-keyed dict form; if xcresult drops `--legacy`, all attachments are silently skipped with exit code 0 |
| TT-7 | Medium | `testCSVNumericFormatThreeDecimalPlaces` iterates all columns with nondeterministic random broadband value — fragile to float formatting choices |
| TT-8 | Medium | `testBootstrapKeepsSmallMetricDataEager` conflates "FFT present in file header" with "FFT eagerly loaded" — passes even after lazy-load refactor |
| TT-9 | Medium | `testGenerateBasicPDFReport` uses `Thread.sleep` blocking the main runloop; silently skips PDF assertion in CI (no microphone) |

### → M15 or near-term (persistence/export — not yet in any milestone)

These are High/Medium findings from the persistence review that should be folded into
M15 task-8 or a new M15 task-10 before acceptance:

| ID | Severity | Finding |
|----|----------|---------|
| PE-2 | High | Partial temp files (PDF, CSV) not deleted after export cancellation or error — `removeItem(at: outputURL)` missing from catch handlers |
| PE-3 | High | `CSVExporter.format(_:)` uses `String(format: "%.3f", value)` which honours process locale — decimal comma on `de_DE`/`fr_FR` devices breaks all CSV numeric values |
| PE-4 | High | `MeasurementDataReader` file handle opened in `init` is not closed on any early-throw path — file descriptor leak per corrupt/version-mismatched file |
| AE-4 | High | `updateProcessingSampleRateIfNeeded` allocates `FFTProcessor`/`WeightingProcessor` objects (calls `vDSP_DFT_zrop_CreateSetup` + `malloc`) on the audio render thread |
| AE-5 | High | `Logger.audioEngine.error/debug` calls inside `processFFTFrame` (every 240 frames + on write error) — `os_log` acquires internal locks, not real-time safe |
| AE-6 | High | LAF percentile histogram ceiling is +10 dB SPL; signals above that silently saturate the histogram, yielding wrong LAF5/LAF95 percentiles |
| AE-7 | High | `fftEnergyScratch` array allocated on audio render thread on first frame after FFT reconfiguration |

### Backlog (Medium / Low, no active milestone)

| ID | Severity | Finding |
|----|----------|---------|
| PE-5 | Medium | `StoredDataProvider.bootstrap()` loads all metric rows (potentially 155 K entries) unconditionally into RAM — no cap or lazy load |
| PE-6 | Medium | `PDFReportGenerator.loadBroadbandValues` passes full frame sequence to chart renderer without downsampling — PDF render time scales with recording duration |
| PE-7 | Medium | `RecordingManager.clearPendingSoftDeleteSidecar` uses `fileExists` + `removeItem` TOCTOU pattern instead of try-remove with per-code-ignore |
| PE-8 | Low | `MeasurementDataWriter.frameCount` incremented on `writeQueue` without synchronization accessible from main-thread reads |

---

## Detailed Findings

### AE — iOS Audio Engine

#### AE-1 · Critical · `AcousticMetricsCalculator` — no synchronization
**File**: `SpektoWatch2/Managers/AcousticMetricsCalculator.swift` (entire class)  
**Also**: `SpektoWatch2/AudioEngine.swift` lines ~1151, ~1525  
`updateMetrics(...)` is called on the audio render thread every frame. `reset()` is called
from `resetMetrics()` on the main thread during a live → recording switch (line ~573)
while `engineStatus == .running`. The class has no lock at all. All energy accumulators
(`lafEnergy`, `laeqAccumulator`, `lafHistogram`) and the statistics (`getRecordingStatistics`)
can be torn simultaneously. This is the primary scope of M15 task-8.  
**Fix**: Add `OSAllocatedUnfairLock` inside `AcousticMetricsCalculator` guarding all mutable
state, or pass results to main via captured snapshot.

#### AE-2 · Critical · `measurementWriter`/`audioFileWriter` unguarded on audio thread
**File**: `SpektoWatch2/AudioEngine.swift` lines ~1230, ~1542–1543  
Both `var` properties are written on main (`setupMeasurementDataFileIfNeeded`,
`closeMeasurementWriter`) and read on the audio render thread without any lock.
Concurrent `closeMeasurementWriter()` during a write-frame call is a use-after-free.  
**Fix**: Guard behind a dedicated `OSAllocatedUnfairLock<Optional<...>>` for each writer,
or extend `processingLock` coverage to include these reads.

#### AE-3 · Critical · `RecordingCoordinator` `@Published` flags read on audio thread
**File**: `SpektoWatch2/AudioEngine.swift` lines ~1230, ~1542, ~1611  
`isRecordingToFile` and `isMeasurementRecording` forward to `RecordingCoordinator`
`@Published` properties. `@Published` has no thread-safety guarantee. These are written
on main and read on the audio render thread — a data race per the Swift memory model.  
**Fix**: Snapshot both flags into `OSAllocatedUnfairLock<Bool>` state mirroring the
`widgetSpectralWeightingsLock` pattern established in M15 task-2.

#### AE-4 · High · Sample-rate reconfiguration allocates on audio thread
**File**: `SpektoWatch2/AudioEngine.swift` lines ~1217–1221, ~1786–1812  
`updateProcessingSampleRateIfNeeded` is called from `processAudioBuffer` and reallocates
`fftProcessor`, `weightingProcessor`, and `visualSpectrogramProcessor` (calls
`vDSP_DFT_zrop_CreateSetup` + heap alloc) while holding `processingLock`. This fires on
the first render callback of every session.  
**Fix**: Detect the sample-rate change in the tap callback and dispatch the reallocation to
`DispatchQueue.main.async`; guard against duplicate dispatches with an atomic flag.

#### AE-5 · High · `Logger` calls inside `processFFTFrame`
**File**: `SpektoWatch2/AudioEngine.swift` lines ~1562, ~1567–1569  
Apple's unified logging system is not documented as real-time safe (acquires internal locks,
may `malloc` on first call per category). Periodic debug calls every 240 frames will lock the
audio thread on the first tick each session.  
**Fix**: Remove `Logger.*` from the hot path; accumulate error flags in atomics and log from
the main-thread `DispatchQueue.main.async` update block.

#### AE-6 · High · LAF histogram ceiling too low
**File**: `SpektoWatch2/Managers/AcousticMetricsCalculator.swift` lines ~107–111  
The histogram spans −130 to +10 dB (1401 bins × 0.1 dB). With typical calibration offsets
of ~90 dB SPL, real broadband levels routinely exceed +10 dB SPL. Values above the ceiling
silently fall outside the array bounds, yielding wrong LAF5/LAF95 statistics with no error.  
**Fix**: Extend the histogram to ≥ 150 dB SPL, or clamp `broadbandLevel` to the range
before indexing with an `os_log` warning on saturation.

#### AE-7 · High · `fftEnergyScratch` allocated on audio render thread
**File**: `SpektoWatch2/AudioEngine.swift` lines ~1496–1497  
`fftEnergyScratch` is conditionally reallocated inside `processFFTFrame` when its count
does not match `energyCount`. This conditional allocation path runs on the audio render
thread and calls into the system allocator.  
**Fix**: Pre-allocate `fftEnergyScratch` to the new size inside `applyFFTConfiguration`
alongside the existing buffer clears, so the audio hot path never hits the allocating branch.

---

### WA — Watch App

#### WA-1 · Critical · `WKExtendedRuntimeSession` delegate on wrong thread
**File**: `SpektoWatch Watch App/WatchAudioEngine.swift` lines ~501–525  
`extendedRuntimeSession(_:didInvalidateWith:)` and `extendedRuntimeSessionWillExpire(_:)`
both read `isRecording` (a `@Published var`, main-actor only) and call `stopRecording()`
on whatever thread the system delivers the delegate callback. `session = nil` also happens
synchronously on that thread, racing against `handleSceneBackgrounded` and `startRecording`
main-thread reads.  
**Fix**: Wrap both delegate method bodies in `DispatchQueue.main.async { [weak self] in ... }`.

#### WA-2 · High · `LevelCornerWidget` missing from complication reload list
**File**: `Shared/WatchConnectivityManager.swift` lines ~15–19  
`complicationWidgetKinds` enumerates `Circular`, `Rectangular`, `Inline` — but not
`"SpektoWatchLevelCorner"` (registered in `WatchComplicationWidget.swift` line 33).
The corner complication never receives a timeline reload.  
**Fix**: Add `"SpektoWatchLevelCorner"` to both `complicationWidgetKinds` arrays (iOS +
watch copies).

#### WA-3 · High · `sendWithRetry` messageQueue mutation unprotected
**File**: `SpektoWatch2/WatchConnectivityManager.swift` lines ~300–353  
`messageQueue.append` and `isProcessingQueue` reads/writes in `sendWithRetry` are
unprotected. The method can be called from SwiftUI view actions (any thread) while
`sessionReachabilityDidChange` callbacks (already dispatched to main) call `processQueue()`.
Torn reads of `isProcessingQueue` can double-send or double-remove messages.  
**Fix**: Dispatch `sendWithRetry`'s body via `DispatchQueue.main.async`, or add
`dispatchPrecondition(condition: .onQueue(.main))` and enforce main-thread entry at all
call sites.

#### WA-4 · Medium · `WatchLevelMeterView` O(n) `removeFirst`
**File**: `SpektoWatch Watch App/WatchLevelMeterView.swift` lines ~141–145  
`levelHistory` is a plain `[Float]`; `appendLevel` calls `removeFirst()` which shifts all
elements. `RingBuffer` already exists in Shared and is used by `WatchSpectrogramView`.  
**Fix**: Replace `levelHistory: [Float]` with `RingBuffer<Float>(capacity: historyLength)`.

#### WA-5 · Medium · `DateFormatter` allocated per `timeString` call
**File**: `SpektoWatch Watch App/WatchSpectrogramView.swift` lines ~138–141  
A new `DateFormatter` is created on every `timeString(from:)` invocation inside the view
body.  
**Fix**: Promote to `private static let` or file-scope constant.

#### WA-6 · Low · Version mismatch rejection is silent
**File**: `Shared/SpectrogramData.swift` lines ~204–209  
`fromBinaryData` returns `nil` on unknown schema version with no log statement — silent data
loss on version mismatch between iOS and watchOS builds.  
**Fix**: Add `print("[SpectrogramData] Unknown schema version \(version)")`  in the
version-check `else` branch.

---

### PE — Persistence & Export

#### PE-1 · Critical · Integer overflow in `MeasurementDataReader.readFrame`
**File**: `SpektoWatch2/MeasurementDataReader.swift` line ~97  
`UInt64(index * frameSize)` multiplies two `Int` values before casting to `UInt64`. For
large recordings the signed intermediate overflows, producing a corrupt seek offset or an
offset past EOF rather than a clean `invalidFrameIndex` throw.  
**Fix**: Replace with `UInt64(index) * UInt64(frameSize)`.

#### PE-2 · High · Partial export files not deleted after cancellation/error
**File**: `SpektoWatch2/Views/RecordingDetailView.swift` lines ~958–980, ~992–1014  
`finishCancelledExport()` and the general error handler clear in-memory state but never call
`FileManager.removeItem(at: outputURL)`. Cancelled or failed exports leave truncated files
in the temp directory.  
**Fix**: Add `try? FileManager.default.removeItem(at: outputURL)` in both `catch is
CancellationError` and the general `catch` handlers before calling the finish function.

#### PE-3 · High · `CSVExporter.format(_:)` is locale-sensitive
**File**: `SpektoWatch2/CSVExporter.swift` line ~65  
`String(format: "%.3f", value)` honours the process locale. On `de_DE`/`fr_FR` devices
the decimal separator is a comma, corrupting all numeric CSV values.  
**Fix**: Use `String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)`.

#### PE-4 · High · `MeasurementDataReader` file handle leaked on init error
**File**: `SpektoWatch2/MeasurementDataReader.swift` lines ~16–79  
`FileHandle(forReadingFrom:)` is stored in a local before any `self.` assignment. Any
`throw` after that point exits `init` without `deinit` running, leaving the file descriptor
open until process exit.  
**Fix**: Add `var initFailed = true; defer { if initFailed { try? fileHandle.close() } }`
immediately after the `FileHandle` creation; set `initFailed = false` at the last line of
`init`.

#### PE-5 · Medium · `StoredDataProvider.bootstrap()` loads all frames into RAM
**File**: `SpektoWatch2/StoredDataProvider.swift` lines ~169–194  
At 43 fps for a 1-hour recording, `bootstrap` builds ~155 K `StoredMetricRow` entries
(each a `[String: Float]` dictionary) unconditionally. Streaming APIs exist but don't
replace the eager bootstrap.  
**Fix**: Cap bootstrap to ≤ 4 000 summary rows (uniform-stride downsample), matching the
`spectrogramOverview(maxFrameCount:)` approach.

#### PE-6 · Medium · `loadBroadbandValues` passes unbounded frame sequence to chart
**File**: `SpektoWatch2/PDFReportGenerator.swift` lines ~253–263  
The chart renderer receives every broadband dB value with no downsampling. For long
recordings the chart becomes a solid block and PDF render time scales linearly with frame
count.  
**Fix**: Downsample `lineValues` to ≤ 1 000 points before passing to the chart renderer.

#### PE-7 · Medium · `clearPendingSoftDeleteSidecar` TOCTOU on remove
**File**: `SpektoWatch2/RecordingManager.swift` lines ~218–226  
`fileExists` + `removeItem` is a TOCTOU pair. Replace with a direct `removeItem` that
ignores `NSFileNoSuchFileError` specifically.

#### PE-8 · Low · `MeasurementDataWriter.frameCount` read on main without barrier
**File**: `SpektoWatch2/MeasurementDataWriter.swift` lines ~127, ~148–151  
`frameCount` is incremented on `writeQueue` and read externally on main without explicit
synchronization. The `writeQueue.sync` drain before `close()` provides a barrier for the
close path, but mid-write external reads are technically a data race.

---

### UI — iOS UI/SwiftUI

#### UI-1 · Critical · `AudioPlayerManager` completion closure strong `self` capture
**File**: `SpektoWatch2/Views/AudioPlayerManager.swift` lines ~89–93  
`scheduleSegment` completion closure captures `self` strongly. `AVAudioPlayerNode` retains
the block until the segment finishes draining after `stop()`. This prevents `AudioPlayerManager`
from deallocating after view dismissal mid-playback, and the completion fires a second `stop()`
on an already-stopped engine.  
**Fix**: `{ [weak self] in guard let self else { return }; ... }`.

#### UI-2 · High · `promoteSpectrogramResolutionThenApply` untracked GCD work
**File**: `SpektoWatch2/Views/RecordingDetailView.swift` lines ~1240–1259  
`DispatchQueue.global.async` FFT computation is not tracked in any `Task` and is not
cancelled by `onDisappear`. On view dismissal mid-compute, the completion fires and mutates
dismissed-view state.  
**Fix**: Convert to `Task.detached`, store in `spectrogramLoadTask`, check `Task.isCancelled`
before state mutation.

#### UI-3 · High · `applyPlaybackWeighting` untracked GCD work
**File**: `SpektoWatch2/Views/RecordingDetailView.swift` lines ~1212–1226  
Rapid weighting-picker changes queue multiple competing `DispatchQueue.global.async`
mutations to `weightedSpectrogramCache` with no cancellation. All run to completion even
after view dismissal.  
**Fix**: Convert to `Task.detached`, store in `@State var weightingTask`, cancel before
creating a new one.

#### UI-4 · High · `exportSpectrogramImage` can present share sheet on dismissed view
**File**: `SpektoWatch2/Views/RecordingDetailView.swift` lines ~1051–1064  
`DispatchQueue.global.async` work is not tracked; `showShareSheet = true` is set in the
main-thread callback even if the view has been dismissed. On iOS 17+, presenting a sheet
from a view controller not in the window hierarchy triggers a `UISheetPresentationController`
assertion failure.  
**Fix**: Convert to `Task.detached`, store in `@State var spectrogramExportTask`, cancel in
`onDisappear`, guard completion with `if Task.isCancelled { return }`.

#### UI-5 · Medium · Export overlay stuck during slow cancellation
**File**: `SpektoWatch2/Views/RecordingDetailView.swift` lines ~1017–1019  
`cancelActiveExport()` calls `exportTask?.cancel()` but does not clear `activeExportKind`.
The overlay remains visible until `CancellationError` propagates through the PDF renderer —
potentially seconds.  
**Fix**: Set `activeExportKind = nil` immediately inside `cancelActiveExport()`.

#### UI-6 · Medium · `PhotoPickerView` `isPresented` binding not reset
**File**: `SpektoWatch2/Views/PhotoPickerView.swift` lines ~27–38  
The delegate calls `picker.dismiss` directly without resetting the `isPresented` SwiftUI
binding. After the first presentation, the binding may remain `true`, preventing
re-presentation.  
**Fix**: Pass and set `isPresented = false` alongside `picker.dismiss`.

#### UI-7 · Medium · `DashboardViewModel` nested `ObservableObject`
**File**: `SpektoWatch2/DashboardViewModel.swift` line ~7  
`@Published var dashboardManager = DashboardManager()` publishes only reference replacement,
not nested `@Published` mutations. The manual `objectWillChange` forwarding is a workaround
that does not compose cleanly with SwiftUI dependency tracking for bindings.  
**Fix**: Inject `dashboardManager` as `let dashboardManager: DashboardManager` or as a
direct `@EnvironmentObject`.

---

### TT — Tests & Tooling

#### TT-1 · Critical · New M15 test files not in `project.pbxproj`
**Files**: `RecordingPersistenceDurabilityTests.swift`, `WatchDSPParityTests.swift`,
`StoredDataProviderTests.swift` (and verify `CSVExporterTests.swift`, `PDFReportGeneratorTests.swift`)  
None of these three files are referenced in `project.pbxproj`. They exist on disk but are
never compiled or run by any `xcodebuild test` invocation or Xcode Cloud job. Every M15
task acceptance criterion citing them as evidence is currently unverifiable.  
**Fix**: Open the project in Xcode and enable `SpektoWatch2Tests` target membership for all
three files via the File Inspector.

#### TT-2 · Critical · `testPDFGenerationCancellationThrowsQuickly` is a false positive
**File**: `SpektoWatch2Tests/PDFReportGeneratorTests.swift` lines ~390–413  
`task.cancel()` is called from the test actor with no cooperative suspension after task launch.
The detached task may complete entirely before `cancel()` fires, causing `XCTFail("PDF
generation should throw CancellationError")` — but the thrown error is a non-cancellation
`PDFRendererErrors`, so the test silently swallows the failure. The 0.5 s timing assertion
is measured from `cancel()` time, not task start — a normally-completing 0.4 s run also
passes.  
**Fix**: Insert `await Task.yield()` after `task.cancel()`. Use a fixture large enough that
`loadBroadbandValues` cannot complete in a single scheduling quantum, or inject a deliberate
async suspension point into the generator.

#### TT-3 · High · Cancellation tests in `StoredDataProviderTests` and `CSVExporterTests` share the same false-positive race
**Files**: `SpektoWatch2Tests/StoredDataProviderTests.swift` lines ~58–75;
`SpektoWatch2Tests/CSVExporterTests.swift` lines ~379–402  
Same pattern as TT-2: `task.cancel()` with no yield; fast hosts complete before cancel fires;
no fallback `catch` for non-`CancellationError` failures — those surface as unhandled errors.  
**Fix**: Add `await Task.yield()` after `task.cancel()`, increase fixture size to 10 K frames,
add a `catch { XCTFail("Unexpected error: \(error)") }` fallback.

#### TT-4 · High · `testRecordingDecodeWithMissingID_throws` metadata backup in test body
**File**: `SpektoWatch2Tests/RecordingPersistenceDurabilityTests.swift` lines ~226–293  
Backup/restore is inside the test body, not `setUp`/`tearDown`. A `fatalError` or process
kill between backup and defer leaves the user's real `recordings_metadata_v2.json` absent.
Parallel test runs sharing the same Documents directory can cross-contaminate.  
**Fix**: Move backup/restore into `setUp`/`tearDown`, or supply a temporary directory root
via `AppServices.testFixture(recordingManager:)`.

#### TT-5 · High · `acp-validate` required-file list stops at M5
**File**: `agent/scripts/acp-validate` lines ~7–57  
The `required` static list does not include any M6–M15 milestone or task files. Deleting an
accepted task record passes the script silently.  
**Fix**: Add M6–M15 milestone `.md` file paths to the required list, or add a loop that
validates all `.md` files under `agent/tasks/milestone-15-critical-stability-correctness/`.

#### TT-6 · High · `capture-screenshots.py` silently drops all attachments on non-legacy xcresult
**File**: `agent/scripts/capture-screenshots.py` lines ~140–153  
`walk_attachments` checks `isinstance(attachments, dict)` and extracts `_values`. If
`xcresulttool` drops `--legacy` format (Apple's stated direction), attachments arrive as a
plain `list`, the guard is false, and the script exits with code 0 reporting "Captured 0
screenshots".  
**Fix**: Add fallback: `values = attachments.get("_values", attachments) if isinstance(attachments, dict) else attachments`.

#### TT-7 · Medium · `testCSVNumericFormatThreeDecimalPlaces` fragile
**File**: `SpektoWatch2Tests/CSVExporterTests.swift` lines ~312–330  
Iterates all columns with a nondeterministic `Float.random` broadband value; a value like
`-5.1234` formatted to 4 places fails the `parts.count == 2` assertion without a clear
diagnosis. First-column timestamp `0.000` formatting also varies.  
**Fix**: Replace `Float.random` with a deterministic constant; assert decimal precision only
on known-value columns.

#### TT-8 · Medium · `testBootstrapKeepsSmallMetricDataEager` conflates two concepts
**File**: `SpektoWatch2Tests/StoredDataProviderTests.swift` lines ~20–30  
`hasFullFFT == true` reflects `fftBinCount > 0` in the file header, not that FFT data was
eagerly loaded. A future lazy-load refactor will still pass this test.  
**Fix**: Rename to `testBootstrapEagerlyLoadsLevelHistoryAndMetricRows`; move `hasFullFFT`
to a dedicated test with a `fftBinCount: 0` fixture for the negative case.

#### TT-9 · Medium · `testGenerateBasicPDFReport` uses `Thread.sleep` on main runloop
**File**: `SpektoWatch2Tests/PDFReportGeneratorTests.swift` lines ~51–99  
`Thread.sleep(forTimeInterval: 0.5)` blocks the main runloop, preventing `RecordingManager`
timers from firing. In CI (no microphone), the `stoppedAudioURL` guard triggers `XCTFail`
and returns — no PDF is generated, no PDF assertion is reached. Test always appears green
in CI.  
**Fix**: Use `createTestRecording()` directly to bypass the `RecordingManager` recording
lifecycle; replace `Thread.sleep` with `XCTestExpectation`.

---

## Additional Coverage Gaps (not in M18 list)

1. **`acp-validate` static file list** covers M1–M5 only; completed M6–M15 acceptance records are
   unguarded against deletion.
2. **`capture-screenshots.py` attachment-walking logic** has no unit test; a format change would
   produce silent zero-screenshot output.
3. **`createTestMeasurementFile` uses `try!`** throughout both `PDFReportGeneratorTests` and
   `CSVExporterTests` — any writer failure crashes the test process rather than producing an XCTest
   failure.
4. **`RecordingPersistenceDurabilityTests.tearDown`** instantiates a fresh `RecordingManager()` for
   cleanup — if the initializer hangs on a corrupt metadata file, test artifacts accumulate across
   runs.
5. **`WatchDSPParityTests` has no coverage of `performVisualDCT`** — the `20·log10` DCT fix (M15
   task-3) is only tested via a math-abstraction test, not against the production
   `WatchAudioEngine.performVisualDCT` function.

---

## Routing Summary

| Milestone | New findings added |
|-----------|-------------------|
| **M15** | AE-1, AE-2, AE-3 (task-8 scope), PE-1, PE-2, PE-3, PE-4 (new task-10), TT-1 (immediate action) |
| **M15 task-8** | Also captures AE-4, AE-5, AE-7 (audio-thread malloc/logging) and AE-6 (histogram ceiling) |
| **M16** | WA-1, WA-2, WA-3, WA-4, WA-5, WA-6 |
| **M17** | UI-1, UI-2, UI-3, UI-4, UI-5, UI-6, UI-7 |
| **M18** | TT-2, TT-3, TT-4, TT-5, TT-6, TT-7, TT-8, TT-9 + 5 coverage gaps |
| **Backlog** | PE-5, PE-6, PE-7, PE-8 |

Generated: 2026-05-24  
Source: 5-subagent parallel review (AE / WA / PE / UI / TT)
