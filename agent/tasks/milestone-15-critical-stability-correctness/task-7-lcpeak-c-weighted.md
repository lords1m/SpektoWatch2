# Task 7: `LCpeak` from the C-Weighted Spectrum

Status: completed
Created: 2026-05-23
Completed: 2026-05-24
Milestone: `milestone-15-critical-stability-correctness`
Source: 2026-05-23 code review — DSP H1

## Goal

`LCpeak` as currently implemented is misnamed: it's computed from
the raw broadband sample peak with the calibration offset added, not
from the C-weighted spectrum. Users reading "LCpeak" in CSV exports,
PDF reports, recording metadata, and the watch envelope are seeing a
broadband-with-offset value labeled as C-peak. Standards (IEC 61672)
define LCpeak as the peak instantaneous value of the C-weighted
signal.

## Scope

### Sub-1: Compute LCpeak correctly

In `AudioEngine.processFFTFrame` (~line 1275), `peakLevel` is
fed into `AcousticMetricsCalculator.updateMetrics` as the LCpeak
input. `peakLevel` derives from the raw broadband sample peak.

**Fix:** route LCpeak through the C-weighted FFT path. The
C-weighted magnitudes are already computed conditionally when a
widget consumer requires them (`requiredSpectralWeightingsForCurrentFrame`).

Approach A: ensure the C-weighted spectrum is always computed when
recording (so LCpeak has a source), then derive the peak
instantaneous value from it (inverse FFT to time domain is the
strictly-correct path; a frequency-domain peak detector is the
practical one).

Approach B: apply a C-weighting time-domain filter (biquad cascade)
to the sample buffer in parallel with the FFT, take the absolute
peak. More CPU but produces the IEC-correct value.

Pick A or B based on what fits the existing pipeline. Document the
choice in this task file's "Notes" section.

### Sub-2: Audit and migrate consumers

`LCpeak` flows to:
- `Recording.peakLevel` — written at recording-stop time.
- CSV export column headers.
- PDF report fields.
- Watch envelope (`WatchAppState` reserved future use).
- Live widgets reading `live.levels["LCpeak"]`.

After the fix, the value changes for any non-quiet recording. Audit
every consumer to ensure none is implicitly expecting the old
broadband-with-offset semantics. In particular:
- The watch `singleValue` widget reading LCpeak (M9 task-7 noted
  the "loudness reads LAF regardless of metric" bug class — verify
  this metric in particular is not affected).
- `RecordingDetailView`'s peak-level display.

### Sub-3: Document the boundary

Pre-fix recordings have `peakLevel` baked into metadata. Post-fix
recordings will use the new computation. Document in the handoff
report:
- Old recordings' `peakLevel` remains as recorded (no migration).
- A code comment in `Recording.swift` notes the semantic boundary
  by date.

## Acceptance

- [ ] `LCpeak` derives from the C-weighted spectrum (or a C-weighted
  time-domain filter), not from raw broadband samples.
- [ ] New unit test in `SpektoWatch2Tests/`: feed a low-frequency
  (e.g., 31.5 Hz) tone fixture — C-weighting attenuates by ~3 dB —
  and assert that LCpeak < broadband peak by approximately that
  margin.
- [ ] Audit results documented in this task file's "Notes" section.
- [ ] No regression on `AcousticMetricsCalculator` existing tests.
- [ ] iOS + watchOS builds green.

## Files

- `SpektoWatch2/AudioEngine.swift`
- `SpektoWatch2/Managers/AcousticMetricsCalculator.swift`
- `SpektoWatch2/Processing/FrequencyWeightingProcessor.swift`
  (possibly — if a new time-domain C filter is needed)
- `SpektoWatch2/Models/Recording.swift` (semantic-boundary comment)
- New tests in `SpektoWatch2Tests/LCpeakComputationTests.swift`

## Verification

- iOS + watchOS builds green.
- New low-frequency tone fixture test passes.
- Hardware acceptance (documented): play a calibrated 1 kHz tone
  and a 31.5 Hz tone of equal RMS — LCpeak readings differ by
  ~3 dB (matching the IEC C-weighting curve), where before they
  were nearly identical.

## Notes

### Approach chosen: A — frequency-domain C-weighted peak detector

`AudioEngine.processFFTFrame` now:
1. Fetches `cGains = localWeightingProcessor.getWeightingGains(for: .c)` (amplitude-domain
   linear factors, precomputed at init time — no per-frame allocation).
2. Multiplies per-bin FFT amplitudes by C-gains into `lcPeakScratch` via `vDSP_vmul`.
3. Finds the maximum with `vDSP_maxv`.
4. Converts: `20·log10(cPeakLinear + ε) + calibrationOffset` → dB SPL.
5. Passes the result as `peakLevel` to `metricsCalculator.updateMetrics`.

Approach A was chosen over Approach B (time-domain biquad cascade) because:
- The C-weighting gain tables are already precomputed in `FrequencyWeightingProcessor`.
- No additional filter state or per-frame filter pass is needed.
- Avoids any additional heap allocation on the audio render thread.
- The result is consistent with the FFT frame used for all other acoustic metrics.

`lcPeakScratch` is resized lazily alongside `fftEnergyScratch` (both guarded by the
`energyCount != count` check). Note: this lazy allocation shares the same AE-7 concern
flagged in the 2026-05-24 code review; pre-allocation in `applyFFTConfiguration` is
deferred to M15 task-8.

### Consumer audit

| Consumer | File | Action |
|----------|------|--------|
| `metricsCalculator.updateMetrics(peakLevel:)` | `AudioEngine.swift` | **Fixed** — now receives C-weighted LCpeak |
| `self.currentPeakLevel` in `updateUI` | `AudioEngine.swift` | **Fixed** — now reads `spectrogramData.levels["LCpeak"]` (falls back to raw peak) |
| `recording.peakLevel = data.levels["LCpeak"]` in `ControlBarView` | `ControlBarView.swift` | No change needed — already reads from the live metrics dict |
| `recording.peakLevel` display in `RecordingDetailView` | `RecordingDetailView.swift` | No change — shows stored value; semantic boundary documented in `Recording.swift` |
| PDF summary table `"LCpeak": recording.peakLevel` | `PDFReportGenerator.swift` | No change — uses stored `Recording.peakLevel`, which is now the correct LCpeak. Note: `"LAFmax"` also falls back to `recording.peakLevel` for recordings without a measurement reader (pre-existing issue, not introduced here; tracked in backlog). |
| `SingleValueWidget` `case "LCpeak"` | `SingleValueWidget.swift` | No change — reads live `levels["LCpeak"]`, now correct |
| Widget settings picker `"LCpeak"` | `WidgetSettingsView.swift` | No change — metric key is unchanged |
| `PresetCompositions.swift` `"LCpeak"` metric | `PresetCompositions.swift` | No change — metric key is unchanged |
| Demo data `peakLevel: sample.peak` | `SpektoWatch2App.swift` | No change — static fixture, not live audio |

### Semantic boundary in `Recording.peakLevel`

Documented in `Recording.swift` via a doc-comment on the property: recordings stopped
before 2026-05-24 store the raw broadband sample peak; recordings stopped on/after this
date store the IEC 61672 C-weighted frequency-domain peak. No migration is performed.

## Out of scope

- LZpeak / LApeak (already correctly weighted).
- Changing the recording metadata format.
- Migrating old recordings' `peakLevel` values.
