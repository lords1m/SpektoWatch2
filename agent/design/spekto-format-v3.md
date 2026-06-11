# .spekto measurement format — version 3

Status: **implemented (write gated)** — reader dual v2+v3; writer v3 behind
`SPEKTO_SPEKTO_V3=1`; default write remains v2 until Phase 7.4 acceptance.

## Goals

1. **Integrity** — IEEE CRC32 over the header region (magic through TLV).
2. **Seek index** — frame offset table at EOF for O(1) random access (needed when
   per-frame compression lands).
3. **Calibration metadata** — TLV block in the header (mic source, gain, offset,
   device model, weighting) so exports/reports retain provenance.
4. **Extensibility** — unknown TLV types are skipped; new fields do not require v4.
5. **Compatibility** — v1/v2 files read forever; v2 files are **not** migrated.

Watch standalone recordings use the same binary layout with extension `.swr`
(`WatchRecordingSession`). Watch continues writing **v2** until iOS min-version
guarantees a v3-capable reader on the phone.

## File layout (v3)

```
┌─────────────────────────────────────────┐
│ Fixed header (52 bytes)                 │
├─────────────────────────────────────────┤
│ Metric keys (length-prefixed UTF-8)     │  same as v2
├─────────────────────────────────────────┤
│ TLV extension (tlvSectionLength bytes)  │  new
├─────────────────────────────────────────┤
│ Frame 0 … Frame N-1                     │  same float layout as v2
├─────────────────────────────────────────┤
│ Seek index trailer (optional)           │  patched on writer close
└─────────────────────────────────────────┘
```

`headerSize` = 52 + metric-keys bytes + `tlvSectionLength`.

## Fixed header (52 bytes, little-endian)

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 4 | `magic` | `0x53504B54` (`"SPKT"`) |
| 4 | 2 | `version` | `3` |
| 6 | 2 | `fftBinCount` | same as v2 |
| 8 | 8 | `frameCount` | patched on close (offset 8) |
| 16 | 8 | `sampleRate` | Hz |
| 24 | 4 | `fps` | frames per second |
| 28 | 4 | `fftBlockSize` | FFT size |
| 32 | 2 | `metricCount` | |
| 34 | 2 | `flags` | see below |
| 36 | 4 | `headerCRC32` | IEEE CRC32; `0` while recording |
| 40 | 8 | `seekIndexOffset` | byte offset to seek trailer; `0` while recording |
| 48 | 4 | `tlvSectionLength` | bytes following metric keys |

### Flags (v3)

| Bit | Name | Meaning |
|-----|------|---------|
| 0 | `flagHasFullFFT` | trailing full-FFT floats per frame (v2) |
| 1 | `flagCompressedFFT` | **reserved** — per-frame lzfse FFT (not implemented) |
| 2 | `flagHasSeekIndex` | seek trailer present at `seekIndexOffset` |

## TLV section

Repeated records: `type: UInt16`, `length: UInt16`, `value[length]`.

| Type | Value |
|------|-------|
| 1 | Microphone source (`MicrophoneSource.rawValue`, UTF-8) |
| 2 | Capture gain (`Float32`) |
| 3 | Calibration offset dB (`Float32`) |
| 4 | Device model (`UIDevice`/`WKInterfaceDevice` model string, UTF-8) |
| 5 | Frequency weighting (`"A"` / `"C"` / `"Z"`, UTF-8) |

Unknown types: skip `length` bytes.

## Frame body

Identical to v2/v1: `timestamp`, metric floats, `broadbandLevel`, 31×Z, 31×A,
31×C, optional `fftBinCount` full-FFT floats when `flagHasFullFFT`.

## Seek index trailer

Written at `seekIndexOffset` on `MeasurementDataWriter.close()`:

| Offset | Size | Field |
|--------|------|-------|
| 0 | 4 | `magic` = `0x58444E49` (`"INDX"`) |
| 4 | 8 | `frameCount` (must match header) |
| 12 | 8×N | absolute file offsets to each frame |

While recording, `seekIndexOffset == 0` and `headerCRC32 == 0`; readers use
fixed stride (`frameSize`) like v2.

## CRC32

- Algorithm: IEEE CRC32 (same as PNG/zlib `crc32()`).
- Region: bytes `[0 ..< headerSize)` with bytes 36–39 (`headerCRC32`) treated as zero.
- Validated on read when `headerCRC32 != 0`.

## Version matrix

| Version | Write default | Read |
|---------|---------------|------|
| 1 | no | yes (legacy) |
| 2 | **yes** | yes |
| 3 | env `SPEKTO_SPEKTO_V3=1` | yes |
| >3 | no | `unsupportedVersion` |

## Migration policy

**No conversion.** Dual-read makes migration unnecessary. v2 golden files must
round-trip unchanged.

## Deferred (v3.1+)

- `flagCompressedFFT` + lzfse per-frame blocks (gated on profiling evidence).
- v3 as default write (`MeasurementDataFormat.version = 3`) after manual
  waterfall/export acceptance (Phase 7.4).
