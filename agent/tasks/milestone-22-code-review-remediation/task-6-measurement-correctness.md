# Task 6: Measurement Correctness

Status: code_complete (pending macOS build + simulator tests)
Created: 2026-11-24
Milestone: `milestone-22-code-review-remediation`
Owns: MC-1 … MC-11
Decision: **Q2** (versioning of changed metrics)

## Goal

Reported LAF/LAS, LAeq, LCpeak, band levels and loudness are independent of
display settings (window, FFT size, hop, smoothing) within ±0.5 dB for
stationary signals, and follow IEC 61672-1 time-weighting semantics.

## Steps

0. **Reference harness first.** Add `MeasurementReferenceTests` with
   synthetic signals (1 kHz sine at 94 dB, pink noise, 10 ms tone burst,
   impulse) run through `ProcessingPipeline` + `AcousticMetricsCalculator`
   for every window × FFT size × hop combo. Capture current (wrong) values to
   document the deltas, then make the tests assert the correct targets.
1. **MC-1 — hop > FFT.** `SampleRingBuffer` tracks samples actually advanced;
   carry the unconsumed remainder of the hop to the next read; compute
   `dt = advancedSamples / fs` per frame.
2. **MC-2 — window normalisation.** Divide power by `Σw²/N` (ENBW) for level
   and band energies; keep coherent-gain scaling only for display magnitude.
   Precompute per window in `FFTProcessor`.
3. **MC-5 + MC-3 — time-domain broadband path.** Add biquad A- and C-weighting
   IIR filters (bilinear-transformed IEC 61672 poles, per sample rate) applied
   to each tap block. Compute broadband energy per block and run exponential
   Fast/Slow (125 ms / 1 s) per sample-block → LAF/LAS/LAeq. LCpeak =
   `max|c-weighted sample|`. FFT path remains for spectra/bands only. Cost:
   two biquad cascades per sample via `vDSP_biquad` — RT-safe.
4. **MC-4 — band Leq.** Integrate unsmoothed band energy: `E += e·dt`,
   `Leq = 10·log10(E/T)`; any display smoothing happens in power domain and
   only for display. Write the integrated values to `.spekto`.
5. **MC-6 — loudness.** Feed Z-weighted (or band-wise) levels into the ISO 226 /
   ISO 532 path; extrapolate above the table along the last slope.
6. **MC-7 — watch.** Use `tapFormat.sampleRate`; process every hop in each
   buffer; `dt` from processed frames. Reuse the shared IIR path from step 3
   (Shared/), so phone and watch compute identically.
7. **MC-8 — trigger capture.** Pass the real frame rate into
   `TriggerSpectrumAccumulator`/`SpectralNoveltyDetector`; capture ends at the
   current `writeHead` and completes after `postFrames` new frames arrive.
8. **MC-9.** Convert SPL to dBFS with the calibration offset before the clamp.
9. **MC-10.** `bw = 2/ln2 · asinh(1/(2Q))`; loop `min(bands.count,3)..<3`.
10. **MC-11.** `LAFGraphView` rebuilds its buffer on sample-rate change; store
    samples in a non-published ring and publish one tick per frame.
11. **Q2 versioning.** Bump a `metricsVersion` field in `.spekto` metadata /
    `Recording`; detail view and PDF show "Legacy-Berechnung" for older files.

## Acceptance

- Reference tests: sine 94 dB → LAF 94.0 ± 0.2 for all window/hop combos;
  pink noise band sum = broadband ± 0.5 dB; 10 ms burst LAFmax matches
  IEC 61672 tone-burst table ± 0.5 dB; LCpeak of impulse ≥ LCF.
- Watch vs phone parity ± 1.0 dB on hardware (task-8, extends M21 task-6).
- `PERFORMANCE_BUDGET.md` RT budget still met with IIR path.
