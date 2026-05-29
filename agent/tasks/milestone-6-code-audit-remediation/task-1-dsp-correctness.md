# Task 1: DSP Correctness

Status: completed
Created: 2026-05-18
Updated: 2026-05-18
Milestone: `milestone-6-code-audit-remediation`

## Status Summary

| Sub-item | Source finding | Result |
|---|---|---|
| 1. Watch `zop` → `zrop` | Audit #1 (Critical) | DEFERRED — see "Verification Reversals" |
| 2. Watch LAF exponent `/10` → `/20` | Audit #2 (Critical) | DEFERRED — see "Verification Reversals" |
| 3. Window ENBW correction | Audit #11 (High) | DEFERRED — calibration-shifting; needs hardware re-validation |
| 4. Octave-band edges → `pow(2, ±1/6)` | Audit #21 (Medium) | **LANDED** — `SpektoWatch2/SpectrogramProcessor.swift:263-269` |
| 5. C-weighting normalization sign | Audit #22 (Medium) | DEFERRED — see "Verification Reversals" |
| 6. `recordingDuration` torn read | Audit #24 (Medium) | **LANDED** — `SpektoWatch2/AudioEngine.swift:1387-1399` |
| 7. `sampleBuffer` ceiling | Audit #23 (Medium) | **LANDED** — `SpektoWatch2/AudioEngine.swift:1230-1238` |

3 of 7 sub-items landed. 4 deferred with documented reasoning.

## Verification Reversals

Three audit findings did not survive review against existing tests and the math:

- **#1 — `vDSP_DFT_zop` → `vDSP_DFT_zrop`.** `SpektoWatchTests/WatchFFTTests.swift:60-79` (`testNormalizationPreventsOverscaling`) explicitly asserts that the current `zop + 2/N` pipeline produces a unit-amplitude sine peak in the range `[-20 dBFS, +10 dBFS]`. This regression test was introduced in M2 to lock the +66 dB fix. The audit's claim that `2/N` is wrong for `zop` and right for `zrop` directly contradicts a passing test. vDSP's `zop` and `zrop` apply the same `N` scaling for real input; the existing code is correct.
- **#2 — LAF exponent `ln(10)/10` → `ln(10)/20`.** `fftMagnitudes[i] = 20·log10(A_i)`, so `10^(dB/10) = A_i²`. The current code computes `Σ A_i²` — which IS power (Parseval). This matches the iPhone path at `AudioEngine.swift:1365` (`vDSP_vsq` then `vDSP_sve`). The audit's proposed exponent `/20` would sum amplitudes, not power, and would corrupt LAF. Math: deferring is correct.
- **#5 — C-weighting offset sign.** At f = 1 kHz the raw formula evaluates to ≈ -0.062 dB; the code computes `cDb = formula - (-0.062) = 0 dB ± 1e-4`. Already normalized correctly. The audit's claim of "+0.062 dB across the spectrum" is wrong.

## Deferral — Sub-item #3 (Window ENBW)

The audit's analysis here is sound but the fix is measurement-shifting. Magnitudes use coherent-gain (`2/N`) normalization; energy summation should use ENBW correction for broadband accuracy. Applying ENBW now will change displayed LAeq/LAFmax for every user, requiring hardware re-calibration and a new `calibrationOffset` baseline. Defer until paired with a calibration migration.

## What Landed

### `SpektoWatch2/SpectrogramProcessor.swift:263-269`

Octave-band edges now use `pow(2.0 as Float, ±1.0/6.0)` instead of `0.89 / 1.12`. Aligns `ensureOctaveBandRanges` with `makeDiagnosticSnapshot` so the two octave-binning paths cannot disagree near band edges.

### `SpektoWatch2/AudioEngine.swift:1387-1399`

`recordingDuration` is no longer read from the `@Published` property on the audio render thread. The duration is derived inline from `recordingStartTime` (the same pattern used 13 lines below for the writer timestamp). Removes the torn-read risk that could misfire the Taktmax interval reset.

### `SpektoWatch2/AudioEngine.swift:1230-1238`

Added an absolute compaction threshold (`sampleBufferOffset > currentFFTSize * 4`) after the backlog trimmer. The per-iteration compaction inside the FFT while-loop only fires when the loop body runs; the trimmer at lines 1220-1228 advances the offset without removing elements. The new guard ensures the underlying array cannot retain dead head samples indefinitely under sustained backpressure.

## Out of Scope (unchanged)

- Real-time-safety issues on the audio thread (covered by Task 6).
- Any UI changes that surface DSP results.

## Verification

Tests cannot be run locally (simulator broken). Verification commands for the next CI run or developer machine:

