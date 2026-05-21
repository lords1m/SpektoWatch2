# Task 4: Persistence And Acceptance

Status: pending
Milestone: `milestone-11-tone-generator-piano-input`
Depends on: task-3

## Objective

Persist the optional input mode and validate the full user flow.

## Scope

- Persist input mode and last selected note if widget settings are wired.
- If tone-generator widget settings are still not wired, document that
  limitation and keep state local to the widget.
- Add targeted tests for model and selection behavior.
- Run build and focused tests.

## Acceptance

- App builds.
- Focused tests pass on a working local device/simulator or Xcode Cloud.
- Manual smoke: switch to piano input, select A4, confirm 440 Hz display,
  play tone, switch back to Hz input, use existing slider/presets.
