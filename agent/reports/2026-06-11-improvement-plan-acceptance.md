# VERBESSERUNGSPLAN — Acceptance Report

Date: 2026-06-11  
Branch: `main` (20 commits ahead of `origin/main`)  
Source: `VERBESSERUNGSPLAN.md` Phases 1–8

## Status

**Phases 1–7: complete (with documented deferrals).**  
**Phase 8: validation run complete for unit tests; UI/device items partial.**

| Phase | Verdict | Notes |
|-------|---------|-------|
| 1 Repo hygiene | ✅ | DerivedData untracked; docs consolidated |
| 2 WatchConnectivityManager | ✅ | Single `Shared/WatchConnectivityManager.swift` |
| 3 AudioEngine decomposition | ✅ partial | 7 extractions; **2181 → ~1860 LOC**; `<600` deferred |
| 4 DI / AppServices | ✅ | All views on `@EnvironmentObject services` |
| 5 Quality items | ✅ | l10n catalog, chart axis dedup, naming docs, DSP dedup |
| 6 Watch protocol | ✅ | protocolVersion, typed codec, 4-byte binary header |
| 7 .spekto v3 | ✅ partial | Dual-read + gated write; **v3 default write deferred** |
| 8 Verification | ✅ partial | 497 unit tests green; UI tests flaky; device smoke pending |

## Commits (plan execution)

```
5ed4c1c feat(measurement): .spekto v3 read path + gated writer (7.1–7.3)
83e583b feat(watch): 4-byte binary packet header (6.3)
b907e1c feat(watch): typed WC message codec (6.2)
ab0163f feat(watch): protocolVersion on WC messages (6.1)
c7c62ce feat(l10n): string catalog for DSP UI enums (5.1)
… Phase 4 DI, Phase 3 AudioEngine extractions, Phase 2 WCM, Phase 1 hygiene
```

## Phase highlights

### Phase 3 — AudioEngine strangler

Extracted: `AudioCaptureSession`, `ProcessingPipeline`, `WearableIngestCoordinator`,
`UIPublishThrottle`, `RecordingWriterCoordinator`, `SampleRingBuffer`, `InputSignalMonitor`.

`AudioEngineCharacterizationTests` guards behavioral neutrality. Further shrink to
`<600` lines requires extracting `updateUI` / `@Published` surface (higher risk).

### Phase 6 — Watch protocol

- Control messages: `protocolVersion` on all outgoing dicts + application context.
- `WatchConnectivityMessageCodec`: typed payloads, legacy wire shape preserved.
- Binary spectrogram packets: 4-byte header (`kind`, `formatVersion`, `reserved`);
  legacy 1-byte kind decode retained.

### Phase 7 — .spekto v3

Spec: `agent/design/spekto-format-v3.md`.

- **Reader:** v1/v2/v3; header CRC32, TLV calibration metadata, EOF seek index.
- **Writer:** v3 when `SPEKTO_SPEKTO_V3=1`; default remains v2.
- **Golden file:** `SpektoWatch2Tests/Fixtures/measurement_v2_golden.spekto`.
- **Watch:** continues writing v2 `.swr` until v3 default is promoted.

## Test validation (2026-06-11)

| Target | Command | Result |
|--------|---------|--------|
| Unit (`SpektoWatch2Tests`) | `xcodebuild test -only-testing:SpektoWatch2Tests` | **497 passed**, 10 skipped, 0 failed |
| Measurement IO | `MeasurementDataIOTests` + related | 28 passed |
| Watch protocol | `WatchConnectivityTests` + `WatchProtocolVersioningTests` | 44+ passed |

### Known gaps

| Item | Status |
|------|--------|
| `IntegrationTests.testSpectrogramPipelineFPSBudget` | Occasional 1s `drainMainQueue` timeout on full runs; passes in isolation |
| `SpektoWatch2UITests` | Multiple failures (ambiguous accessibility IDs, screenshot flows) — pre-existing / env-sensitive |
| Watch target unit tests | Not in active scheme test plan |
| Device AVAudioEngine smoke | Not run in this acceptance |
| Watch smoke (standalone / stream / transfer) | Not run in this acceptance |
| Instruments vs `BASELINE_PROFILING_MATRIX.md` | Not re-profiled in this acceptance |

## Deferred / out of scope

1. **AudioEngine `<600` lines** — remaining capture lifecycle + UI publish path.
2. **v3 default write** (Phase 7.4) — enable after manual waterfall/export on legacy recording.
3. **lzfse FFT compression** (Phase 6.3 optional, Phase 7.4) — needs signpost evidence.
4. **Legacy binary packet 1-byte header removal** — two releases after 4-byte header.
5. **v2→v3 file migration** — explicitly not required (dual-read).

## Manual follow-up checklist

- [ ] Waterfall scrub on a long **v2** recording (real device or fixture import).
- [ ] CSV/PDF export on v2 recording after plan changes.
- [ ] `SPEKTO_SPEKTO_V3=1` recording → reader round-trip on device.
- [ ] Watch standalone recording → phone ingest (`.swr` still v2).
- [ ] Instruments: `performance.audio`, `performance.spectrogram` vs baseline matrix.
- [ ] Promote v3 write default when above are green.

## Risk register

| Risk | Mitigation shipped |
|------|-------------------|
| WCM drift | Single shared manager + typed codec |
| Protocol incompatibility | protocolVersion + legacy decode paths |
| Corrupt .spekto | v3 header CRC; v2 path unchanged |
| AudioEngine regression | Characterization tests + incremental extractions |
