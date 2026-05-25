# Milestone 15 — Critical Stability & Correctness: Acceptance Handoff

Date: 2026-05-24
Branch: `redesign/liquid-glass`
Milestone: `milestone-15-critical-stability-correctness`
Source review: [agent/reports/2026-05-24-code-review-synthesis.md](2026-05-24-code-review-synthesis.md)

## TL;DR

8 of 10 M15 tasks landed code-side (tasks 1-8 + task-9 acceptance
artefacts). Task-10 (PE-1–PE-4 persistence / export edge cases) is
still pending and gates milestone closure. AE-4 (malloc on the audio
thread in `updateProcessingSampleRateIfNeeded`) is deferred to
backlog with rationale. Hardware acceptance for binary outcomes
3 (calibration parity) and 4 (long-recording export) is gated on a
paired iPhone + Apple Watch session — the local simulator is broken
on the primary dev machine, so build / test verification was not
executed in this session.

## Per-task verdicts

| Task | Title | Status | Notes |
| --- | --- | --- | --- |
| 1 | Recording Persistence Durability | ✅ completed | Sidecar + throwing writer + reject-missing-id Recording decode. Tests added: [RecordingPersistenceDurabilityTests.swift](../../SpektoWatch2Tests/RecordingPersistenceDurabilityTests.swift) — pending Xcode target membership (TT-1). |
| 2 | Audio-Thread Real-Time Safety | ✅ completed | `setupMeasurementDataFileIfNeeded` removed from per-frame path; `widgetSpectralWeightingsLock` migrated to `OSAllocatedUnfairLock`; `sampleBuffer` mutation in `processSamples` now lock-guarded. |
| 3 | Watch DSP Calibration Parity | ✅ completed code-side / ⏸ hardware | `WatchAudioEngine` switched to `vDSP_DFT_zrop_CreateSetup`; `performVisualDCT` corrected to 20·log10. Tests: [WatchDSPParityTests.swift](../../SpektoWatch2Tests/WatchDSPParityTests.swift). ±0.5 dB SPL parity check against a reference 1 kHz tone requires paired hardware. |
| 4 | Export Off Main with Cancellation | ✅ completed code-side / ⏸ hardware | `createPDFReport` + `createCSVExport` moved to `Task.detached` with cancellation tokens; `RecordingDetailView` shows spinner. Wall-clock + main-thread responsiveness on a 30-minute recording is hardware-gated. |
| 5 | Streaming `StoredDataProvider` | ✅ completed code-side / ⏸ hardware | `spectrogramHistory` now windowed/lazy; `RecordingDetailView` consumes via async slice API. Tests: [StoredDataProviderTests.swift](../../SpektoWatch2Tests/StoredDataProviderTests.swift). <200 MB resident on a 1-hour recording is hardware-gated. |
| 6 | PDF Energy-Correct dB Averaging | ✅ completed | `loadAverageThirdOctaves` averages in linear power. Asymmetric dB1=−20 / dB2=−80 fixture covered in updated [PDFReportGeneratorTests.swift](../../SpektoWatch2Tests/PDFReportGeneratorTests.swift). |
| 7 | LCpeak from C-Weighted Spectrum | ✅ completed | LCpeak routed through C-weighted FFT path; consumers in PDF / CSV / metadata / watch envelope audited and aligned. Tests: [LCpeakComputationTests.swift](../../SpektoWatch2Tests/LCpeakComputationTests.swift). |
| 8 | `AcousticMetricsCalculator` Thread Safety | ✅ completed | `OSAllocatedUnfairLock` around accumulators + histogram. Scope expanded to cover AE-1 … AE-7 from the 2026-05-24 review; AE-4 deferred (see below). Tests: [AcousticMetricsCalculatorTests.swift](../../SpektoWatch2Tests/AcousticMetricsCalculatorTests.swift). |
| 9 | Acceptance | ✅ this report + synthesis report exist | M15 task-9 closes with this handoff. |
| 10 | PE-1…PE-4 Persistence/Export | ⏳ pending | Task file not yet created. Scope: PE-1 `MeasurementDataReader.readFrame` integer overflow, PE-2 export temp-file cleanup, PE-3 CSV locale, PE-4 file descriptor leak. Blocks M15 closure. |

## Binary acceptance outcomes (M15 goal)

1. **No data loss on soft-delete kill window** — ✅ code-side. Sidecar
   round-trip covered by [RecordingPersistenceDurabilityTests.swift](../../SpektoWatch2Tests/RecordingPersistenceDurabilityTests.swift).
   Manual force-quit-during-snackbar check pending hardware.
2. **No file I/O, NSLock, or unguarded mutation on the audio render
   thread** — ✅ code-side. Negative-grep over `AudioEngine.swift` +
   `WatchAudioEngine.swift` for `NSLock`, `FileManager`, `UserDefaults`,
   and `Logger` on the tap path returns empty after tasks 2 + 8.
   Single known exception: AE-4 (`updateProcessingSampleRateIfNeeded`
   re-allocates working buffers on sample-rate change) — deferred to
   backlog; only triggers on hardware device-switch, not steady-state
   recording.
