# Milestone 14 Acceptance — Performance & Centralization

**Date:** 2026-05-25  
**Milestone:** M14 — Performance & Centralization  
**Source audit:** agent/reports/2026-05-21-performance-centralization-audit.md  

---

## Per-Task Verdict

| Task | Name | Status |
|------|------|--------|
| task-1 | Quick wins (R6+R7+R8+R9) | ✅ completed 2026-05-25 |
| task-2 | Centralize loudness (R4) | ✅ completed 2026-05-25 |
| task-3 | Per-band Leq in metrics (R3) | ✅ completed 2026-05-25 |
| task-4 | Bark precompute upstream (R2) | ✅ completed 2026-05-25 |
| task-5 | Masking receives Z bands (R11) | ✅ completed 2026-05-25 (verification reversal) |
| task-6 | Tighten weighting contract (R5) | ✅ completed 2026-05-25 |
| task-7 | Investigate double smoothing (R10) | ✅ completed 2026-05-25 (decision B) |
| task-8 | Kill vizAudioEngine (R1) | ✅ completed 2026-05-25 |
| task-9 | Acceptance | ✅ code-side complete; hardware deferred |
| task-10 | DCT visual path, FFT measurement path | ✅ completed 2026-05-22 (opportunistic) |

---

## Binary Outcome Coverage

### 1. Single AudioEngine instance per app lifetime ✅

`grep "AudioEngine(filterManager:" SpektoWatch2/**/*.swift` (excluding tests and `.claude/`):

```
SpektoWatch2/AppServices.swift:117  ← sole factory site
SpektoWatch2/PlaybackAnalyzer.swift:21  ← comment only (documentation)
```

`RecordingDetailView` previously constructed a second engine:
```swift
// REMOVED:
@StateObject private var vizAudioEngine = AudioEngine(
    filterManager: BandstopFilterManager(),
    connectivityManager: WatchConnectivityManager()
)
```
Replaced by `@EnvironmentObject audioEngine: AudioEngine` + `PlaybackAnalyzer` coordinator.

### 2. Zero per-bin/per-band aggregation inside SwiftUI Canvas closures ✅

`SpectrumBandChartView.Canvas` (`AudioWidgets.swift`):
- **third-octave**: reads `leqThirds` — pre-computed array from `AudioEngine.bandLeqZ/A/C`
- **octave**: `SpectrumBandAggregator.octaveBands(fromThirds:)` — 10 power-sums from precomputed thirds (not a full FFT walk)
- **bark**: reads `precomputedBark` when non-empty; inline fallback only on the first frame before `DashboardViewModel` registers the requirement

No Canvas closure walks the raw FFT spectrum.

### 3. All acoustic metrics in AcousticMetricsCalculator ✅

- `updateMetrics(frequencies:magnitudes:bandsZ:bandsA:bandsC:)` computes broadband levels, per-band Leq EMA, PHON, and SONE.
- `MetricsResult` struct bundles `levels: [String: Float]` + `bandLeqZ/A/C: [Float]`.
- Per-widget `@StateObject LoudnessCalculator` instances removed from `LevelHistoryWidget`, `SingleValueWidget`, `WatchLoudnessWidget` (task-2).
- `LoudnessCalculatorView` (settings UI) retains its own instance — correct, it's not a data widget.

### 4. MeasurementDataWriter is the only recording-time output path ✅

`MeasurementDataWriter.writeFrame` is called exclusively from `AudioEngine.processFFTFrame` (line ~1708), gated by the existing `measurementWriter` lock. `RealtimeAudioFileWriter` handles the PCM stream. No secondary metric accumulation runs in parallel.

---

## Build Status ✅

| Target | Result |
|--------|--------|
| iOS (Simulator, Debug) | `** BUILD SUCCEEDED **` |
| watchOS (Simulator, Debug) | `** BUILD SUCCEEDED **` |

---

## What Each Task Changed

### task-1 — Quick wins (R6+R7+R8+R9)

- **R8**: calibration snapshot moved to top of `processFFTFrame` (4 reads → 1).
- **R9**: already done via `BandstopFilterManager.snapshotEnabledFilters` + didSet invalidation.
- **R7**: `currentOctaveBands` alias + forwarder + 2 writes removed; `displayOctaveBands` weighting-selector removed; `OctaveBandWidget` reads weighted variant directly.
- **R6**: `currentSpectrum` forwarder + 2 writes removed; fallbacks use `[]`.
- `LiveAcousticState` publishes 10 properties (was 12); `updateUI()` drops 2 parameters.

### task-2 — Centralize loudness (R4)

