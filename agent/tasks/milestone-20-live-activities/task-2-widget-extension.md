# Task 2: Widget Extension Target & On-Device Acceptance

Status: in_progress
Created: 2026-05-30
Milestone: `milestone-20-live-activities`

## Done so far (2026-05-30)

- User created the `SpektoWatch2WidgetExtension` target in Xcode
  (synchronized root group `SpektoWatch2Widget/`, embedded in the
  `SpektoWatch2` app, "Include Live Activity" on).
- `Shared/MeasurementActivityAttributes.swift` added to the extension's target
  membership (pbxproj membership exception).
- Replaced Xcode's placeholder `SpektoWatch2WidgetLiveActivity.swift`
  (`SpektoWatch2WidgetAttributes` "Hello World") with the real measurement
  Live Activity on `MeasurementActivityAttributes` (Lock Screen + Dynamic
  Island; live dB(weighting), peak, `.timer` elapsed, recording/paused).
  Kept the struct name so `SpektoWatch2WidgetBundle` stays valid.
- Removed the redundant staged `SpektoWatchLiveActivity/` file.
- iOS app scheme builds green; `SpektoWatch2WidgetExtension.appex` embeds and
  host app `NSSupportsLiveActivities = true`.

Remaining: on-device acceptance (below). Xcode also generated template
`SpektoWatch2Widget.swift` (static widget) + `SpektoWatch2WidgetControl.swift`
(Control Center) still showing placeholder content — flesh out or drop from the
bundle separately; out of scope for the Live Activity.

## Why this is manual

The Live Activity UI (`ActivityConfiguration`) must be declared in a
`@main WidgetBundle` inside a **Widget Extension** target. Creating an Xcode
target by editing `project.pbxproj` from text tools is fragile and high-blast-
radius — and the pbxproj already carries uncommitted user changes. So target
creation is left to Xcode.

## Manual Xcode steps

1. **File → New → Target → Widget Extension.**
   - Product name e.g. `SpektoWatchLiveActivity`.
   - **Check "Include Live Activity".** Uncheck "Include Configuration
     Intent" unless you want a configurable home-screen widget too.
   - Embed in the `SpektoWatch2` app target.
2. **Replace the generated widget source** with
   `SpektoWatchLiveActivity/MeasurementLiveActivityWidget.swift` (already
   written). Either move that file into the new target's group or add it to
   the target's membership.
3. **Add the shared attributes to the extension target:** add
   `Shared/MeasurementActivityAttributes.swift` to the extension's target
   membership (File Inspector → Target Membership). It is already compiled
   into the app; the extension needs the same type.
4. **Confirm the extension's generated `WidgetBundle`** lists
   `MeasurementLiveActivityWidget()`.
5. **Info.plist:** the extension's Info.plist must have
   `NSSupportsLiveActivities = YES` (the Widget Extension template usually
   sets this on the host app; the app target already has the build setting).
6. Build the app scheme; confirm the `.appex` embeds and code-signs.

## On-device acceptance (hardware)

1. Install on a device (iPhone with Dynamic Island for the full experience;
   any iOS 16.1+ device for the Lock Screen banner).
2. Start a measurement/recording. Confirm:
   - Live Activity appears on the Lock Screen with live dB(weighting) + peak.
   - Dynamic Island compact shows the level; expanded shows level + elapsed
     timer + peak + recording state.
   - Level/peak update roughly once per second (1 Hz throttle).
   - Elapsed timer counts up smoothly without per-second pushes.
3. Stop the recording → activity ends and disappears.
4. Background the app mid-recording → activity persists and keeps updating
   while the audio session is alive.
5. Confirm no "budget exhausted" / ActivityKit errors in the device console.

## Acceptance

- Live Activity renders and updates on device per the checklist above.
- `Activity.request` no longer logs "no UI to render"–class failures.
- Promote M20 to completed once the on-device checklist passes.
