# Task 4: Complication App Group + Watch Info.plist

Status: partial
Created: 2026-05-18
Updated: 2026-05-18
Milestone: `milestone-6-code-audit-remediation`

## Status Summary

| Sub-item | Source finding | Result |
|---|---|---|
| 1. App Group entitlement | Audit #26 (Critical) | PARTIAL — `.entitlements` files + Swift App-Group helper + constants created in code; Xcode `CODE_SIGN_ENTITLEMENTS` wiring + Apple Developer Portal registration are manual follow-ups (see "Required Xcode setup" below) |
| 2. Shared state via App Group suite | Audit #26 (Critical) | **LANDED in code** — `Shared/WatchConnectivityManager.swift`, `SpektoWatch2/WatchConnectivityManager.swift`, and `SpektoWatch Complications/WatchComplicationProvider.swift` all route through `AppGroup.defaults` (= `UserDefaults(suiteName:)` with safe fallback to `.standard` until the entitlement is wired) |
| 3. Remove iOS-only `UIBackgroundModes` from watch plist | Audit #33 (High) | **LANDED** — `SpektoWatch-Watch-App-Info.plist` |
| 4. Complication timeline policy `.never` | Audit #34 (High) | **LANDED** — `SpektoWatch Complications/WatchComplicationProvider.swift:19-24` |

3 of 4 fully landed in code, 1 partial (pending Xcode UI work that cannot be safely done via text edits to `project.pbxproj`).

## What Landed

### New file: `Shared/AppGroup.swift`

Centralized definition of the App Group identifier (`group.BrandtAcoustics.SpektoWatch2.shared`), a `defaults` helper returning `UserDefaults(suiteName: identifier)` with a safe fallback to `UserDefaults.standard`, and the complication shared-state keys (`spw.complication.level`, `spw.complication.weighting`). Until the Xcode entitlement is wired, the fallback path leaves the pre-fix behavior intact (no regression) and the complication continues to show placeholder data — same as before. Once the entitlement is active, the fallback is no longer hit and the complication starts displaying live values.

### New file: `SpektoWatch Watch App/SpektoWatchWatchApp.entitlements`

Declares the App Group membership. Must be wired into the watch app target via Xcode (see below).

### New file: `SpektoWatch Complications/SpektoWatchComplications.entitlements`

Same declaration for the WidgetKit complication extension target.

### `Shared/WatchConnectivityManager.swift` (lines 12-19, 295-301)

`updateComplicationState` writes via `AppGroup.defaults` and `ComplicationSharedKeys`. Removed the private static `complicationLevelKey`/`complicationWeightingKey` since they now live in `Shared/AppGroup.swift`.

### `SpektoWatch2/WatchConnectivityManager.swift` (lines 11-17, 113-117)

Same App-Group routing applied for consistency; under iOS the `#if os(watchOS)` block is dead, but the change keeps the two files structurally aligned for any future cross-target compile.

### `SpektoWatch Complications/WatchComplicationProvider.swift` (rewritten)

