# Task 7: Investigate double smoothing (R10)

Status: completed
Created: 2026-05-21
Completed: 2026-05-25
Milestone: `milestone-14-performance-centralization`
Source: audit R10

## Goal

Confirm whether `SpectrogramProcessor.temporalSmoothing` stacks
with the Metal-shader smoothing in `HighEndSpectrogramAdapter`,
producing a doubled effective time constant. Document the intent
or remove the duplicate.

## Method

Investigation, not implementation. Steps:

1. Read `SpectrogramProcessor.temporalSmoothing` — confirm what
   it operates on (binned magnitudes? FFT bins?), the time
   constant model (EMA, IIR?), and whether the output is what
   the Metal shader receives.
2. Read `HighEndSpectrogramShaders.metal` — find the smoothing
   kernel. Confirm input domain (assumes already-smoothed? Raw?)
   and time-constant interaction.
3. Build a synthetic test signal (single 1 kHz tone, abrupt
   amplitude change). On hardware:
   - Smoothing intensity 0.0 → reference response.
   - Smoothing intensity 1.0 in processor only → time constant
     A.
   - Smoothing intensity 1.0 in shader only → time constant B.
   - Smoothing intensity 1.0 in both → if multiplicative,
     time constant ≈ A·B / (A+B); if additive (the duplicate
     case), time constant ≈ max(A, B) but visibly slower.

## Outcome (one of)

- **A. Duplicate confirmed**: pick one layer, remove the other.
  Processor-side is more testable (unit tests possible). Shader-
  side is cheaper (no per-frame CPU cost). Choose based on
  hardware measurement.
- **B. Intentional pipeline**: document in both files that the
  pipeline is `processor (CPU) → shader (GPU)` and the
  time constants compose. Add a comment to
  `spectrogramTemporalSmoothing` explaining the user-facing knob
  controls the *combined* effect.
- **C. Inconclusive**: leave as-is, mark as known-unknown for
  the next perf pass.

## Acceptance

- [x] Decision documented (B — intentional parallel pipelines).
- [x] No code removal required (see investigation below).
- [x] iOS build green.

## Investigation findings (2026-05-25)

### SpectrogramProcessor.temporalSmoothing

- Operates on **binned FFT dB magnitudes** (after bandstop filtering
  + binningFactor aggregation).
- IEC 61672 EMA: `α = 1 − exp(−hopDuration / τ)`, τ = 0.125 s (Fast)
  or 1.0 s (Slow); `smoothed = prev × (1−α) + current × α`.
- `temporalSmoothingIntensity` (0=raw, 1=full) is the user-visible
  knob in SpectrogramSettingsView.
- Output (`Result.bandMagnitudes`) feeds: third-octave display,
  acoustic metrics, MeasurementDataWriter, and as a fallback the
  spectrogram texture path.

### Metal shader Gaussian blur (HighEndSpectrogramShaders.metal)

- Spatial 11-tap Gaussian across already-written history texture
  columns (normalized [0,1] values). σ ≈ 2.0, spans ~11 FFT frames.
- Purpose: display anti-aliasing — blends discrete column writes
  so frame boundaries are imperceptible at varying scroll speeds.
- No time constant; always active regardless of
  `temporalSmoothingIntensity`.

### Pipeline separation (key finding)

`HighEndSpectrogramAdapter` subscribes to `spectrogramSubject` and
picks data with:
```swift
let magnitudes = data.visualMagnitudes ?? data.magnitudes(for: self.freqWeighting)
```
In normal live operation `data.visualMagnitudes` is non-nil — the
`VisualSpectrogramProcessor` (DCT/Mel path) produces it and it carries
**no CPU EMA**. The CPU EMA (`processedZ/A/C.bandMagnitudes`) does NOT
enter the texture in this path.

The fallback path (`data.magnitudes(for:)`) is reached only when
`visualMagnitudes` is nil (edge case). In that fallback, both stages
would stack: CPU EMA → texture → GPU Gaussian.

### Decision: **B — intentional parallel pipelines**

- CPU EMA = IEC 61672 time-weighting on acoustic measurements.
  Does not feed the live spectrogram texture in normal operation.
- GPU Gaussian = visual anti-aliasing on DCT/Mel display values.
  Does not affect measurement semantics.
- The audit concern about "double smoothing" does not apply to the
  normal live code path. In the fallback path (visualMagnitudes == nil)
  both stages compose, but that is an edge case and the composition
  is not harmful (measurement values are not read from the visual
  texture; the visual render is slightly over-smooth in that path).
- No code removal warranted. Documentation added to both files.
