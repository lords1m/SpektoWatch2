# Task 3: Watch DSP Calibration Parity with iOS

Status: completed
Created: 2026-05-23
Completed: 2026-05-24

## Outcome

All three sub-items landed 2026-05-24.

- Sub-1 (FFT variant): `WatchAudioEngine.performFFT` migrated from
  `vDSP_DFT_zop_CreateSetup` (full complex DFT) to
  `vDSP_DFT_zrop_CreateSetup` (real-optimized half-spectrum). The
  `2/N` normalization that was previously paired with the wrong
  variant is now correctly paired with `zrop`. New properties
  `windowedSamples` (N), `splitRealIn` / `splitImagIn` (N/2 each),
  with `vDSP_ctoz` deinterleaving the windowed real signal into
  split-complex form — identical pattern to
  `Processing/FFTProcessor.swift`. Buffers shrank from 4×N to
  4×(N/2) plus the N-length windowed-samples scratch.
- Sub-2 (DCT log convention): `performVisualDCT` replaced
  `vDSP_vdbcon(..., 1)` with the explicit `vDSP_vclip` +
  `vvlog10f` + `vDSP_vsmul × 20` sequence — same code shape as
  iOS `FFTProcessor.convertToDB`. Reads as amplitude-domain
  20·log10 without flag ambiguity.
- Sub-3 (parity test): new
  `SpektoWatch2Tests/WatchDSPParityTests.swift` (~165 LOC, 3
  XCTest cases). The watch path can't be imported into the iOS
  test target so the test reproduces the post-fix watch pipeline
  inline and asserts: (a) iOS vs reproduction agree at 1 kHz
  within 0.5 dB, (b) the old `zop+2/N` combination is at least
  3 dB hotter (guard against regression to the pre-fix variant),
  (c) `20·log10 == 2 × 10·log10` for representative DCT
  coefficients (guard for the log convention).

## Hardware acceptance pending

- Side-by-side reference 1 kHz tone on iPhone + Apple Watch with
  paired calibration; `LAF` values agree within ±0.5 dB.
- Heads-up for the handoff report: existing watch-only stored
  recordings will read ~12 dB louder after this change. No
  migration is warranted (values were never reference-calibrated).


Milestone: `milestone-15-critical-stability-correctness`
Source: 2026-05-23 code review — DSP H2, H3

## Goal

Bring the watch's FFT measurement path and DCT visual path into
calibration agreement with the iOS pipeline. Today the watch reads
~12 dB below iOS for the same physical input — two compounding
bugs of 6 dB each. After this task, identical 1 kHz tones on both
devices read within ±0.5 dB of each other.

## Scope

### Sub-1: Watch FFT variant (DSP H2, **High**)

`WatchAudioEngine.performFFT` (line ~78) uses
`vDSP_DFT_zop_CreateSetup` (full complex DFT, length N). It feeds
real samples into `realIn` with zeros in `imagIn`, takes the first
`N/2` magnitudes, and normalizes by `2/N` (line ~399). That `2/N`
normalization is the convention for `vDSP_DFT_zrop` (real-optimized,
half-spectrum length N/2) — applying it to the full complex output
overstates bin amplitudes by ~6 dB.

The iOS `FFTProcessor` correctly uses `vDSP_DFT_zrop_CreateSetup`.

**Fix:** migrate the watch to `vDSP_DFT_zrop_CreateSetup`. Remove
the `imagIn` buffer (real-optimized variant doesn't need it). The
inspected bins are 0…N/2 already; normalization stays `2/N`. Match
the exact pattern in `Processing/FFTProcessor.swift` for consistency.

### Sub-2: Watch DCT log convention (DSP H3, **High**)

`WatchAudioEngine.performVisualDCT` (line ~446) calls
`vDSP_vdbcon(..., 1)` on the DCT-II coefficient magnitudes. The
`1` flag is the **power** convention (10·log10). DCT-II coefficients
are amplitude-domain values, so the correct conversion is 20·log10
(flag `0`). The iOS `VisualSpectrogramProcessor` does the explicit
`vvlog10f` + `×20` sequence and gets it right.

**Fix:** either pass flag `0` to `vDSP_vdbcon`, or replicate the
iOS sequence (`vvlog10f` + `vDSP_vsmul × 20`) for code-shape
parity with the iOS path. Recommended: the explicit sequence —
it's harder to misread later.

### Sub-3: Cross-platform parity test

Add a unit test that drives both `FFTProcessor` and the watch's
processing into agreement. Mock the watch's DFT setup creation in
test scope (or extract a shared helper) so the watch path can be
exercised from the iOS test target.

If the watch processing can't be exercised from the iOS target due
to target membership, add a deterministic fixture (1 kHz sine,
known amplitude) and assert the expected SPL value at the relevant
bin in both code paths against the same reference, even if run in
separate test targets.

## Acceptance

- [ ] `WatchAudioEngine` uses `vDSP_DFT_zrop_CreateSetup`. Code
  grep confirms zero remaining `vDSP_DFT_zop_CreateSetup` calls in
  the watch app target.
- [ ] `performVisualDCT` uses 20·log10 (either `vDSP_vdbcon` flag
  `0` or the explicit `vvlog10f` + 20 sequence).
- [ ] New `SpektoWatch2Tests/WatchDSPParityTests.swift` (or extension
  of `WatchProtocolVersioningTests`) feeds a 1 kHz tone fixture
  through both paths and asserts agreement within 0.5 dB.
- [ ] iOS + watchOS builds green.
- [ ] Hardware acceptance (documented in handoff report): play a
  reference 1 kHz tone at known SPL on both devices simultaneously;
  recorded `LAF` values agree within ±0.5 dB.

## Files

- `SpektoWatch Watch App/WatchAudioEngine.swift`
- New: `SpektoWatch2Tests/WatchDSPParityTests.swift` (or extension
  to existing watch test file)

## Verification

- iOS + watchOS builds green.
- New parity test passes.
- Manual hardware: side-by-side reading agrees within ±0.5 dB.

## Out of scope

- Replacing the hand-rolled DCT path with `VisualSpectrogramProcessor`
  (deferred follow-up; would require moving the processor to `Shared/`
  and target-membership work).
- Mel filter bank on the watch — currently the watch visual path
  emits raw DCT bins; bringing it to mel parity is a separate effort
  noted in M14 task-10 follow-ups.

## Risk

Fixing the two bugs will shift every existing watch reading by
roughly 12 dB. Users with stored watch-only measurements (rare given
companion mode is default) will see a one-time level jump. Document
this in the handoff report; no stored-measurement migration is
warranted since the values were never calibrated to a reference in
the first place.
