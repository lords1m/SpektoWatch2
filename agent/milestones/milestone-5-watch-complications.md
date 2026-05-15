# Milestone 5: Watch Complications

Status: in_progress  
Created: 2026-05-14  
Source design: `agent/design/spektowatch-field-engineering-design.md`

## Goal

Deliver the first watch-native surface for SpektoWatch: a WidgetKit complication
extension embedded in the watch app that displays the current sound level on the
Apple Watch face and in the Smart Stack. The complication must consume live data
from the existing `WatchConnectivityManager` pipeline without adding bandwidth
pressure or breaking the compact-protocol constraint.

## Completion Criteria

- A Widget Extension target (`SpektoWatch Complications`) is added to the Xcode
  project and embedded in `SpektoWatch Watch App`.
- Three complication families are implemented:
  - `.accessoryCircular` — circular gauge with dBSPL reading.
  - `.accessoryRectangular` — wider tile with level value and a progress bar.
  - `.accessoryInline` — single-line text with current dBSPL.
- Complications display "–" or a placeholder when no live data is available.
- `WatchConnectivityManager` calls `WidgetCenter.shared.reloadTimelines(ofKind:)`
  when new live measurement data arrives, throttled to at most once per second.
- The watch app build (`SpektoWatch Watch App` scheme) succeeds with the
  extension embedded.
- The existing SpektoWatchTests suite still passes.

## Manual Acceptance

1. Add the "SpektoWatch" complication to a watch face.
2. Start live measurement on the iPhone.
3. Confirm the complication updates with the current dBSPL level within ~2 s.
4. Lock the iPhone or stop measurement.
5. Confirm the complication shows the last value (or a placeholder after a
   reasonable interval).

## Explicit Non-Goals

- No complication on watchOS faces that do not support WidgetKit (pre-watchOS 9).
- No complication for recording state, masking state, or spectral content.
- No standalone watch recording trigger via complication.
- No watchOS Smart Stack interactive element in this milestone.

## Future Milestones

- Complication for recording start/stop via App Intent.
- Smart Stack interactive widget with level trend.
- External calibrated microphone and compliance workflow.
- Polished masking workflow and reusable masking profiles.

## Tasks

- `agent/tasks/milestone-5-watch-complications/task-1-complication-source-files.md`
- `agent/tasks/milestone-5-watch-complications/task-2-xcode-target.md`
- `agent/tasks/milestone-5-watch-complications/task-3-live-data-integration.md`
- `agent/tasks/milestone-5-watch-complications/task-4-acceptance.md`
