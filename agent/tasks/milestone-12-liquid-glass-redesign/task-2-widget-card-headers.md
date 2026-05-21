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

## Follow-up landed (2026-05-21, second pass — review issue 1+9)

- Card body restructured from overlay to a proper `VStack { header;
  kernel.innerCanvas() }`. The header now sits *above* the kernel
  instead of obscuring its top edge (no more eyebrow over the 20k Hz
  axis on spectrogram/waterfall). The kernel renders inside a 14pt-
  radius dark inner canvas, inset 6pt horizontally and 6pt at the
  bottom so the liquidGlassCard surface is visible as a frame.
- Header space is **reserved unconditionally** — hidden via opacity
  in edit mode rather than removed — so toggling edit doesn't
  reflow the kernel and break Metal redraw assumptions.
- Card total height stays equal to `widget.size.height`; kernel
  height = `max(60, size.height - chromeOverhead)` where overhead
  is cardTopInset(8) + headerHeight(22) + headerGap(6) +
  cardBottomInset(6) = 42pt.

## Deferred / not landed
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
