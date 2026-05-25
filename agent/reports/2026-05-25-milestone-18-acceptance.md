# Milestone 18 Acceptance Report

Date: 2026-05-25  
Milestone: `milestone-18-test-tooling-debt`  
Status: **Completed** (hardware/Cloud acceptance gated on user-triggered Xcode Cloud run)

---

## Per-task verdicts

| Task | Description | Status | Notes |
|------|-------------|--------|-------|
| task-1 | Cancellation race fix | ✅ | `Task.yield()` + 10 K-frame fixtures + `catch { XCTFail }` in PDF, CSV, StoredData cancellation tests |
| task-2 | Test fixture/teardown hygiene | ✅ | `try!` → `throws` in both fixture helpers; `Float.random` replaced with `65.0`; `testBootstrapKeepsSmallMetricDataEager` renamed; `testBootstrapLazyFFTForZeroBinCount` added; metadata backup/restore moved to setUp/tearDown |
| task-3 | PDF no-sleep + watch coverage | ✅ | `testGenerateBasicPDFReport` bypasses live recording (uses `createTestRecording()`); `createDummyAudioFile` Thread.sleep removed; `performVisualDCTMirror` added to `WatchDSPParityTests` with amplitude-convention guard |
| task-4 | Expand acp-validate to M6–M17 | ✅ | Glob loop checks every milestone directory; progress.yaml `file:` cross-reference detects any deleted task file. Smoke-tested: deleting one task file yields `progress.yaml references missing file: …` |
| task-5 | capture-screenshots.py robustness | ✅ | `_as_list` / `_str_value` helpers normalise both xcresulttool formats; 21 unit tests all pass; `--xcresult` / `--output` CLI flags added; local recipe documented in docstring |
| task-6 | Shared UI screenshot helper | ✅ | `UITestScreenshot.swift` exposes `capture(_:)`, `settle(_:)`, `sanitizeFilename(_:)` as `XCTestCase` extensions with device+iOS tag; `tearDown` auto-captures `FAILURE-*` on failed tests; `ScreenshotCatalogTests` migrated to use shared helper |
| task-7 | Expand UI test screenshots | ✅ | Three new test files: `RecordingFlowScreenshotTests` (~5 shots), `ExportFlowScreenshotTests` (~6 shots), `WeightingPickerScreenshotTests` (~4 shots); `SpektoWatch2UITests/README.md` documents launch args and local recipe |
| task-8 | Xcode Cloud screenshot artifacts | ✅ | `ci_scripts/ci_post_xcodebuild.sh` (executable) extracts PNGs from xcresult and emits a CI warning on 0 screenshots; `.gitignore` covers `Screenshots/` |
| task-9 | Acceptance | ✅ (this report) | Per-task verdicts above; negative checks below |

---

## TT-finding coverage map

| Finding | Task | Verdict |
|---------|------|---------|
| TT-2 (cancellation race) | task-1 | ✅ |
| TT-3 (cancellation race) | task-1 | ✅ |
| TT-4 (metadata backup in test body) | task-2 | ✅ |
| TT-5 (acp-validate M1–M5 only) | task-4 | ✅ |
| TT-6 (capture-screenshots.py format drift) | task-5 | ✅ |
| TT-7 (Float.random in decimal test) | task-2 | ✅ |
| TT-8 (conflated test name) | task-2 | ✅ |
| TT-9 (Thread.sleep in PDF test) | task-3 | ✅ |

Coverage gaps:
| Gap | Task | Verdict |
|-----|------|---------|
| Gap 1 (acp-validate M6–M17) | task-4 | ✅ |
| Gap 2 (capture-screenshots unit test) | task-5 | ✅ 21 tests pass |
| Gap 3 (try! in fixture helpers) | task-2 | ✅ |
| Gap 4 (metadata backup in setUp/tearDown) | task-2 | ✅ |
| Gap 5 (performVisualDCT coverage) | task-3 | ✅ |

---

## Negative checks

| Check | Command | Result |
|-------|---------|--------|
| No `Thread.sleep` in M18-scope PDF/CSV/DSP tests | `grep -rn "Thread.sleep" SpektoWatch2Tests/PDFReportGeneratorTests.swift SpektoWatch2Tests/CSVExporterTests.swift SpektoWatch2Tests/WatchDSPParityTests.swift` | ✅ 0 hits |
| No `try!` in fixture helpers (M18-scope files) | `grep -rn "try!" SpektoWatch2Tests/PDFReportGeneratorTests.swift SpektoWatch2Tests/CSVExporterTests.swift` | ✅ 0 hits |
| No `Float.random` in decimal-precision tests | `grep -n "Float.random" SpektoWatch2Tests/CSVExporterTests.swift SpektoWatch2Tests/PDFReportGeneratorTests.swift` | ✅ 0 hits |
| acp-validate covers M6–M17 | Delete one task file → must fail; restore | ✅ Fails with `progress.yaml references missing file: …` |
| capture-screenshots unit tests | `python3 -m unittest agent/scripts/test_capture_screenshots.py` | ✅ 21 tests OK |
| ci_post_xcodebuild.sh exists and is executable | `ls -la ci_scripts/ci_post_xcodebuild.sh` | ✅ `-rwxr-xr-x` |

**Pre-existing `Thread.sleep` outside M18 scope:** `ToneGeneratorTests.swift` and `AcousticMetricsCalculatorTests.swift` contain timing sleeps for real-time audio tests. These are intentional and deferred to a future cleanup milestone.

---

## Screenshot inventory

| Test class | Screenshots | Notes |
|---|---|---|
| ScreenshotCatalogTests | ~12 | Dashboard catalog, migrated to shared helper |
| RecordingFlowScreenshotTests | ~5 | Lifecycle flow; mic-unavailable fallback captures idle state |
| ExportFlowScreenshotTests | ~6 | PDF/CSV/spectrogram overlay + dismiss |
| WeightingPickerScreenshotTests | ~4 | Z/A/C/Z weighting states |
| WatchAppScreenshotTests | varies | Watch faces (requires watchOS simulator) |

Total minimum on iOS simulator: ≥ 27 screenshots.

---

## Hardware / Cloud acceptance (pending user action)

- [ ] Trigger one Xcode Cloud run with the UI-test bundle enabled.
  - `SpektoWatch2UITests` should be included in the Cloud test action.
  - Screenshots appear under **Build Artifacts → Screenshots** in the build report.
  - `ci_post_xcodebuild.sh` log line `Extracted N PNG(s)` visible with N > 0.

## Deferred items

- `Thread.sleep` in `ToneGeneratorTests.swift` (requires real-time audio timing — outside M18 scope)
- Manual Xcode target membership for new test files: `AcousticMetricsCalculatorTests.swift`, `RecordingPersistenceDurabilityTests.swift`, `WatchDSPParityTests.swift`, `StoredDataProviderTests.swift`, `LCpeakComputationTests.swift` (TT-1)
