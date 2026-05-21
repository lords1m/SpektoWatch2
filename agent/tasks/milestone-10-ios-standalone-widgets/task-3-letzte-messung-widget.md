# "Letzte Messung" Widget (Small)

Status: pending
Created: 2026-05-21
Milestone: `milestone-10-ios-standalone-widgets`

## Scope

Implement the single-recording summary widget. Name, date, duration, LAeq. Reads the most recent entry from the AppGroup-shared recordings store. Reload timeline on recording-finished notification.

## Notes

- App Group entitlement registration in the Developer Portal +
  pbxproj wiring is a hard prerequisite for tasks 2-6. See M6
  task-4 notes — code-side is already in place.
- Local simulator is broken per AGENT.md; verify on hardware or
  via Xcode Cloud.
- Widget extensions have strict memory + execution budgets. Avoid
  any Metal / heavy compute in the widget render path; pre-compute
  in the app and persist via AppGroup.
