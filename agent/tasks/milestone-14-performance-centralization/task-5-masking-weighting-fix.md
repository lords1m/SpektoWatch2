# Task 5: Masking receives Z bands (R11)

Status: completed
Created: 2026-05-21
Completed: 2026-05-25
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

- [x] `AudioEngine.onBandsUpdated` always passes `octaveBandsZ` (verified
  at both call sites: `ingestWearableSpectrogramData` line ~1300,
  `updateUI` line ~1866). Bug was already resolved as a side effect of
  M14 task-1 removing the `displayOctaveBands` active-weighting selector.
- [x] `requiredSpectralWeightingsForCurrentFrame()` always includes `.z`
  (confirmed — it's in the initial `[.z, frequencyWeighting]` set).
- [x] Contract documented in `MaskingEngine.wireAudioEngine`: "always
  Z-weighted; do not change to active-weighting array (R11)."
- [x] iOS `** BUILD SUCCEEDED **`.
- [ ] Hardware: toggle A/C weighting → masking novelty score invariant
  (deferred to M9 task-10 hardware pass).

## Verification reversal note

The audit traced the bug to a `displayOctaveBands` selector that picked
Z/A/C based on `frequencyWeighting`. That selector was removed in M14
task-1 ("quick wins"), which dropped the `currentOctaveBands` alias and
the `displayOctaveBands` switch block. Both `onBandsUpdated` call sites
now hardcode `octaveBandsZ` — the bug no longer exists in code.
