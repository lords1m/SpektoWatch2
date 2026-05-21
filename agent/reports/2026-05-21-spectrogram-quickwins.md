# Spectrogram & Level-History Quick-Wins — 2026-05-21

Branch: working tree (uncommitted)
Driver: visual regression flagged by comparing
  - `~/Downloads/reference.mp4` (reference app)
  - `~/Downloads/RocketSim_Recording_iPhone_12_mini_5.4_2026-05-21_11.08.36.mp4` (this build)
  side by side. Frames extracted via `swift /tmp/extract-frames.swift`.

Out of scope for an ACP milestone per user decision; this report exists so
the two code changes are traceable later.

## Problems observed

1. **Spectrogram banding**: visible horizontal lines between frequency bins,
   especially at low frequencies on the log axis. Reference app shows a
   continuous gradient in the same band.
2. **Time-axis desync**: with a spectrogram widget and a Pegelverlauf
   (level-history) widget stacked, the two time axes drift relative to
   each other under load.

## Root causes

### Banding

`HighEndSpectrogramAdapter.precomputeMapping` (lines 246–272) maps each
log-frequency display pixel to an FFT bin. When `binWidth < 1.0` — i.e.
multiple display pixels map to one FFT bin, which happens for every low
frequency on the log axis — the code does **linear** interpolation
between `magnitudes[index0]` and `magnitudes[index1]`. The `fraction` is
tiny for adjacent pixels inside the same bin pair, so several rows show
nearly identical values. The transition to the next bin pair appears as
a horizontal plateau edge.

### Time-axis desync

Spectrogram and level history derive their time bases differently:

- `HighEndSpectrogramAdapter.updateWithFFTMagnitudes` uses
  `columnAdvanceAccumulator += dt / secondsPerColumn`; under load it
  writes interpolated extra columns to keep wall-clock time consistent.
- `LAFGraphView.updateLevelBuffer` was one-update-equals-one-slot,
  regardless of `dt`. Under load (dropped FFT callbacks), the buffer
  filled slower than the axis claims.

## Fixes landed (this session)

### Fix #1 — `SpektoWatch2/HighEndSpectrogramAdapter.swift`

`applyFrequencySmoothingIfNeeded` now has an always-on baseline strength
`0.25` in addition to the user-controlled slider. `effectiveStrength`
ends up ~0.06, applied via the existing 3-tap Gaussian kernel. The
user slider continues to add smoothing on top.

Cosmetic mitigation — hides the symptom, does not fix the underlying
linear-interpolation problem. The proper fix would be cubic interpolation
or zero-padded FFT; both deferred per user choice.

### Fix #2 — `SpektoWatch2/LAFGraphView.swift`

`updateLevelBuffer(level:)` rewritten to be wall-clock-driven, mirroring
the spectrogram's `columnsToWrite` path:

- Computes `slotsToWrite = round(dt × expectedUpdateRate)`,
  clamped to `[1, buffer.count]`.
- For `slotsToWrite > 1`, writes interpolated values between
  `lastBufferedLevel` and the new value across the missing slots, so
  the buffer fills wall-clock time even if FFT callbacks were dropped.
- New `@State` properties: `lastUpdateTimestamp`, `lastBufferedLevel`.
  Both reset in `resetBuffer()`.

## Not done

- Cubic / zero-pad bin interpolation (the real fix for the banding
  symptom).
- Shared `AudioEngine.currentTime` clock provider — both widgets still
  derive timing locally; they just now happen to use the same logic, so
  they stay in sync under the same load conditions. A truly shared
  clock would survive more pathological cases.
- Hardware verification — local simulator is broken (AGENT.md). User
  to confirm on device.

## Files changed

- `SpektoWatch2/HighEndSpectrogramAdapter.swift` (smoothing baseline)
- `SpektoWatch2/LAFGraphView.swift` (wall-clock advance)

## Note on co-touched files in `git status`

`HighEndSpectrogramAdapter.swift` also carries an unrelated user-side
edit (rename of `rpd` → `renderPassDescriptor` in `draw`). Respected
per AGENT.md rule against overwriting unrelated user work; not part of
this report's scope.
