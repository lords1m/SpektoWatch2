# Task 3: Live Data Integration

Status: not_started  
Created: 2026-05-14  
Milestone: `milestone-5-watch-complications`

## Objective

Make complications update in response to incoming live measurement data by
calling `WidgetCenter.shared.reloadTimelines(ofKind:)` from
`WatchConnectivityManager`, throttled to at most once per second.

## Scope

- Import `WidgetKit` in `WatchConnectivityManager.swift`.
- Add a `lastComplicationReload: Date` property initialized to `.distantPast`.
- In the handler that receives live measurement data from the phone, after
  updating published state, check if at least 1 second has elapsed since
  `lastComplicationReload` and call
  `WidgetCenter.shared.reloadTimelines(ofKind: "SpektoWatchLevelComplication")`.
- The provider must read the `lastKnownLevel` from `UserDefaults(suiteName:)`
  shared between the watch app and the extension (App Group required if targets
  differ; since we embed the extension in the watch app, a shared defaults key
  in the watch app's container is sufficient at this milestone).

## Shared State Strategy

Rather than an App Group (which requires provisioning portal changes), the
provider reads from a `UserDefaults` file written by the watch app in its
documents/library directory, or uses the simpler approach: the provider uses a
`@AppStorage`-compatible key that the watch app writes via `UserDefaults.standard`
and the extension reads.

## Acceptance

- A live measurement value update from the phone triggers a timeline reload
  within 2 seconds.
- The complication shows the new value within the next natural refresh window.
- `WatchConnectivityManager` unit tests still pass.

## Non-Goals

- No App Group entitlement configuration — use `UserDefaults.standard` in the
  watch app scope or accept placeholder-only complications for this milestone if
  App Group provisioning is blocked.
- No background refresh scheduling beyond `reloadTimelines`.
