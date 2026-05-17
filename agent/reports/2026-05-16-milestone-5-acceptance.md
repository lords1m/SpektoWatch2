# Milestone 5 Handoff: Watch Complications

Date: 2026-05-16  
Branch: main  
Milestone: `milestone-5-watch-complications`  
Status: completed

## Summary

All four milestone tasks are complete. The watch app now embeds a WidgetKit
extension named `SpektoWatch Complications` with circular, rectangular, and
inline level complications. Incoming compact watch live data updates the
complication defaults and reloads all three widget timelines at most once per
second.

## Files Changed

**New production files:**

- `SpektoWatch Complications/Info.plist` — explicit WidgetKit extension
  `NSExtension` metadata.
- `SpektoWatch Complications/WatchComplicationWidget.swift` — three WidgetKit
  widget configurations for circular, rectangular, and inline families.

**Modified production files:**

- `SpektoWatch2.xcodeproj/project.pbxproj`
  - Added `SpektoWatch Complications` app-extension target.
  - Added file-system synchronized group and product reference.
  - Embedded the `.appex` in `SpektoWatch Watch App`.
- `SpektoWatch Complications/SpektoWatchComplications.swift`
  - Reduced to the `@main` widget bundle entry point.
- `SpektoWatch Complications/WatchComplicationProvider.swift`
  - Reads placeholder/live level state from `UserDefaults.standard`.
- `Shared/WatchConnectivityManager.swift`
  - Stores the latest `LAF`/broadband level for complications.
  - Calls `WidgetCenter.shared.reloadTimelines(ofKind:)` for all three widget
    kinds, throttled to at most once per second.
- `SpektoWatch2/WatchConnectivityManager.swift`
  - Applies the same watchOS complication state updates in the connectivity
    manager compiled by the active watch app target.
- `SpektoWatch-Watch-App-Info.plist`
  - Added the watch microphone usage string used by the active watch app target.

## Verification

- `plutil -lint SpektoWatch Complications/Info.plist SpektoWatch2.xcodeproj/project.pbxproj` — passed.
- `xcodebuild build-for-testing -project SpektoWatch2.xcodeproj -scheme "SpektoWatch Watch App" -destination "generic/platform=watchOS"` — passed.
- `xcodebuild test -project SpektoWatch2.xcodeproj -scheme SpektoWatchTests -destination "platform=watchOS Simulator,id=5206C2E7-A62F-437B-9889-743C73C91D10"` — passed, 56 tests.

Result bundle:
`/Users/simeonbrandt/Library/Developer/Xcode/DerivedData/SpektoWatch2-bmheciywsslsgvbiwjpygnlqhyzq/Logs/Test/Test-SpektoWatchTests-2026.05.16_13-37-42-+0200.xcresult`

## Manual Acceptance Notes

The automated build confirms the `.appex` is embedded and validates as a watchOS
app extension. The following still require Apple Watch hardware or an
interactive paired simulator session:

1. Add the "SpektoWatch" circular, rectangular, and inline complications to a
   watch face.
2. Start live measurement on iPhone.
3. Confirm the complication updates with the current dB value within about two
   seconds.
4. Stop measurement and confirm the last value or placeholder behavior is
   acceptable.

## Known Constraints

- This milestone intentionally avoids App Group provisioning. The provider uses
  standard defaults per the task boundary; if live sharing across the widget
  process proves unreliable on hardware, the next iteration should add an App
  Group entitlement and shared defaults suite.
- The watch simulator logs expected audio-unit warnings for microphone tests,
  but the suite passes.
