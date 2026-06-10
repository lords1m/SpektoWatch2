# Profiling SpektoWatch2 (Instruments)

Use a **physical iPhone** and **Release** or **Profile** configuration for realistic timing. Debug builds and `SPEKTO_DEBUG_SPECTRUM=1` add overhead; compare both when tuning the spectrum path.

## Instruments template

Add these instruments (File → New Recording, or duplicate **Time Profiler** template):

| Instrument | Purpose |
|------------|---------|
| **Time Profiler** | CPU stacks, main-thread work |
| **Hangs** | Microhangs (>250 ms) and full hangs |
| **Points of Interest** | App signposts (`com.spektowatch`, category PointsOfInterest) |
| **Thermal State** | Nominal / Fair / Serious |

Recording mode: **Deferred** (Xcode Profile) is fine.

### Signposts to correlate

| Name | When |
|------|------|
| `PersistenceMigration` | UserDefaults migration ladder |
| `MetalPrewarm` | `MTLCreateSystemDefaultDevice` |
| `AudioEngineStart` | `startAudioCapture()` through graph start |
| `AudioCapturePrewarm` | Lazy `AVAudioEngine` + `prepare()` after engine init |
| `AudioEngineSetup` | `finishAudioEngineSetup` (mic graph on main) |
| `DashboardLoad` | Decode + apply persisted dashboard |

## Device prep (important)

After a long profile, the phone may start in **Serious** thermal state and skew the next trace.

1. Force-quit SpektoWatch2.
2. Wait **2–3 minutes** until Settings → Privacy (or a prior trace) shows cooling; aim for **Nominal** at record start.
3. Unplug/replug USB if attach fails.

## Scenarios (one trace file each)

### 1. Cold launch (~5 s)

1. Start recording, then launch the app once.
2. Do not tap anything for 5 s.
3. Stop.

**Pass:** no hang >250 ms in the first 2 s; `PersistenceMigration` ends before `AudioEngineStart` on main.

### 2. First live audio (~60 s)

1. Cold launch, wait for dashboard.
2. Start recording when UI is visible.
3. Start **live mode** (mic) once — the path that used to stall around 45–66 s.
4. Hold 30–60 s, stop.

**Pass:** `AudioCapturePrewarm` before user tap; `AudioEngineSetup` under ~300 ms on main (Hangs track).

### 3. Sustained spectrum (~3 min)

1. Launch with spectrum visible.
2. Record ~3 min with minimal navigation.
3. Stop.

**Pass:** thermal reaches **Serious** later than a baseline trace; main thread mostly idle between UI updates.

## Scheme environment variables

| Action | `SPEKTO_DEBUG_SPECTRUM` |
|--------|-------------------------|
| **Run** (Debug) | `1` (enabled in scheme) |
| **Profile** (Release) | off (baseline CPU) |

## Exporting tables (optional)

```bash
xctrace export --toc --input /path/to/trace.trace
xctrace export --input /path/to/trace.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="potential-hangs"]'
```

## Baseline comparison

Keep named traces (e.g. `run.trace`, `profilerun2.trace`) and compare hang timestamps, thermal intervals, and POI ordering after optimization changes.
