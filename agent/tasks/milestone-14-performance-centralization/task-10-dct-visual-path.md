# Task 10: DCT visual path, FFT measurement path

Status: completed
Created: 2026-05-22
Completed: 2026-05-22
Milestone: `milestone-14-performance-centralization`
Source: user request after Apple Accelerate spectrogram comparison

## Goal

Use DCT only for visual spectrogram-style surfaces while preserving
FFT as the measurement source of truth.

This separates the two jobs:

- **Measurement path:** FFT stays authoritative for SPL levels,
  A/C/Z weighting, third-octave and octave bands, recorded
  measurement metadata, and acoustic metrics.
- **Visual path:** DCT-II feeds live spectrogram, waterfall,
  watch spectrogram previews, recording-detail visual playback, and
  PNG spectrogram export.

## Why

The Apple Accelerate spectrogram sample emphasized a compact
Accelerate-based visual pipeline. For this app, the important
constraint is not to trade measurement correctness for visual
smoothness. The app now computes visual-only DCT payloads in parallel
with the existing FFT payloads, so visual rendering can change without
affecting measurement semantics.

## Implementation landed

- `Shared/SpectrogramData.swift`
  - Added optional `visualFrequencies` and `visualMagnitudes`.
  - Extended binary serialization with trailing visual arrays while
    keeping old v1 decoders compatible.
- `SpektoWatch2/SpectrogramProcessor.swift`
  - Added `VisualSpectrogramProcessor` backed by `vDSP.DCT(type: .II)`.
  - Uses the same window choice as the FFT path and emits dB-scaled
    visual bins.
- `SpektoWatch2/AudioEngine.swift`
  - Computes FFT measurement magnitudes as before.
  - Computes DCT visual magnitudes in parallel on the same sample
    window.
  - Sends visual DCT fields to the watch when available.
- `SpektoWatch2/HighEndSpectrogramAdapter.swift`
  - Live spectrogram prefers `visualMagnitudes`, with FFT fallback for
    legacy payloads.
- `SpektoWatch2/WaterfallView.swift`
  - Waterfall appends visual DCT frames when present.
- `SpektoWatch2/SpectrogramImageRenderer.swift`
  - PNG spectrogram export renders via DCT-II.
- `SpektoWatch2/Views/RecordingDetailView.swift`
  - Recording-detail visual playback recomputes DCT history from the
    audio file, while metric playback stays backed by stored
    measurement data.
- `SpektoWatch Watch App/WatchAudioEngine.swift`
  - Watch local processing computes DCT visual magnitudes alongside its
    FFT path.
- `SpektoWatch Watch App/WatchSpectrogramView.swift`,
  `WatchModularFace.swift`, and
  `WatchWidgets/WatchSpectrogramWidget.swift`
  - Watch visual surfaces prefer DCT visual payloads.
- `SPECTROGRAM_REFERENCE.md`
  - Updated architecture documentation to describe the split
    FFT-measurement / DCT-visual pipeline.

## Acceptance

- [x] FFT remains the only source used for measurement semantics.
- [x] Visual spectrogram, waterfall, watch spectrogram, recording
  detail, and image export use DCT when visual payloads are available.
- [x] Legacy payload compatibility remains: readers can fall back to
  FFT magnitudes when `visualMagnitudes` is absent.
- [x] Tests cover DCT visual-bin generation and visual payload
  serialization.

## Verification

Focused Xcode test run completed on 2026-05-22:

- `FFTProcessorTests`
- `SpectrogramImageExporterTests`
- `WatchProtocolVersioningTests`
- `WatchConnectivityTests`

Result: 56 tests, 0 failures.

## Follow-ups

- Visual A/C weighting is intentionally not added yet. Measurement
  weighting still belongs to FFT. If visual weighted spectrograms are
  needed, add explicit `visualMagnitudesA/C` fields rather than
  reusing measurement arrays.
- The adapter method name `updateWithFFTMagnitudes` is now semantically
  stale for visual payloads, but renaming it would ripple through many
  tests and was not needed for this change.
- Watch local DCT path (`WatchAudioEngine.performVisualDCT`) still
  emits raw linear DCT bins, not the Apple-sample mel pipeline.
  Companion-mode bins arrive mel-binned from iOS, so the two watch
  modes now show slightly different spacing. Resolve by either
  (a) moving `MelSpectrogramProcessor` into `Shared/` and reusing it
  on the watch, or (b) duplicating a smaller mel filter (e.g. 64
  bands) inline in `WatchAudioEngine`.

## Apple-sample mel pipeline (2026-05-23 extension)

Implemented the full pipeline from
<https://developer.apple.com/documentation/accelerate/visualizing-sound-as-an-audio-spectrogram>:
Hann → DCT-II → |.| → 2/N scale → mel filter bank → 20·log10 → +offset.

- `VisualSpectrogramProcessor` now owns a `MelSpectrogramProcessor`
  and emits 128 mel-band magnitudes by default (configurable;
  `melBandCount = 0` reverts to legacy linear DCT for debug/tests).
- `visualFrequencies` carries mel band centers in Hz.
- `HighEndSpectrogramAdapter.updateWithFFTMagnitudes` accepts an
  optional `inputFrequencies:` array; when present, the mapping cache
  is built off those frequencies instead of the linear-from-Nyquist
  assumption. Eliminates the previous double log-mapping when mel
  bins were fed in.
- Cache invalidation keys off frequency-axis hash + sample rate
  changes.
- Tests:
  `testVisualSpectrogramProcessorProducesMelBands`,
  `testVisualSpectrogramProcessorReconfigureRebuildsMelBank`,
  and a renamed `testVisualSpectrogramProcessorProducesLegacyDCTBins`
  for mel-off coverage.
- `SPECTROGRAM_REFERENCE.md` describes the new 6-step pipeline.
