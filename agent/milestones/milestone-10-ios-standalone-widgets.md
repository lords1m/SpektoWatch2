# Milestone 10: iOS Standalone Widgets

Status: pending
Priority: medium
Estimated: 2 weeks

## Goal

Take a subset of the in-app widgets and re-expose them as native iOS
home-screen / lock-screen widgets (WidgetKit). The user picks widgets
in iOS's widget gallery, drags them onto their home screen, and they
update via the standard system refresh cycle — no app foreground
required.

## Reality check (read first)

WidgetKit widgets are **timeline-driven snapshots**, not live views.
The system asks the widget for a timeline of entries every so often
(seconds to hours, never guaranteed); the widget renders each entry
as a static SwiftUI view. This rules out anything that needs live
audio:

| In-app widget | Standalone iOS widget feasibility |
|---|---|
| spectrogram | ❌ live audio, no background mic |
| waterfall | ❌ live audio |
| levelHistory | ⚠ only as snapshot from last recording |
| frequencyDisplay | ❌ live FFT |
| levelMeter | ❌ live audio |
| phaseMeter | ❌ live audio |
| singleValue | ⚠ "last reading" or "last LAeq from last recording" |
| toneGenerator | ⚠ interactive via AppIntents (iOS 17+); plays only when widget tapped |
| spektralanalyseLab | ❌ live |
| masking | ❌ requires app foreground |

So this milestone is **not** "the same widgets but on home screen."
It is "a small set of recording-centric snapshot widgets + one
interactive quick-action widget."

## Design first (gated by task-1)

Task-1 is a design pass. Lock the list before any code lands.
Starting candidates:

1. **"Letzte Messung" (Small)** — name, date, duration, LAeq of the
   most recent recording. Single-glance summary on home screen.
2. **"Recent Recordings" (Medium / Large)** — list of last 3 / 5
   recordings with their LAeq.
3. **"Level Snapshot" (Small)** — if the app ran a measurement in
   the last N minutes, show that level. Otherwise an empty / "open
   app" state. Powered by the AppGroup state that M5/M6 already
   writes for the watch complication.
4. **"Tonegenerator Quick" (Small, iOS 17+)** — AppIntents-based
   tappable widget that launches the app with the last-used tone
   pre-loaded. Optional stretch goal.

Anything beyond that goes to the backlog.

## Architecture

- New target: **`SpektoWatch2Widgets`** (iOS Widget Extension).
- Reuse `Shared/AppGroup.swift` from M6 task-4. The watch
  complication already writes a compatible state blob via
  `AppGroup.defaults`. The iOS widgets read the same store — no
  new IPC.
- Recording list: reads `recordings_metadata_v2.json` from the
  shared App Group container (not Documents — current location is
  inside the app sandbox; a small RecordingManager migration may
  be needed, see task-3 notes).
- Timeline policy:
  - "Letzte Messung" / "Recent Recordings": `.atEnd` reload after
    each recording finishes (post via NotificationCenter →
    `WidgetCenter.shared.reloadTimelines(ofKind:)`).
  - "Level Snapshot": `.after(60s)` while the app was recently
    active, `.never` once stale.

## Gated by

- **App Group entitlement.** M6 task-4 created the entitlement
  files and the code-side reads/writes, but the App Group itself
  still needs to be registered in the Developer Portal and wired
  via `CODE_SIGN_ENTITLEMENTS` in `project.pbxproj` for both the
  app target and the new widget extension target. Without this
  the widgets fall back to `UserDefaults.standard`, which is
  per-process and therefore broken across extension/app boundary.

## Tasks (initial)

1. Design — lock the widget list + sizes + timeline policy +
   AppGroup data contract.
2. Widget extension target — scaffold `SpektoWatch2Widgets`, wire
   App Group, embed in app, verify it boots empty.
3. "Letzte Messung" widget (Small).
4. "Recent Recordings" widget (Medium + Large).
5. "Level Snapshot" widget (Small).
6. (Optional) Tonegenerator Quick (Small, iOS 17+ AppIntents).
7. Acceptance — install on hardware, hot-swap a recording, verify
   each widget updates within the expected refresh window.

## Non-Goals

- Lock-screen widgets requiring continuous data (none of the
  shipped ones do anyway).
- watchOS complication parity beyond what M5 already ships.
- Live-data widgets — explicit out of scope per the reality check
  above.
- Interactive widgets beyond the optional Tonegenerator Quick.

## Acceptance

- All tasks above completed.
- At least one widget installed and stable on hardware for ≥ 24h.
- App Group store contract documented under
  `agent/design/` so future widgets can read the same source of
  truth without re-deriving it.
