# Task 2: Widget Card Headers

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-12-liquid-glass-redesign`
Depends on: task-1

## Goal

Add the eyebrow + meta-value row at the top of every widget card per
the redesign spec (`design_handoff_spektowatch_redesign/README.md §
2 Widget Card`).

## Landed (2026-05-21)

- `WidgetCardView.cardHeader` — 11pt SF Symbol + 10pt SF Mono
  uppercase title (`tracking 1.8`, `.secondary`); right-aligned meta
  pill (semibold mono value + tertiary mono unit) on a dark capsule
  so the readout stays legible over any kernel background.
- Header rendered as a `.overlay(alignment: .top)` on the card so
  total card height stays equal to `widget.size.height` — no
  dashboard layout regression.
- Header hidden in edit mode to keep the drag/delete circles
  unobstructed.
- `metaText` derives the live readout from
  `audioEngine.currentSpectrogramData?.levels` (pure read; no kernel
  changes):
  - levelHistory / levelMeter / singleValue → LAF (dB(A))
  - spectrogram / waterfall / frequencyDisplay / octaveBands /
    spektralanalyseLab → LAeq (dB Leq)
  - phaseMeter / toneGenerator / masking → nil (no meaningful scalar
    without touching the kernel; defer to a later sub-pass)

## Deferred / not landed

- **Inner-canvas wrapper.** Task scope said to apply `.innerCanvas()`
  to each kernel's body. Skipped this pass because most kernels
  (Spectrogram, Waterfall, FrequencySpectrum, etc.) already paint
  their own dark background; wrapping would double-up, and the
  task's own non-goal forbids changing kernel rendering. Revisit
  per-kernel when the audit (M9) flags which ones actually render on
  a transparent canvas.
- **Per-widget meta sources for non-level types.** Phase/tone/masking
  meta would need to read from each widget's local state — out of
  scope for "no kernel changes". Will pick up in a follow-up pass
  alongside task-5 once each kernel's settings sheet is touched.

## Validation

- `xcodebuild -scheme SpektoWatch2 -destination 'generic/platform=iOS
  Simulator' build` → `** BUILD SUCCEEDED **`.
- Local simulator broken; visual acceptance gated on hardware
  (task-6).

## Acceptance status

- [x] Every widget card shows the eyebrow strip (in live mode).
- [x] Meta values update live for level-derived types.
- [ ] Meta values for phase/tone/masking — deferred with rationale.
- [ ] Hardware visual pass — gated on task-6.

Promoting to `completed` is gated on the hardware pass; status stays
`in_progress` until then.
