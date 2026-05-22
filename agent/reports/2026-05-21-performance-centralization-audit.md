# SpektoWatch2 — Performance & Centralization Audit

Date: 2026-05-21
Branch: `redesign/liquid-glass`
Scope: trace every per-frame measurement number from raw audio to
display, identify any redundant or duplicated computation, and
recommend a path to "calculate centrally, render dumbly."

## TL;DR

The live audio path is **mostly already centralized**. After the
M12 spectrum band fix and M13 task-6 aggregator extraction, the
pipeline has a single FFT, one weighting application per *needed*
weighting, one acoustic-metrics call, one band aggregator. The
gaps are concentrated in three places:

1. **A second `AudioEngine` instance** runs during recording
   playback (RecordingDetailView's `vizAudioEngine`). Whole
   pipeline duplicated. **Highest-impact win.**
2. **Per-widget recompute inside `Canvas` closures** — band data,
   leq EMA, and loudness lookups recomputed on every redraw
   instead of once per audio frame.
3. **`LoudnessCalculator` instantiated per-widget** with its own
   `@StateObject`. Phon/sone interpolation tables are static —
   should be one cached calculator.

Net DSP cost reduction available without changing math: estimated
30-50% during recording playback, 5-15% during normal live
operation depending on widget mix.

## Pipeline map (live operation)

```
AVAudioEngine input buffer  (16384 samples / ~370 ms typical)
   │
   ▼  processAudioBuffer
peakLevel (scalar, vDSP_maxmgv)
   │
   ▼  processSamples → ring-buffer accumulate → processFFTFrame
fftLinearMagnitudesScratch       (one FFT per frame)
fftDBMagnitudesScratch           (vDSP log10)
   │
   ▼  + calibrationOffset via vDSP_vsadd                          ① cal applied
                                                                    once to mags
dbZ                                                                ▲
   │                                                               │
   ├──▶ FrequencyWeightingProcessor.applyWeighting(.a)  ┐
   │                                                    ├─ gated by
   ├──▶ FrequencyWeightingProcessor.applyWeighting(.c)  ┘ requiredSpectral
   ▼                                                        Weightings
SpectrogramProcessor.process(.z)                                   ② bandstop +
   │  (also for .a and .c if produced)                                octaves +
   │                                                                   binning +
   │                                                                   smoothing
   ▼
processed{Z,A,C}.bandMagnitudes / .bandFrequencies / .spectrum
   │
   ▼  computeDisplayThirdOctaveBands (Z/A/C)             ─→ SpectrumBand-
   │                                                       Aggregator
   ▼
displayOctaveBands{Z,A,C}                                          ③ third-octave
                                                                    SPL per
                                                                    weighting

   ┌──────────────────────────────────────────────────────────────┐
   │  Parallel: AcousticMetricsCalculator.updateMetrics(           │
   │    energyZ, energyA, energyC, peakLevel, dt, ...)             │
   │                                                                │
   │  Returns dict with: LAF, LAS, LCF, LCS, LZF, LZS,              │
   │  LAeq, LAFmin, LAFmax, LCpeak, LAF5, LAF95, LAFT5, LAFTeq      │
   └──────────────────────────────────────────────────────────────┘   ④ all broadband
                                                                       levels here
SpectrogramData(
   frequencies, magnitudes (Z), magnitudesA?, magnitudesC?,
   broadbandLevel, levels: [String: Float], sampleRate, timestamp
)
   │
   ├──▶ emitSpectrogramData(...) — Metal renderers (bypasses SwiftUI)
   │
   ├──▶ updateUI(...) — main-thread, writes to LiveAcousticState
   │
   ├──▶ MeasurementDataWriter.writeFrame(...) — recording path
   │
   └──▶ onBandsUpdated callback — MaskingEngine consumes Z bands
```

Numbered points are the "single source of truth" candidates. If
all consumers read from these, downstream is just rendering.

## What's already central — no action needed

- **Single FFT per frame**: `FFTProcessor.performFFT(into:)` writes
  into a pre-allocated scratch buffer; no per-frame allocations.
- **Weightings gated**: `requiredSpectralWeightingsForCurrentFrame()`
  returns the union of `{ .z, frequencyWeighting }`, recording
  needs (`{ .a, .c }`), and widget overrides. Z always; A/C only
  if a widget actually displays them or recording is on. Already
  cheap when nothing needs A/C.
- **Energy computation vectorised**: `vDSP_vsq` for magnitudes²,
  `vDSP_dotpr` against pre-computed `aWeightingGainsSq` /
  `cWeightingGainsSq` arrays. Cannot be cheaper.
- **AcousticMetricsCalculator** computes every broadband level
  (LAF/LAS/LCF/LCS/LZF/LZS/LAeq/LAFmin/LAFmax/LCpeak/LAF5/LAF95/
  LAFT5/LAFTeq) in one call. Returns a dict. Single source of
  truth for downstream `data.levels[...]` lookups.
- **Band aggregator centralised** (M13 task-6): both AudioEngine's
  pre-compute path and the widget's fallback route through
  `SpectrumBandAggregator.thirdOctaveBands` since M12 task-8 +
  M13 task-6.
- **Calibration**: applied exactly twice per frame — once as a
  `vDSP_vsadd` to magnitudes, once as a linear factor for
  energies. These are NOT duplicates; they're two coherent
  consumers of the same scalar.
- **Recording statistics**: written to disk frame-by-frame by
  `MeasurementDataWriter` using values pulled from `levels[...]`.
  No recomputation on the writer side.
- **PDF report + CSV export**: read `recording.laeqFast`,
  `.peakLevel`, etc. as stored fields. No recomputation.

## Redundancies found (graded)

### High impact

#### R1. Recording playback spins up a second AudioEngine

`SpektoWatch2/Views/RecordingDetailView.swift:21-24` constructs
`@StateObject vizAudioEngine = AudioEngine(...)` to visualize
playback. `AudioPlayerManager.onAudioSamples` (line 140-141) feeds
playback samples back through `vizAudioEngine.processExternalAudio`,
which runs the **full FFT + weighting + metrics + band
aggregation pipeline** for the second time. The main `AudioEngine`
is still alive in the background.

During recording playback the app holds **two** complete DSP
pipelines, each doing per-frame FFT + 1-3 weightings + 31 bands ×
3 + the full AcousticMetricsCalculator pass.

**Why it exists**: the detail view wants its own scrubbing
spectrogram + level history independent of live audio.

**Fix**: extract a `PlaybackAnalyzer` that reuses
`FFTProcessor` + `SpectrogramProcessor` + `SpectrumBandAggregator`
+ `AcousticMetricsCalculator` directly without owning a full
`AudioEngine`. The detail view consumes the analyzer's output and
the live engine stays paused (it already stops live mode when
playback runs). Result: one pipeline, ~50% DSP reduction during
playback.

#### R2. Per-widget `Canvas` recomputes band aggregation every redraw

`SpektoWatch2/AudioWidgets.swift:91-93, 188-189, 196-197` —
`SpectrumBandChartView`'s `Canvas` closure calls
`computeBandData(...)` on every Canvas redraw. Since the widget
observes the engine, every 15Hz audio publish triggers a Canvas
re-evaluation → new band aggregation pass.

For Third-octave mode: shortcut when `precomputedThirdOctave.count
== 31` (it always is) — just uses the precomputed array, cheap.

For Octave mode: derives octaves from precomputed thirds via
`fromThirds:` path. Cheap (10 power sums).

For Bark mode: **does its own per-bin aggregation** on every
redraw. The engine doesn't pre-compute Bark; the widget walks
the full spectrum array of ~1024 bins on every redraw to
aggregate into 24 bands.

**Fix**: either (a) memoize the aggregator output keyed by
`(mode, spectrum.count, last data timestamp)`, or (b) move Bark
aggregation upstream into AudioEngine so it's published like
third-octave. Bark is a fixed band layout; it's the same shape
of work as the existing third-octave precompute. Estimated
saving: ~0.5 ms per Spectrum widget per Bark redraw.

#### R3. Per-widget Leq EMA in `updateLeq`

`SpektoWatch2/AudioWidgets.swift:207-223` — for every visible
band, `SpectrumBandChartView` maintains its own EMA of band level
in linear power space (`leqAlpha = 0.02`, ≈ 580 ms time constant
at the publish rate). This is per-widget state, not shared.

If two Spectrum widgets are on the dashboard, the same EMA runs
twice. If a third-octave + an octave widget coexist, they each
maintain their own per-band EMA.

**Fix**: AudioEngine already computes broadband LAeq via
`AcousticMetricsCalculator`. Adding a **per-band LAeq buffer**
(31 floats per weighting) to `AcousticMetricsCalculator` would
centralize the EMA. Then `SpectrumBandChartView` just reads
`live.bandLeq` instead of maintaining its own.

This is also a correctness win: M9 task-4 flagged the hardcoded
`leqAlpha = 0.02` constant — moving it to the engine lets us
expose it as a user setting on the Spectrum widget settings
sheet without needing widget-local state.

### Medium impact

#### R4. LoudnessCalculator instantiated per widget

Four call sites each own a `@StateObject LoudnessCalculator`:
- `SingleValueWidget` (line 7)
- `LAFGraphWidget` (line 6)
- Watch `WatchLoudnessWidget` (line 12)
- `Shared/LoudnessCalculatorView` (line 12)

Each instance has its own internal interpolation cache. The phon
↔ sone lookup tables are static across the app's lifetime.

**Fix**: make `LoudnessCalculator` a singleton with thread-safe
methods, or pull the calculation into `AcousticMetricsCalculator`
so phon/sone become part of the standard `levels[...]` dict.
Eliminates duplicate per-widget state and the per-widget
`@StateObject` allocation cost on dashboard layout changes.

Bonus correctness: M9 task-3 + task-7 both flagged that the
phon/sone overlay reads `data.levels["LAF"]` regardless of the
user's explicitly-selected metric. Centralising the loudness
calc inside the metrics layer also fixes this — the caller would
pass `metricKey` and the calc would pick the right level.

#### R5. Frequency weighting decision happens in two places

The audio thread decides which weightings to compute via
`requiredSpectralWeightingsForCurrentFrame()`. But individual
widgets *also* select a weighting via `data.magnitudes(for: weighting)`
(SpectrogramData accessor) and `audioEngine.currentOctaveBandsA/Z/C`
direct reads.

Today the widget's `weighting` setting is read from
`@Published frequencyWeighting` on AudioEngine, plus per-widget
override settings. The required-weightings set should already
cover all widget needs.

**Risk**: if a widget reads `magnitudesA` but the required-set
didn't include `.a` (e.g. widget override changed faster than
the requirements update), the widget falls back to the Z
magnitudes via `data.magnitudes(for:)` accessor's `?? magnitudes`
clause — silent degradation, not a crash.