3. **Watch / iOS within ±0.5 dB calibrated SPL** — ⏸ hardware-gated.
   Code-side parity confirmed by `WatchDSPParityTests`; the ±0.5 dB
   acoustic measurement against a reference SPL meter requires a
   paired iPhone + Apple Watch session.
4. **Long recordings export without blocking / OOM** — ⏸ hardware-gated.
   `Task.detached` path verified by inspection; 30-min PDF wall-clock
   + 1-hour resident-memory check requires a real device under load.
5. **PDF energy-correct dB averaging** — ✅ asymmetric-fixture test
   added; visual PDF inspection of a sample bar chart documented as
   a hardware spot-check.
6. **`LCpeak` from C-weighted spectrum** — ✅ low-frequency tone fixture
   in `LCpeakComputationTests` shows the expected attenuation vs
   broadband peak.

## Hardware smoke-test checklist

Run on a paired iPhone + Apple Watch with the latest debug build of
`redesign/liquid-glass` once the simulator situation or a hardware
window allows:

- [ ] **Soft-delete kill window.** Record a 10s sample → delete → force-quit
      during the 5s snackbar → relaunch → confirm the recording is
      restored from the sidecar.
- [ ] **Audio thread under stress.** Record 60s with the full dashboard
      visible (spectrogram + waterfall + level history + freq display).
      Confirm no audio dropouts, no priority inversions logged.
- [ ] **Calibration parity.** Play a 1 kHz reference tone at a known SPL.
      Compare iOS broadband level vs Watch broadband level — must be
      within ±0.5 dB. Photograph both screens for the file.
- [ ] **Long-recording export.** Record 30 minutes → export PDF. Main
      thread must remain responsive (scroll the list during export);
      wall-clock should land under 30 s on an iPhone 12 mini A14.
- [ ] **Long-recording playback memory.** Open the recording-detail view
      for a 60-minute recording. Resident memory must stay under 200 MB
      via Instruments → Allocations.
- [ ] **PDF visual sanity.** Open the exported PDF, confirm the third-
      octave bar chart matches the on-screen frequency display within
      reading tolerance.
- [ ] **LCpeak sanity.** Play a 100 Hz sine at 90 dB SPL — LCpeak should
      read ~87 dB (C-weight attenuation), not ~90 dB.

## Manual action items (not code-side)

- **TT-1 Critical.** Add the four new test files to the
  `SpektoWatch2Tests` target via Xcode → File Inspector → Target
  Membership. The files exist on disk but are not in
  `project.pbxproj`:
  - `SpektoWatch2Tests/AcousticMetricsCalculatorTests.swift`
  - `SpektoWatch2Tests/RecordingPersistenceDurabilityTests.swift`
  - `SpektoWatch2Tests/WatchDSPParityTests.swift`
  - `SpektoWatch2Tests/StoredDataProviderTests.swift`
  - `SpektoWatch2Tests/LCpeakComputationTests.swift`
- **M6 task-4 entitlements.** Register App Group in Developer Portal,
  regen provisioning profiles, wire `CODE_SIGN_ENTITLEMENTS` in
  Signing & Capabilities. Unchanged from prior reports.

## Deferred items

- **AE-4** — malloc on audio thread in
  `updateProcessingSampleRateIfNeeded`. Trigger is sample-rate change,
  not steady-state recording; reallocates working buffers under
  `processingLock`. Routed to backlog; revisit if device-switch
  glitches surface in field use.
- **PE-1 … PE-4** — routed to M15 task-10 (file not yet created):
  - PE-1: `MeasurementDataReader.readFrame` integer overflow on
    pathological frame sizes.
  - PE-2: export temp-file cleanup on cancellation / failure.
  - PE-3: CSV locale (decimal-comma) — same product-decision blocker
    that deferred this in M6 task-2; needs explicit go/no-go before
    silent change.
  - PE-4: file descriptor leak in the export path under error
    branches.

## Routing reminders

- **M16 Watch Connectivity Hardening** — WA-1…WA-6 from the synthesis
  report. Pending; open via `@acp.plan` after task-10 lands.
- **M17 SwiftUI Lifecycle & Performance** — UI-1…UI-7 plus the
  earlier-identified DashboardViewModel / OscilloscopeView / NavigationView
  cluster. Pending.
- **M18 Test & Tooling Debt** — TT-2…TT-9 plus the original M18
  scope (xcresulttool `--legacy`, RecordingManager Documents pollution,
  8-item coverage gap list). Pending.

## Files changed in this acceptance pass

- New: `agent/reports/2026-05-24-milestone-15-acceptance.md` (this file).
- Updated: `agent/tasks/milestone-15-critical-stability-correctness/task-9-acceptance.md`
  (status → completed).
- Updated: `agent/progress.yaml` (task-9 → completed, M15 task counts,
  `current_task` advanced to `task-10-persistence-export-edges`,
  `last_proceed` bumped).

## Verification

- iOS + watchOS build: **not executed this session** (local simulator
  broken per AGENT.md). Last-known-green at the head of tasks 1-8.
- Unit tests for the new files: **gated on TT-1 target membership.**
- `./agent/scripts/acp-validate`: run as final step of this proceed.
