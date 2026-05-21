# "Recent Recordings" Widget (Medium + Large)

Status: pending
Created: 2026-05-21
Milestone: `milestone-10-ios-standalone-widgets`

## Scope

List of last 3 (Medium) / 5 (Large) recordings with LAeq. Same data source as task-3. Each row a deep-link into the recording detail view.

## Notes

- App Group entitlement registration in the Developer Portal +
  pbxproj wiring is a hard prerequisite for tasks 2-6. See M6
  task-4 notes — code-side is already in place.
- Local simulator is broken per AGENT.md; verify on hardware or
  via Xcode Cloud.
- Widget extensions have strict memory + execution budgets. Avoid
  any Metal / heavy compute in the widget render path; pre-compute
  in the app and persist via AppGroup.
