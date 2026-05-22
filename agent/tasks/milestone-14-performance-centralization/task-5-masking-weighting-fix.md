# Task 5: Masking receives Z bands (R11)

Status: pending
Created: 2026-05-21
Milestone: `milestone-14-performance-centralization`
Source: audit R11

## Goal

`MaskingEngine.receiveBands` always operates on Z-weighted (linear)
1/3-octave bands, regardless of the user's active frequency
weighting. Masking calibration and ambient model should not
drift when the user toggles A/C.

## Why (correctness, not perf)

The audit (R11) traced the callback chain:
`AudioEngine.onBandsUpdated` → set via `MaskingEngine.init` →
called in `AudioEngine.updateUI(..., octaveBands: displayOctaveBands, ...)`
where `displayOctaveBands` is the **active-weighting** array
(line ~1397-1401):

```swift
switch frequencyWeighting {
case .a: displayOctaveBands = displayOctaveBandsA
case .c: displayOctaveBands = displayOctaveBandsC
case .z: displayOctaveBands = displayOctaveBandsZ
}
```

If the user has A-weighting selected, `MaskingEngine` receives
A-weighted bands and its ambient/novelty model captures
A-perceived structure. Switch to Z later and the trigger
behaviour shifts noticeably. Latent bug.

## Scope

- AudioEngine.updateUI: route the `onBandsUpdated` callback off
  `displayOctaveBandsZ` directly, not `displayOctaveBands`.
- Verify the `requiredSpectralWeightingsForCurrentFrame()` set
  always includes `.z` (it already does — line 1515).
- Document the contract in `MaskingEngine`'s init: "always
  receives Z bands; user weighting selection does not affect
  masking."

## Acceptance

- Toggle frequency weighting in the iOS UI; masking ambient
  model and novelty score stay invariant (no calibration drift).
- iOS build green.
- Re-run M9 task-10 (masking) hardware checks for the
  trigger-fires-at-threshold item.