**Fix**: tighten the contract. Either guarantee that
required-set is updated synchronously on widget settings change
(today it's lazy via `widgetSpectralWeightingsLock` — call sites
exist but coverage of every settings path isn't proven), or
expose `data.magnitudes(for:)` as a Result type so callers can
log on fallback.

### Low impact

#### R6. `currentSpectrum` vs `currentSpectrogramData.magnitudes`

Both publish the same array. `currentSpectrum` is set once on
the main thread after processing; `currentSpectrogramData.magnitudes`
is the same data wrapped in a struct. Widgets reading either get
the same numbers, but reading both via two separate
`@ObservedObject` accesses doubles SwiftUI's dependency-tracking
work.

**Fix**: deprecate `currentSpectrum` in favor of consuming
`currentSpectrogramData?.magnitudes` (with the existing weighting
accessor). One source, one publish. ~50 LOC removable from
LiveAcousticState + 12 forwarders.

#### R7. `currentOctaveBands` (the unweighted variant)

LiveAcousticState publishes both `currentOctaveBands` (the
"active weighting") and `currentOctaveBandsZ/A/C`. The active
variant is just an alias for one of the weighted ones, picked by
`frequencyWeighting`.

**Fix**: delete `currentOctaveBands` — every consumer can read
the weighted variant directly via the widget's resolved
weighting setting. M9 task-4 already flagged that the
`FrequencySpectrumWidget` reads `currentOctaveBandsA/Z/C`
explicitly; nothing currently consumes the alias.

#### R8. Calibration is a hot read

`calibrationOffset` is read once per frame at line 1332-1333 and
again at line 1404. Both reads happen on the audio render thread.
Float reads are atomic on iOS but the published-property KVO
machinery isn't lock-free.

**Fix**: snapshot once at frame start (`let cal =
calibrationOffset`) and use the local. Trivially cheap, removes
two `objc_msgSend` calls per frame.

#### R9. Bandstop filter snapshot per frame

`bandstopFilterManager.snapshotEnabledFilters()` is called every
frame inside `SpectrogramProcessor.applyBandstopFilters`. The
filter list rarely changes (user-driven). Snapshot could be
cached and invalidated only on filter mutation.

**Fix**: cache + invalidate on `filterManager.filters` change.
Low impact under default usage (no filters), real impact only
when many filters are configured.

### Out-of-band but worth noting

#### R10. Spectrogram smoothing happens twice

`SpectrogramProcessor.process(...)` runs temporal smoothing on
the binned magnitudes. The `HighEndSpectrogramAdapter` (Metal)
also applies its own smoothing kernel per-row in the shader (if
enabled). For users who turn on temporal smoothing, both layers
contribute — likely the intent, but worth confirming visually
that the result matches expectations on hardware.

#### R11. MaskingEngine consumes Z bands separately

`MaskingEngine.receiveBands` is called via the `onBandsUpdated`
callback with the **active-weighting** bands (per
`AudioEngine.updateUI`). Masking math is intended to operate on
Z (linear). When the user selects A or C weighting, masking sees
A or C bands instead of Z — likely a latent bug, not a perf
issue.

**Fix**: change the callback to always pass Z bands. Mask
calibration / ambient model should not shift when the user
toggles weighting.

## Recommended landing order

If you want concrete commits, ranked by perf impact ÷ code risk:

1. **R8 (cal snapshot)** — 5-line fix, zero risk, lands today.
2. **R7 (delete `currentOctaveBands` alias)** — drops one
   `@Published` from LiveAcousticState. Touches the LiveAcoustic
   forwarder block and any consumer references. ~15 min of work.
3. **R6 (consolidate `currentSpectrum`)** — slightly bigger
   reach but follows the same pattern.
4. **R4 (singleton LoudnessCalculator)** — small file, fixes
   the per-widget `@StateObject` waste.
5. **R3 (centralize Leq EMA in AcousticMetricsCalculator)** —
   new method on the calculator + new LiveAcousticState band-Leq
   buffer + delete the widget's local EMA. Bigger change but
   high payoff.
6. **R2 (move Bark aggregation upstream)** — add a Bark
   precompute output to `AudioEngine` (gated like A/C
   weightings); widget reads directly.
7. **R5 (tighten weighting contract)** — needs API design;
   defer.
8. **R1 (kill `vizAudioEngine`)** — biggest win, biggest reach.
   Needs a `PlaybackAnalyzer` extract from `AudioEngine`. Pair
   with M13 task-4 Phase 2 since both touch the same surface.

## Acceptance criteria for "centralization complete"

If you want a binary test of when this is done:

1. **Single AudioEngine instance per app lifetime** (kill R1).
2. **Zero per-bin or per-band aggregation inside SwiftUI Canvas
   closures** — all widget bodies read pre-computed arrays from
   LiveAcousticState (kill R2, R3).
3. **All broadband and per-band acoustic metrics computed in
   `AcousticMetricsCalculator`** — including phon, sone, per-band
   Leq (kill R3, R4).
4. **Single `Color` for each accent / state across both targets**
   (already inventoried; tracked under M13 task-8 Phase 2 and
   M13 task-7 Phase 2).
5. **MeasurementDataWriter is the single recording-time output
   path**; recording detail view reads back via
   `MeasurementDataReader`, never re-runs DSP (depends on R1).

## What to do with this report

This is a read-only audit. No code changes proposed in this pass.
The numbered items can be landed individually as small commits
under a new task (M13 task-10 candidate: "Performance audit
follow-ups") or folded into M14 if M13 closes first.

R1 (the second AudioEngine) is the single highest-leverage fix
and would benefit from being its own dedicated task with a
hardware before/after Instruments capture.