- Reads via a local `ComplicationAppGroup` helper that mirrors `Shared/AppGroup.swift`. (Duplication is deliberate: the complications target doesn't currently include `Shared/AppGroup.swift` in its compile sources. The file carries a clear "MUST MATCH Shared/AppGroup.swift" comment and a TODO to remove once the target membership is added in Xcode.)
- Timeline policy: `.after(60s)` → `.never`. The watch-side `WatchConnectivityManager.updateComplicationState` is now the sole reload trigger (throttled to ≥ 60 s per Task 3). The previous timer-based policy doubled budget consumption with no new information.

### `SpektoWatch-Watch-App-Info.plist`

Removed the `UIBackgroundModes` / `audio` entries. `UIBackgroundModes` is iOS-only; on watchOS background audio is managed via `WKExtendedRuntimeSession`. The stray key had no effect and would have raised an App Review red flag.

## Required Xcode setup (manual)

These steps cannot be safely automated by editing `project.pbxproj` from text tools and must be done by a human in Xcode:

1. **In the Apple Developer Portal**:
   - Identifiers → App Groups → register `group.BrandtAcoustics.SpektoWatch2.shared`.
   - Edit the App IDs for both the watch app (`BrandtAcoustics.SpektoWatch2.watchkitapp`) and the complications widget extension. Enable the **App Groups** capability and check the group registered above.
   - Regenerate / re-download the affected provisioning profiles.

2. **In Xcode**:
   - Select the `SpektoWatch Watch App` target → Signing & Capabilities → "+ Capability" → "App Groups" → check `group.BrandtAcoustics.SpektoWatch2.shared`. Xcode should generate / wire `SpektoWatchWatchApp.entitlements` (a skeleton with the correct contents is already in `SpektoWatch Watch App/`; either let Xcode adopt that file, or replace its auto-generated file with that one).
   - Repeat for the `SpektoWatch Complications` target with `SpektoWatchComplications.entitlements`.
   - Optional consolidation: add `Shared/AppGroup.swift` to the `SpektoWatch Complications` target's Compile Sources (Build Phases tab). Then delete the duplicated `ComplicationAppGroup` enum at the top of `SpektoWatch Complications/WatchComplicationProvider.swift` and replace usage with `AppGroup.defaults` + `ComplicationSharedKeys.*`.

3. **Verify** the new `CODE_SIGN_ENTITLEMENTS` build setting for each target points to the corresponding `.entitlements` file.

## Out of Scope (unchanged)

- Adding interactive complication actions (deferred to future Smart Stack milestone).
- Adding new complication families.
- Recording-state complication.

## Verification

Tests cannot be run locally (simulator broken). Verification:

- Build both targets in Xcode after the manual entitlement setup — confirm code-signing succeeds and the App Group ID appears in both `.entitlements` files.
- Manual hardware (paired Apple Watch): add complication to a watch face, start measurement on iPhone, confirm the complication renders a real dB value within 60 s of a level change.
- Manual hardware: walk the watch out of iPhone range, confirm the complication shows the last known value (not "–").
- Console during a 10-minute session: confirm no "widget refresh budget exhausted" warnings.

## Notes

This task is partly an admission that Task 3 of M5 (`agent/tasks/milestone-5-watch-complications/task-3-live-data-integration.md`) shipped a shortcut that didn't actually work. That task explicitly used `UserDefaults.standard` and noted "No App Group entitlement configuration — use UserDefaults.standard in the watch app scope". Widget extensions run in a separate process and have their own `UserDefaults.standard`, so the watch app's writes were never readable by the extension. The complication has likely shown only placeholder data since M5 shipped.

## Audit References

#26 (partial — code landed, entitlement wiring manual), #33 (landed), #34 (landed)

## Objective

Make the watch complication actually display live data. The M5 milestone
shipped on the explicit assumption that `UserDefaults.standard` was
sufficient because the extension is embedded in the watch app — that
assumption is wrong. Widget extensions run in a separate process and have
their own `UserDefaults.standard`. The complication has likely never shown
real data; only the static placeholder.

## Scope

1. **Critical — Add App Group entitlement** — Add a
   `group.com.spektowatch.shared` (or similar — confirm reverse-DNS prefix
   from existing bundle IDs) entitlement to:
   - `SpektoWatch Watch App` target
   - `SpektoWatch Complications` widget extension target
   Update `.entitlements` files; document the group ID in
   `Shared/WatchWidgetConfiguration.swift` as a single constant.

2. **Critical — Route shared state through the App Group suite** —
   `Shared/WatchConnectivityManager.swift:287-299` and
   `SpektoWatch Complications/WatchComplicationProvider.swift:27`.
   Replace every `UserDefaults.standard` access that crosses the
   app↔extension boundary with `UserDefaults(suiteName: appGroupID)`.
   Audit `grep -rn "UserDefaults.standard" SpektoWatch\ Complications/ \
   "SpektoWatch Watch App/" Shared/` to find every site.

3. **High — Remove iOS-only Info.plist key from watch target** —
   `SpektoWatch-Watch-App-Info.plist:8-10`. Delete the `UIBackgroundModes`
   entry (value `audio`) — it has no effect on watchOS and is an App
   Review red flag.

4. **High — Complication timeline reload policy** —
   `SpektoWatch Complications/WatchComplicationProvider.swift:22-24`.
   Change the policy from `.after(Date.now + 60s)` to `.never`. The
   explicit `WidgetCenter.shared.reloadTimelines` path (after the Task 3
   throttle fix) is now the sole driver.

## Out of Scope

- Adding interactive complication actions (deferred to future Smart Stack
  milestone).
- Adding new complication families.
- Recording-state complication.

## Verification

- Manual hardware (paired Apple Watch): add complication to a watch face,
  start measurement on iPhone, confirm the complication renders a real
  dB value within 60 s. Walk the watch out of iPhone range, confirm the
  complication shows the last known value rather than "–".
- Build both targets and confirm code-signing succeeds with the new
  entitlement. Verify the App Group ID appears in both `.entitlements`
  files and matches the constant referenced from code.
- Console: during a 10-minute session, confirm no "widget refresh budget
  exhausted" warnings appear.

## Notes

This task is partly an admission that Task 3 of M5 (`task-3-live-data-
integration.md`) was incorrect. Reference that file from the M6 task
notes for traceability. Do not modify the M5 task file itself — it
represents historical state.

## Audit References

#26, #33, #34
