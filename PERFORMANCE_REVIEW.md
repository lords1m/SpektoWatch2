# SpektoWatch — Performance Review (May 2026)

A focused audit of the audio hot-path, FFT/processing pipeline, UI update path,
and recording I/O. The Metal/shader layer was already optimised in Jan 2026
(see `SPECTROGRAM_REFERENCE.md`); this review targets the **Swift side** of the
pipeline, where most remaining wins are.

The processing thread runs at roughly **86 FFTs/sec** (44.1 kHz / hop 512), so
any per-frame inefficiency multiplies fast.

---

## Top 5 — biggest wins, easiest to land

These are ranked by *expected CPU reduction × effort*. Numbered file:line refs
are against the current `main` checkout.

### 1. `FrequencyWeightingProcessor.applyWeighting` recomputes `log10` every call

**File:** `SpektoWatch2/Processing/FrequencyWeightingProcessor.swift:66-69`

```swift
for i in 0..<count {
    let gainDB = 20.0 * log10(max(gains[i], 1e-10))
    weighted[i] = dbMagnitudes[i] + gainDB
}
```

The weighting gains are immutable after `init`, but `20 * log10(gain[i])` is
recomputed for every bin on every call. The hot path runs **A and C
separately, plus Z** in `AudioEngine.processFFTFrame` — so this is roughly
**3 × 4096 × 86 ≈ 1.06 M `log10` calls per second**, all for a constant value.

**Fix:** Pre-compute and store `aWeightingGainsDB`, `cWeightingGainsDB`,
`zWeightingGainsDB` (all zeros) at init. Hot path becomes a single vDSP add:

```swift
vDSP_vadd(dbMagnitudes, 1, gainsDB, 1, &weighted, 1, vDSP_Length(count))
```

**Expected impact:** ~3-5 % CPU on the processing thread; eliminates a non-trivial source of jitter.

---

### 2. `AudioEngine.processFFTFrame` runs Z, A *and* C even when only one is shown

**File:** `SpektoWatch2/AudioEngine.swift:1167-1230`

The method currently:
- applies A *and* C *and* Z weighting (`localWeightingProcessor.applyWeighting` ×2 + `dbZ` aliased)
- runs `spectrogramProcessor.process()` three times — once per track
- runs `computeDisplayThirdOctaveBands` three times
- selects one as `processed` and `displayOctaveBands`

The other two tracks are only consumed when `isRecordingToFile && isMeasurementRecording` is true (line 1273) or when sent to the watch as part of `SpectrogramData` (Z is the primary, A/C are optional in `SpectrogramData.toBinaryData()`).

**Fix:** Gate Z+A+C computation:

```swift
let needsAllTracks = isRecordingToFile && isMeasurementRecording
let processedZ = needsAllTracks || frequencyWeighting == .z ? compute(.z) : nil
let processedA = needsAllTracks || frequencyWeighting == .a ? compute(.a) : nil
let processedC = needsAllTracks || frequencyWeighting == .c ? compute(.c) : nil
```

…and pass `nil`s into `SpectrogramData` (it already supports optional A/C).

**Expected impact:** ~30-40 % reduction in `processFFTFrame` cost when the user
isn't recording. This is the single largest win in the audit.

---

### 3. `FFTProcessor.convertToDB` / `convertToLinear` — scalar log10 / pow

**File:** `SpektoWatch2/Processing/FFTProcessor.swift:381-403`

```swift
for i in 0..<linearMagnitudes.count {
    let mag = max(linearMagnitudes[i], 1e-10)
    dbMagnitudes[i] = 20.0 * log10(mag)
}
```

Pure scalar Swift over 4096 bins on every FFT frame.

**Fix:** Use Accelerate's vectorised log10:

```swift
import Accelerate

func convertToDB(_ linear: [Float], into out: inout [Float]) {
    let n = vDSP_Length(linear.count)
    var floor: Float = 1e-10
    vDSP_vsmax(linear, 1, &floor, &out, 1, n)         // max(linear[i], 1e-10)
    var count = Int32(linear.count)
    vvlog10f(&out, out, &count)                        // log10 in place
    var twenty: Float = 20.0
    vDSP_vsmul(out, 1, &twenty, &out, 1, n)            // × 20
}
```