- Static PHON/SONE helpers added to `LoudnessCalculator` (splTable precomputed at class load, no audio-thread alloc).
- `updateMetrics` gains `frequencies` + `magnitudes` parameters; computes PHON+SONE after the lock block.
- `WatchAudioEngine` includes PHON/SONE in `SpectrogramData.levels`.
- `@StateObject LoudnessCalculator` removed from `LevelHistoryWidget`, `SingleValueWidget`, `WatchLoudnessWidget` (~65 LOC deleted).

### task-3 — Per-band Leq (R3)

- `MetricsResult` struct introduced.
- `AcousticMetricsCalculator` gains `leqBandAlpha = 0.02`, per-band EMA buffers under lock.
- `LiveAcousticState` gains `bandLeqZ/A/C`.
- `SpectrumBandChartView.leqValues @State` + `updateLeq` + `resetLeq` removed; view accepts `leqThirds: [Float]` param.
- 4 new unit tests added.

### task-4 — Bark precompute (R2)

- `widgetBarkBandsRequiredLock` (OSAllocatedUnfairLock) + `setWidgetBarkBandsRequired` added to `AudioEngine`.
- Bark bands computed once per frame (gated); `LiveAcousticState` gains `currentBarkBandsZ/A/C`.
- `SpectrumBandChartView` reads `precomputedBark` when non-empty; fallback inline.
- `DashboardViewModel` scans `frequencyBands` settings; calls `setWidgetBarkBandsRequired`.

### task-5 — Masking Z bands (R11)

Verification reversal: both `onBandsUpdated` call sites already pass `octaveBandsZ` after task-1 removed the `displayOctaveBands` weighting-selector. Contract comment added to `MaskingEngine.wireAudioEngine`.

### task-6 — Tighten weighting contract (R5)

`SpectrogramData.magnitudes(for:)` now uses explicit `if let` branches with `#if DEBUG` logs on fallback. Settings-change path confirmed single call site (`WidgetSettingsView.onSave` → Combine sink). Optional API change not taken (double-optional ripple).

### task-7 — Investigate double smoothing (R10)

Decision **B** — intentional parallel pipelines:
- CPU EMA (`SpectrogramProcessor.temporalSmoothing`): IEC 61672 time-weighting on FFT dB measurements. Does **not** feed the live spectrogram texture in normal operation (adapter prefers DCT/Mel `visualMagnitudes`).
- GPU Gaussian (`HighEndSpectrogramShaders.metal`): 11-tap blur on [0,1] DCT/Mel texture values. Display anti-aliasing only.
- No stacking in normal live rendering. Documentation added to both files.

### task-8 — Kill vizAudioEngine (R1)

- New `PlaybackAnalyzer.swift` (100 LOC): saves/restores main engine state; stops live mode on `start()`; routes `processSamples` through `engine.processExternalAudio`; resumes live mode on `stop()`.
- `RecordingDetailView`: `@StateObject vizAudioEngine = AudioEngine(...)` **removed**; `@EnvironmentObject audioEngine` added; `@StateObject playbackAnalyzer` added; both `HighEndSpectrogramAdapterWithAxes` and `WidgetCardView` pass the main engine.

### task-10 — DCT visual path (opportunistic, 2026-05-22)

`SpectrogramData` gained `visualMagnitudes`/`visualFrequencies`; `VisualSpectrogramProcessor` (DCT-II/Mel) runs alongside FFT measurement path; `HighEndSpectrogramAdapter` prefers DCT visual arrays; measurement semantics remain FFT-based.

---

## Verification Reversals

| Audit finding | Outcome |
|---|---|
| R11 (masking weighting drift) | Already fixed by task-1 removing `displayOctaveBands` selector — no new code needed |

---

## Hardware Acceptance (Deferred)

The following items require a physical device or Instruments trace and cannot be automated code-side:

- **CPU drop ≥ 5%** during 4-widget live dashboard vs. M13 baseline (Instruments)
- **CPU drop ≥ 20%** during recording playback (one DSP pipeline confirmed, measurement deferred)
- **WidgetCardView re-render count** near-zero for non-live widgets under live audio
- **LAF/LAeq/LCpeak reference signal** parity vs. M13 baseline
- **Frequency-spectrum pixel diff ≤ 1%** per band in third-octave/octave/Bark modes
- **Masking novelty score invariant** to A/C weighting toggle (documented in task-5)

These items are tracked in `agent/tasks/milestone-14-performance-centralization/task-9-acceptance.md` and should be verified on the next hardware pass.

---

## Open Follow-Ups

| Item | Route |
|---|---|
| Phase 3 widget protocol refactor (M13 task-4 Phase 2): migrate 10 live widgets to observe `audioEngine.live` directly so engine forwarders + bridge can be removed | Future milestone / M13 continuation |
| `PlaybackAnalyzer` Phase 2: extract own FFTProcessor+SpectrogramProcessor so main engine EMA state is not reset on playback start | Future task (low priority if CPU target is met) |
| Hardware acceptance pass for M14 outcomes | Next device session |
