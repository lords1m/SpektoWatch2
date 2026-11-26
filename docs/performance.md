# Performance

Single reference for SpektoWatch2 performance targets, baseline profiling, and
release gates. Merged from the former root files `PERFORMANCE_BUDGET.md`,
`BASELINE_PROFILING_MATRIX.md`, `PERFORMANCE_CONTRACT.md`, and
`docs/profiling.md`.

Audio continuity always has priority over visual smoothness.

## Contents

1. [Budget](#1-budget) — hard targets per scenario and device
2. [Signposts and guard tests](#2-signposts-and-guard-tests)
3. [Baseline profiling matrix](#3-baseline-profiling-matrix) — how to collect and record a baseline
4. [Instruments guide](#4-instruments-guide) — launch/live/sustained traces, device prep
5. [Release checklist and post-release monitoring](#5-release-checklist-and-post-release-monitoring)

---

## 1. Budget

### Scope

- iOS app (`SpektoWatch2`)
- watchOS companion (`SpektoWatch Watch App`)
Core realtime paths:
- `Audio capture and FFT processing`
- `Spectrogram rendering (Metal)`
- `Watch connectivity updates`

### Reference Devices

- iPhone reference: iPhone 12 class or newer
- Apple Watch reference: Series 7 class or newer

If a weaker target device is added, budgets must be updated explicitly.

### Test Scenarios

- `S1 Idle`: app open, no recording, no test tone
- `S2 Live`: microphone capture + spectrogram visible
- `S3 Live+Record`: microphone capture + file recording + spectrogram visible
- `S4 Live+Watch`: microphone capture + watch sync active + spectrogram visible
- `S5 Stress`: all active (capture + record + watch sync + widgets visible)

All gates below apply to release builds on physical devices with screen brightness at 50% and Low Power Mode off unless noted.

### iPhone Budget

#### Realtime Quality

- Frame rate (`S2-S5`): >= 58 FPS average, no visible sustained stutter
- Frame time (`S2-S5`): p95 <= 17.2 ms, p99 <= 20 ms
- Audio XRuns / dropouts (`S2-S5`): 0 tolerated
- End-to-end audio-to-visual latency (`S2-S5`): <= 120 ms p95

#### CPU / GPU

- CPU total (`S2`): <= 15%
- CPU total (`S3-S5`): <= 22%
- GPU (`S2`): <= 35%
- GPU (`S3-S5`): <= 45%

#### Memory

- App RSS steady-state (`S2` after 3 min): <= 150 MB
- App RSS steady-state (`S5` after 5 min): <= 180 MB
- Memory growth over 10 min in `S5`: <= 10 MB
- Crashes or jetsam: 0 tolerated

#### Power / Thermal

- Battery drain (`S2`, 30 min): <= 12%
- Battery drain (`S5`, 30 min): <= 18%
- Thermal state in `S5`: must not remain in `.serious` for > 60 s, must never hit `.critical`

### Apple Watch Budget

#### UI and Update Smoothness

- Widget/dashboard refresh cadence (`S4-S5`): >= 1 update/sec under normal conditions
- Perceived UI stutter in watch dashboard: none sustained > 2 s

#### Resource Use

- Watch app CPU (`S4`): <= 25%
- Watch app memory steady-state (`S4` after 3 min): <= 60 MB
- Battery drain (`S4`, 30 min active session): <= 10%

### Connectivity Budget (Phone <-> Watch)

- Transfer latency for live level updates (`S4`): p95 <= 300 ms
- Update loss rate during 10 min run (`S4`): <= 1%
- Backpressure behavior: if overloaded, degrade update frequency before affecting audio path

### Degradation Rules (Must Have)

When limits are approached, quality must degrade in this order:

1. Reduce watch update rate/batching
2. Reduce spectrogram history length (`timeColumns`)
3. Disable interpolation
4. Reduce vertical bins (`frequencyBins`)
5. Increase hop size

Audio integrity (no dropouts) is always higher priority than visual fidelity.

### Release Gates

A release is blocked if any of the following occurs in baseline validation:

- Any audio dropout/XRun in `S2-S5`
- Any metric exceeds budget by > 10%
- Memory leak trend above allowed growth
- Persistent thermal throttling in normal ambient conditions

### Ownership and Update Policy

- Budget owner: app performance maintainer
- Update frequency: whenever FFT/render/config defaults change, or when a new minimum device target is introduced
- Any budget change requires a note explaining tradeoff and user impact

---

## 2. Signposts and guard tests

Signposts currently emitted in code (subsystem `com.spektowatch`, category
PointsOfInterest):

| Signpost | Stage |
|----------|-------|
| `AudioTapCallback` | Mic tap callback |
| `FFTFrameProcessing` | Per-frame DSP in the processing pipeline |
| `PerformFFT` | `FFTProcessor` transform |
| `SpectrogramProcess` | Band aggregation / spectrogram processing |
| `PersistenceMigration` | UserDefaults migration ladder at launch |
| `MetalPrewarm` | `MTLCreateSystemDefaultDevice` |
| `AudioEngineStart` | `startAudioCapture()` through graph start |
| `AudioCapturePrewarm` | Lazy `AVAudioEngine` + `prepare()` after engine init |
| `AudioEngineSetup` | `finishAudioEngineSetup` (mic graph on main) |
| `DashboardLoad` | Decode + apply persisted dashboard |

> The Metal render stage (texture upload / draw) and the watch send/receive
> path have **no signposts** yet. Use Metal System Trace and the watch logs
> for those until signposts are added.

Automated regression guards:

- `FFTProcessorTests.testFFTRegressionBudget`
- `IntegrationTests.testSpectrogramProcessingRegressionBudget`

---

## 3. Baseline profiling matrix

### Preconditions

- Build configuration: `Release`
- Device: physical iPhone (iPhone 12 class or newer), Apple Watch (Series 7 class or newer) for watch scenarios
- iPhone setup: brightness 50%, Low Power Mode off, battery > 40%, airplane mode off for watch tests, app freshly launched before each scenario

### Instruments Templates

- `Time Profiler`
- `Metal System Trace`
- `Allocations`
- `Energy Log`
- `Points of Interest` (for signpost intervals)

### Scenarios and Durations

- `S1 Idle`: 3 minutes
- `S2 Live`: 5 minutes
- `S3 Live+Record`: 5 minutes
- `S4 Live+Watch`: 5 minutes
- `S5 Stress`: 10 minutes

### Capture Procedure (Per Scenario)

1. Connect iPhone and confirm `Release` build is installed.
2. Start Instruments with `Time Profiler + Points of Interest`.
3. Run the scenario for the full duration.
4. Save trace as `Baseline_<scenario>_TimeProfiler.trace`.
5. Repeat scenario for `Metal System Trace + Points of Interest`, `Allocations + Points of Interest`, and `Energy Log + Points of Interest`.
6. Save all traces under ``TestResults/PerformanceBaseline/` (repo-relative, untracked)`.

### Metrics To Record

- FPS average and frame-time p95/p99
- CPU total (app process)
- GPU utilization (render stage)
- Memory RSS steady-state and growth trend
- Audio dropouts / XRuns count
- End-to-end audio-to-visual latency p95 (from signposts and existing latency log)
- Watch update latency p95 and drop/loss estimate (`S4`)
- Battery change over scenario runtime
- Thermal state excursions

### Baseline Results Table

| Scenario | CPU % | GPU % | FPS Avg | Frame p95 ms | RSS MB | RSS Growth MB | XRuns | A/V Latency p95 ms | Watch Latency p95 ms | Battery Delta % | Thermal |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| S1 Idle |  |  |  |  |  |  |  |  | n/a |  |  |
| S2 Live |  |  |  |  |  |  |  |  | n/a |  |  |
| S3 Live+Record |  |  |  |  |  |  |  |  | n/a |  |  |
| S4 Live+Watch |  |  |  |  |  |  |  |  |  |  |  |
| S5 Stress |  |  |  |  |  |  |  |  |  |  |  |

### Pass/Fail Gate

- Compare each row against the budget in section 1.
- Mark scenario as `FAIL` if any audio dropout/XRun occurs, any metric exceeds budget by >10%, memory growth exceeds budget trend, or thermal state remains `.serious` for >60s or reaches `.critical`.

### Notes Template

- Device model:
- iOS / watchOS version:
- App commit/branch:
- Ambient conditions:
- Observed regressions:
- Follow-up actions:

---

## 4. Instruments guide

Use a **physical iPhone** and **Release** or **Profile** configuration for
realistic timing. Debug builds and `SPEKTO_DEBUG_SPECTRUM=1` add overhead;
compare both when tuning the spectrum path.

### Instruments template

Add these instruments (File → New Recording, or duplicate **Time Profiler** template):

| Instrument | Purpose |
|------------|---------|
| **Time Profiler** | CPU stacks, main-thread work |
| **Hangs** | Microhangs (>250 ms) and full hangs |
| **Points of Interest** | App signposts (`com.spektowatch`, category PointsOfInterest) |
| **Thermal State** | Nominal / Fair / Serious |

Recording mode: **Deferred** (Xcode Profile) is fine.

See section 2 for the signpost list.

### Device prep (important)

After a long profile, the phone may start in **Serious** thermal state and skew the next trace.

1. Force-quit SpektoWatch2.
2. Wait **2–3 minutes** until Settings → Privacy (or a prior trace) shows cooling; aim for **Nominal** at record start.
3. Unplug/replug USB if attach fails.

### Scenarios (one trace file each)

#### 1. Cold launch (~5 s)

1. Start recording, then launch the app once.
2. Do not tap anything for 5 s.
3. Stop.

**Pass:** no hang >250 ms in the first 2 s; `PersistenceMigration` ends before `AudioEngineStart` on main.

#### 2. First live audio (~60 s)

1. Cold launch, wait for dashboard.
2. Start recording when UI is visible.
3. Start **live mode** (mic) once — the path that used to stall around 45–66 s.
4. Hold 30–60 s, stop.

**Pass:** `AudioCapturePrewarm` before user tap; `AudioEngineSetup` under ~300 ms on main (Hangs track).

#### 3. Sustained spectrum (~3 min)

1. Launch with spectrum visible.
2. Record ~3 min with minimal navigation.
3. Stop.

**Pass:** thermal reaches **Serious** later than a baseline trace; main thread mostly idle between UI updates.

### Scheme environment variables

| Action | `SPEKTO_DEBUG_SPECTRUM` |
|--------|-------------------------|
| **Run** (Debug) | `1` (enabled in scheme) |
| **Profile** (Release) | off (baseline CPU) |

### Exporting tables (optional)

```bash
xctrace export --toc --input /path/to/trace.trace
xctrace export --input /path/to/trace.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="potential-hangs"]'
```

### Baseline comparison

Keep named traces (e.g. `run.trace`, `profilerun2.trace`) and compare hang timestamps, thermal intervals, and POI ordering after optimization changes.

---

## 5. Release checklist and post-release monitoring

### Ship checklist

1. Run baseline scenarios `S1–S5` on reference devices (section 3).
2. Compare values to the budget (section 1) and mark pass/fail.
3. Run the focused regression tests (section 2).
4. Record measured values and attach trace bundle paths to the release notes.

### Post-release monitoring

Compare Xcode Organizer metrics release-over-release:

- CPU time
- Hang rate / launch stability
- Memory footprint trend
- Watch connectivity reliability

Investigate if any KPI worsens by more than 10% versus the last accepted
baseline.
