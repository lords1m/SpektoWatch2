# Milestone 9: Widget Audit

Status: pending
Priority: medium
Estimated: 1 week

## Goal

Go through every in-app widget one by one and verify three things:

1. **Function** — does the widget actually compute/display what it claims?
   Wire up to live data, check edge cases (silence, clipping, single
   channel vs stereo, sample-rate changes).
2. **Settings** — does the settings sheet expose every meaningful knob
   and persist correctly? Are defaults sensible? Are stale/dead settings
   carried over from earlier iterations?
3. **UI/UX** — does the widget render cleanly at every allowed size (M8
   min/max range), at every cell occupancy, in light + dark, in edit
   mode + view mode? Text wraps/truncates? Touch targets reachable?
   Colors accessible?

Take screenshots at each step and embed them in the per-widget task
file so the analysis is reviewable later without redoing the audit.

## Widget Inventory

(`AudioWidgetType.allCases` — `octaveBands` excluded, kept only for
legacy-decode compatibility per `WidgetConfiguration.swift`.)

1. spectrogram — `HighEndSpectrogramAdapter` / Metal
2. waterfall — `AudioWidgets.swift`
3. levelHistory — `AudioWidgets.swift`
4. frequencyDisplay — `AudioWidgets.swift`
5. levelMeter — `AudioWidgets.swift`
6. phaseMeter — `AudioWidgets.swift`
7. singleValue — `AudioWidgets.swift`
8. toneGenerator — `ToneGeneratorWidget.swift`
9. spektralanalyseLab — `AudioWidgets.swift` / dedicated view
10. masking — `Masking/`

One task per widget + one acceptance task = 11 tasks total.

## Method per task

- Read widget source + settings view source.
- Launch app on hardware or paired simulator (AGENT.md: local
  simulator is broken — use hardware).
- Cycle through every settings combination + every allowed size from
  `WidgetConfiguration.sizeRange(for: <type>)`.
- Capture screenshots at each combination via the
  `controlling-mobile-devices` skill or manual airdrop.
- Annotate findings: what works, what's broken, what's missing, what's
  dead. Keep the bar high — this is a quality pass.

## Non-Goals

- Refactoring widget internals beyond fixing obvious bugs uncovered
  by the audit. Larger refactors get their own milestone.
- Adding new widget types.
- watchOS widgets — separate dashboard.
- Standalone iOS widgets (that is M10).

## Acceptance

- Each per-widget task file ends with: ✅ functional, ⚠ open issues
  list, 📸 screenshot links. Issues either land as small fixes in
  the same task or get queued as follow-up backlog items.
- Final acceptance task collates per-widget verdicts into a single
  report under `agent/reports/`.
