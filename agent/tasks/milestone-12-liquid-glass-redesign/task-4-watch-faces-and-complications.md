# Task 4: Watch Faces & Complications

Status: pending
Created: 2026-05-21
Milestone: `milestone-12-liquid-glass-redesign`
Depends on: task-1

## Goal

Implement the three watch faces and the five complication slot
layouts from `design_handoff_spektowatch_redesign/README.md § 6–7`.

## Scope

### Faces

- **Pegelmesser** — 64pt accent LAF number + dB(A) + bottom peak
  bar (green→yellow→red) + MIN/MAX line.
- **Spektrogramm** — full-screen STFT canvas (viridis) + top status
  bar (pulsing LED + time + "STFT") + bottom "● STFT · 1024" strip.
- **Tongenerator** — `FREQUENZ` label + big "1.00 kHz" + mini sine
  with glow + PAUSE button + λ readout.

### Complications

- Circular Small — arc progress around centered "50 dB(A)".
- Corner / Modular — "LAF · slow" label + big "50.2" + peak bar.
- Rectangular / Smart Stack — live LAF + sparkline + Leq/Lmax/Δ.
- Inline (Modular Face) — single horizontal pill.
- Graphic Bezel — arc + center number + sidebar A-bewertet / Leq /
  Lmax.

## Non-Goals

- Wiring `WatchConnectivity` differently (M5/M6 protocol stays).
- Adding new complication kinds beyond the five listed.

## Acceptance

- All three faces selectable from the watch app.
- At least three complication slots use the new chrome on hardware.