(Same idea for `convertToLinear` using `vvexp10f` or `vvpowf`.)

**Expected impact:** ~5-8× faster on these helpers; meaningfully reduces tail
latency on slower devices.

Note: also expose a buffer-in / buffer-out variant so callers can avoid the
`return [Float]` allocation on every call (see #5).

---

### 4. `MeasurementDataWriter.writeFrame` — synchronous I/O on the audio thread

**File:** `SpektoWatch2/MeasurementDataWriter.swift:43-78`

During measurement recording, every FFT frame:
1. Allocates a fresh `Data(capacity: frameSize)`
2. Calls `appendFloatLE` per scalar (timestamp + ~30 metrics + 3×31 octaves + 4096-bin FFT ≈ 4220 individual appends)
3. Calls `fileHandle.write(frame)` synchronously

At 86 frames/sec × ~17 KB/frame = ~1.4 MB/sec of synchronous disk writes,
**directly on the audio processing path**. This can stall the FFT loop and
cause backlog drops (`maxRealtimeBacklogSeconds = 0.12`).

**Fix:**
1. Pre-allocate one reusable `Data` of `frameSize` once in `init`. Use
   `withUnsafeMutableBytes` and `memcpy` from a contiguous Float buffer
   instead of per-element `appendFloatLE`.
2. Move the actual `fileHandle.write` to a dedicated serial dispatch queue.
   Push frames into a small ring buffer (size 16-32) and let the queue drain
   them. If the ring overflows, drop with a log line — better than stalling
   the processing thread.

**Expected impact:** Eliminates one of the worst tail-latency sources during
recording. Recordings on iPhone 11 / older iPads should stop dropping frames.

---

### 5. `FFTProcessor.performFFT` returns a copy of the magnitudes buffer

**File:** `SpektoWatch2/Processing/FFTProcessor.swift:330, 375`

```swift
return magnitudesBuffer
```

Swift `Array` is copy-on-write. The caller receives a copy (or at least an
extra reference + a likely later copy when callers mutate). At ~4096 floats ×
86 Hz, this is ~1.3 MB/sec of allocation in the hot path, plus ARC traffic.

**Fix:** Add a buffer-out variant the audio engine can use:

```swift
func performFFT(on samples: UnsafePointer<Float>, sampleCount: Int,
                gainBoost: Float, into magnitudes: inout [Float])
```

Reuse a single `[Float]` owned by `AudioEngine` for `linearMagnitudes`,
`dbZ`, etc. Same pattern for `convertToDB`/`convertToLinear`.

While you're in there:
- Replace the **scalar interleave loop** at lines 356-359 with `vDSP_ctoz`
  (literally what it does):

  ```swift
  windowedSamples.withUnsafeBufferPointer { ptr in
      let cplx = UnsafeRawPointer(ptr.baseAddress!).assumingMemoryBound(to: DSPComplex.self)
      var split = DSPSplitComplex(realp: &realIn, imagp: &imagIn)
      vDSP_ctoz(cplx, 2, &split, 1, vDSP_Length(fftSize / 2))
  }
  ```

- The `NSLock` here is hot. If `FFTProcessor` is only ever touched from the
  audio thread plus rare reconfig from the main thread, switch to
  `os_unfair_lock` — same correctness, ~10× faster contention-free path.

**Expected impact:** ~5-10 % CPU reduction on the processing thread.

---

## Medium wins

### 6. `AudioEngine.processFFTFrame` — energy loop is scalar
**File:** `AudioEngine.swift:1247-1252`

```swift
for i in 0..<count {
    let magSq = rawMagnitudes[i] * rawMagnitudes[i]
    energyZ += magSq
    energyA += magSq * aWeights[i] * aWeights[i]
    energyC += magSq * cWeights[i] * cWeights[i]
}
```

Replace with three `vDSP_dotpr` calls (or one `vDSP_vsq` into a temp buffer
plus three `vDSP_dotpr`s):

```swift
var magSq = [Float](repeating: 0, count: count)            // pre-allocate this once
vDSP_vsq(rawMagnitudes, 1, &magSq, 1, vDSP_Length(count))
vDSP_sve(magSq, 1, &energyZ, vDSP_Length(count))
// for A, C: precompute aWeightsSq / cWeightsSq once and dotpr
vDSP_dotpr(magSq, 1, aWeightsSq, 1, &energyA, vDSP_Length(count))
vDSP_dotpr(magSq, 1, cWeightsSq, 1, &energyC, vDSP_Length(count))
```

Same observation as #1: `aWeightsSq` is constant — compute once.

---

### 7. `AudioEngine.processFFTFrame` — calibration offset add is scalar
**File:** `AudioEngine.swift:1161-1163`

```swift
for i in 0..<dbMagnitudes.count {
    dbMagnitudes[i] += calibrationOffset
}
```

→ `vDSP_vsadd(dbMagnitudes, 1, &calibrationOffset, &dbMagnitudes, 1, n)`

Trivial change, modest payoff.

---

### 8. `SpectrogramProcessor.applyBandstopFilters` — log10 per bin per frame
**File:** `SpectrogramProcessor.swift:104-111`

```swift
filtered[i] += 20 * log10(attenuationMap[i])
```

`attenuationMap` only changes when the filter set changes. Cache an
`attenuationDB: [Float]` alongside the linear map and:

```swift
vDSP_vadd(magnitudes, 1, attenuationDB, 1, &filtered, 1, n)
```

Make sure to encode the "blocked" case (`< 0.01`) as a sentinel `-120 - mag[i]`
so that `magnitude + sentinel = -120`, or branch once before the vector op.

---

### 9. `SpectrogramProcessor.aggregateByBinningFactor` — append-loop
**File:** `SpectrogramProcessor.swift:175-197`

`while + .append()` builds two output arrays. Pre-allocate to the exact
output size (you already compute it for `reserveCapacity`) and assign by
index. For magnitudes, use `vDSP_meanv` per chunk, or — better — convert
binning into a strided downsample with a window kernel done once with
`vDSP_desamp`.

---

### 10. `SpectrogramProcessor.calculateOctaveBands` — scalar max loop
**File:** `SpectrogramProcessor.swift:162-171`

```swift
for idx in range.start...range.end {
    if magnitudes[idx] > bandMax { bandMax = magnitudes[idx] }
}
```

→

```swift
magnitudes.withUnsafeBufferPointer { ptr in
    vDSP_maxv(ptr.baseAddress! + range.start, 1, &bandMax, vDSP_Length(range.end - range.start + 1))
}
```

---

### 11. `AudioEngine.installMicrophoneTap` — buffer copy on every callback
**File:** `AudioEngine.swift:1021`

```swift
let newSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
```

This allocates a fresh `[Float]` on every audio buffer. Pre-allocate one
reusable `[Float]` of `maxFrameCount` and `memcpy` into it. Pass it down by
slice or unsafe pointer.

Combined with #5 this removes essentially all per-callback allocations on the
audio path.

---

### 12. `AudioEngine.processSamples` — `newSamples.max()` is scalar
**File:** `AudioEngine.swift:1049-1050`

```swift
let peakVal = newSamples.max() ?? 0
let peakDBFS = 20 * log10(abs(peakVal) + 1e-9)
```

`newSamples.max()` is the *signed* max — followed by `abs()`. That's the wrong
shape: a heavily negative sample wouldn't be treated as a peak. Use
`vDSP_maxmgv` which gives absolute-value max in one vectorised call:

```swift
var peakAbs: Float = 0
vDSP_maxmgv(newSamples, 1, &peakAbs, vDSP_Length(newSamples.count))
let peakDBFS = 20 * log10(peakAbs + 1e-9)
```

Faster *and* correct.

---

## UI / SwiftUI wins

### 13. Multiple `@Published` writes in `updateUI`
**File:** `AudioEngine.swift:1400-1413`

Eight separate `@Published` assignments per UI tick fire eight separate
`objectWillChange.send()` notifications. Every subscribed view re-evaluates
its body for each one.

**Fix options:**
1. Batch into a single `@Published var snapshot: AudioSnapshot` struct that
   holds octaveBands, spectrum, levels, etc. One `objectWillChange` per tick.
2. For widgets that don't need the full bundle, use `PassthroughSubject`s for
   each (you already do this for `spectrogramSubject` — line 110).

Option 2 already exists for the high-rate spectrogram path; extending it to
octave bands and spectrum would let `currentSpectrogramData` etc. stop
publishing entirely.

---

### 14. Watch packet allocates `[Float]` per send
**File:** `AudioEngine.swift:1427`

```swift
let dbfsMagnitudes = spectrogramData.magnitudes.map { $0 - offset }
```

Allocation at 10 Hz isn't catastrophic, but it's avoidable:

```swift
var dbfs = [Float](repeating: 0, count: spectrogramData.magnitudes.count)
var negOffset = -offset
vDSP_vsadd(spectrogramData.magnitudes, 1, &negOffset, &dbfs, 1, vDSP_Length(dbfs.count))
```

Or — better — **stop subtracting on the phone side**: ship the calibration
offset in the watch packet header and let the watch convert at display time.
That removes the per-send allocation entirely *and* lets the watch display in
either dB SPL or dBFS.

---

### 15. `levelHistory.removeFirst()` is O(n)
**File:** `AudioEngine.swift:1416-1419`

```swift
self.levelHistory.append(broadbandLevel)
if self.levelHistory.count > self.maxHistorySize {
    self.levelHistory.removeFirst()
}
```

`removeFirst()` on `[Float]` is O(n) (shifts every element). For a circular
history buffer of size `maxHistorySize`, use a dedicated ring buffer:

```swift
struct RingBuffer<T> {
    private var data: [T]
    private var head = 0
    private(set) var count = 0
    // ... append, snapshot, etc.
}
```

---

## Lower priority / cleanup

- **`MeasurementDataWriter.writeFrame` — `forEach { appendFloatLE }`** (line 67-73). Same issue as #4 internally; pack the entire frame into a contiguous `[Float]` buffer once per init, fill it in place, then `Data(bytesNoCopy:)` or single `withUnsafeBytes` write.
- **`measurementMetricKeys.map { levels[$0] ?? -120.0 }`** (`AudioEngine.swift:1282`). Pre-allocate a `[Float]` of the right size, fill in place. Saves an allocation per frame during recording.
- **`FFTProcessor` lock granularity**. The lock is held across the entire FFT, not just the parameter read. If the only mutator is `setWindowFunction` / `reconfigure` (rare, main thread), use `os_unfair_lock` and only lock around config snapshot — not around the actual `vDSP_DFT_Execute`.
- **`processingLock` snapshot pattern in `processFFTFrame`** (lines 1138-1143). Same observation — `os_unfair_lock` would be lighter than `NSLock` for this single-snapshot use.

---

## Quick measurement plan

The repo already has `PerformanceProfilingTests.swift` — extend it before/after each change so the wins are quantified, not assumed:

```swift
let (fftUs, _) = bench(n: 300) { _ = fftProc.performFFT(on: samples) }
let (dbUs,  _) = bench(n: 300) { _ = fftProc.convertToDB(mags) }
let (weightUs, _) = bench(n: 300) { _ = wp.applyWeighting(to: mags, frequencies: f, weighting: .a) }
```

Add equivalent benchmarks for:
- `SpectrogramProcessor.process` (full path)
- `MeasurementDataWriter.writeFrame`
- `AudioEngine.processFFTFrame` end-to-end

Use OS Signposts (already wired via `Self.performanceLog`) and review in
Instruments → "Logging" or "Time Profiler" with Audio + DSP categories.

---

## Suggested rollout order

1. **#1, #5, #3** — pure FFT / weighting changes, zero behaviour change, easy to test.
2. **#2** — gate Z+A+C on recording state. Highest-impact single change. Verify watch + measurement file still get full data.
3. **#4** — async measurement I/O. Unblocks reliable recording on lower-end hardware.
4. **#6, #7, #8, #9, #10** — Accelerate sweep across the rest of the processing chain.
5. **#11, #12** — input path allocation & correctness fix.
6. **#13, #14, #15** — UI batching & ring buffer.

Steps 1-3 alone should reduce average `processFFTFrame` time by roughly **40-50 %** on iPhone 12-class hardware, and substantially more on older devices.

---

*Audit performed May 2026 against the current `main` branch. Line numbers
are accurate at time of review.*