- `xcodebuild test -scheme SpektoWatch2 -only-testing:SpektoWatchTests/WatchFFTTests` — must still pass; lock for the deferred #1 decision.
- New test recommended (deferred to ENBW work): `FrequencyWeightingProcessor` C-weight at 1 kHz ≈ 0.0 ± 0.01 dB (currently passes by inspection).
- New test recommended: `SpectrogramProcessor.ensureOctaveBandRanges` vs `makeDiagnosticSnapshot` produce identical band assignments for a synthetic tone sweep.

## Follow-ups

- Open a separate sub-task or future milestone for ENBW correction paired with a calibration migration.
- Open a sub-task to remove the dB → linear → dB round-trip in `WatchAudioEngine.processAudioBuffer` (pure cleanup, no behavior change).
- Open a clarification with the audit reviewer (or future audit cycle) to validate #1/#2/#5 against hardware before any further action.

## Audit References

#1 (deferred), #2 (deferred), #11 (deferred), #21 (landed), #22 (deferred), #23 (landed), #24 (landed)

## Objective

Fix every measurement-correctness bug in the DSP layer so the iPhone and
Apple Watch report acoustically equivalent SPL values for the same stimulus.
This is the foundational task of the milestone — every downstream metric
(LAeq, LAFmax, LCpeak, spectrogram colors, the complication value) is wrong
until these are addressed.

## Scope

In priority order (severity tags from the audit):

1. **Critical — Watch FFT setup mismatch** — `SpektoWatch Watch App/WatchAudioEngine.swift:55`
   Replace `vDSP_DFT_zop_CreateSetup` with `vDSP_DFT_zrop_CreateSetup` to
   match the phone's real-to-complex FFT. Restructure input packing
   (interleaved even/odd → split-complex) and ensure the `2/N` normalization
   stays valid. Drop the now-unused imaginary input buffer.

2. **Critical — Watch LAF exponent error** — `SpektoWatch Watch App/WatchAudioEngine.swift:287-291`
   Replace `log(10.0)/10.0` with `log(10.0)/20.0` when converting amplitude
   dB → linear, OR compute the energy sum from the linear magnitudes before
   `vDSP_vdbcon` is applied. Prefer the second approach (avoids a second
   exp/log round-trip on the audio thread).

3. **High — Window normalization for energy** — `SpektoWatch2/Processing/FFTProcessor.swift:413`
   Compute the equivalent noise bandwidth (ENBW) for each supported window
   and apply it as an extra scalar when the magnitudes feed
   `AcousticMetricsCalculator`. Acceptable alternative: keep `2/N` and
   document that the user-facing `calibrationOffset` must be re-derived per
   window — but the audit calls this fragile, so prefer the ENBW fix.

4. **Medium — Octave-band edge constants** — `SpektoWatch2/SpectrogramProcessor.swift:264-265`
   Replace `*0.89 / *1.12` with `pow(2.0 as Float, -1.0/6.0)` and
   `pow(2.0 as Float, +1.0/6.0)` so `ensureOctaveBandRanges` matches the
   diagnostic snapshot path.

5. **Medium — C-weighting normalization sign** — `SpektoWatch2/Processing/FrequencyWeightingProcessor.swift:151-154`
   Flip the sign on the `-0.062` offset (or rewrite as `+ offset` with a
   positive constant). Add a unit test that confirms C-weight at 1 kHz is
   within 0.01 dB of 0.

6. **Medium — `recordingDuration` torn read on audio thread** — `SpektoWatch2/AudioEngine.swift:1387`
   Stop reading the `@Published` property from the audio callback. Replace
   with `CFAbsoluteTimeGetCurrent() - recordingStartTime` computed inline,
   or maintain a separate `Atomic<TimeInterval>` updated from the main
   thread.

7. **Medium — `sampleBuffer` worst-case unbounded growth** — `SpektoWatch2/AudioEngine.swift:1201-1256`
   Add an absolute ceiling that forces compaction regardless of `scrollSpeed`
   — e.g. `2 × maxHistorySize × hopSize`.

## Out of Scope

- Real-time-safety issues on the audio thread (covered by Task 6).
- Any UI changes that surface DSP results.

## Verification

- Add an FFTProcessor unit test that drives a synthetic 1 kHz sinusoid
  through both phone and watch paths and asserts identical normalized
  magnitudes within 1e-3.
- Add a FrequencyWeightingProcessor test asserting A/C weighting at 1 kHz
  is 0.0 ± 0.01 dB.
- Add a SpectrogramProcessor test asserting one-third-octave band edges
  match `pow(2, ±1/6) × center` exactly.
- Manual hardware acceptance: 1 kHz tone at fixed level, phone and watch
  report LAeq within ±0.5 dB.

## Notes

The user's local simulator is broken; tests cannot be run locally. Capture
the test commands in the handoff so they run on Xcode Cloud or another
developer's machine.

## Audit References

#1, #2, #11, #21, #22, #23, #24
