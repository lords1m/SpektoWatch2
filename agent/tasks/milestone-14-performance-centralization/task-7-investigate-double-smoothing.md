# Task 7: Investigate double smoothing (R10)

Status: pending
Created: 2026-05-21
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

- Decision documented (A, B, or C) in the task file with the
  hardware trace.
- If decision A: code change lands as part of this task.
- iOS build green (regardless of outcome).
