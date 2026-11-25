# Task 3: Live Widgets for All App Functions

Status: pending
Created: 2026-11-25
Milestone: `milestone-23-home-screen-dual-mode-widgets`

## Goal

Ensure every app function—not just acoustic plots—has a rich, useful inline
`Live-Widget` representation on the Home Screen alongside its `1×1` icon mode.

## Scope

- **`RecordingsHomeWidget` (`2×1`–`3×2`):**
  - Observes `services.recordingManager`, displays total recording count and the
    most recent recording's title, date, duration, and `LAeq` `LevelChip`.
  - Includes quick actions to open the latest recording's `RecordingDetailView`
    or open `RecordingsListView`.
  - Clean empty state when no recordings exist yet.
- **`SettingsQuickWidget` (`2×1`–`3×2`):**
  - Observes `AudioEngine` settings state (without subscribing to 15 Hz live
    FFT frames): displays active microphone source (`iPhone` vs. `Apple Watch`),
    calibration offset (`dB`), and active frequency/time weighting
    (`dB(A) · Fast`).
  - Quick inline weighting/source controls + button to open full `SettingsRootView`.
- **`AudioEditorHomeWidget` Wiring:**
  - Wire `M22`'s `AudioEditorHomeWidget` (latest recording mini waveform,
    duration/format badge, quick `Bearbeiten` / `Konvertieren` / `Importieren`
    buttons) into `WidgetCardView.renderWidgetContent()`. (Provide a clean
    fallback stub if M23 is compiled before M22 merges.)
- **`WidgetCardView` Routing:**
  - Wire `.audioEditor`, `.recordings`, and `.settings` into
    `WidgetCardView.renderWidgetContent()` when `displayStyle == .liveWidget`.

## Acceptance

- Every active `AudioWidgetType` renders a complete, responsive `Live-Widget`
  within its allowed `WidgetSize` bounds (`sizeRange(for:)`).
- `SettingsQuickWidget` and `RecordingsHomeWidget` do not re-render on 15 Hz
  audio publish ticks.

## Notes

- Follow `LiveAcousticState` isolation patterns (`@ObservedObject` only on the
  state slice each widget actually needs).
