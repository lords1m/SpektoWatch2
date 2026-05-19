# Milestone 6: Code Audit Remediation

Status: completed (code); manual hardware acceptance + Xcode entitlement wiring outstanding
Created: 2026-05-18
Completed (code): 2026-05-19
Handoff: agent/reports/2026-05-19-milestone-6-acceptance.md
Source design: `agent/design/spektowatch-field-engineering-design.md`
Source review: full-codebase review conducted 2026-05-18 (parallel reviewer agents over DSP, WatchConnectivity, recording/persistence, iOS UI, watchOS+complications)

## Goal

Resolve the 44 issues surfaced by the 2026-05-18 codebase audit before any
further feature work. The audit identified five ship-stopper classes:

1. Watch and iPhone produce different SPL readings for the same stimulus
   (FFT setup mismatch + LAF exponent error) — the field-engineering trust
   model from the active design is compromised.
2. WatchConnectivity floods at FFT framerate with no error handling, and the
   watch complication has never actually displayed live data (extension reads
   the wrong `UserDefaults` instance).
3. Recording on-disk format can leave the header lying about frame count after
   a crash; metadata writes in a parallel dead-code path are non-atomic.
4. Spectrogram view uses an `MTLTexture` from a background queue while the
   main thread reads it without synchronization; another path can `fatalError`
   on Metal pipeline failure.
5. Watch audio engine never stops when the app backgrounds, draining battery
   beyond the WKExtendedRuntimeSession window.

Until these are fixed, the app cannot honor the "field engineering tool" trust
positioning from the design, regardless of UI polish.

## Completion Criteria

- All Critical and High findings (#1–#18, #26–#38) addressed in code, with
  per-fix verification notes captured in the corresponding task file.
- All Medium findings (#19–#25, #39–#44) either fixed or explicitly deferred
  with rationale recorded in the task file.
- The two duplicated managers are consolidated: a single `RecordingManager`
  type and a single `WatchConnectivityManager` implementation across targets.
- Watch and iPhone produce SPL readings within ±0.5 dB for the same stimulus
  on the same physical environment (manual verification on hardware).
- WatchConnectivity spectrogram send path is coalesced and self-throttling;
  no `sendMessageData` is invoked at audio framerate.
- Complication target reads from an App Group `UserDefaults(suiteName:)`
  shared with the watch app (overriding the M5 acceptance of the standard-
  defaults shortcut, which is now known to break the feature).
- `git grep -nE '(fatalError|try!|as!)'` over SpektoWatch2/ and Shared/ shows
  no new regressions introduced by this milestone.
- Dead files identified by the audit are removed from the Xcode project.

## Manual Acceptance

Tests cannot be run in the local simulator (broken); acceptance for DSP,
WatchConnectivity, and the complication requires Apple Watch hardware paired
with a development iPhone:

1. Play a calibrated 1 kHz tone at a fixed acoustic level into both the iPhone
   and the paired Apple Watch. Confirm reported LAeq values match within
   ±0.5 dB across at least 30 seconds.
2. Start a measurement on the iPhone for 5 minutes. Confirm the watch
   complication updates within 60 s of each meaningful level change, and that
   the system never silently stops refreshing (check Console for budget
   warnings).
3. Start a recording, then force-quit the app mid-recording. Reopen the app,
   open the recording. Confirm it loads without throwing `ioFailure` and
   reports the correct duration.
4. Reinstall the app from Xcode after creating recordings. Confirm previously
   saved recordings remain playable.
5. Lower wrist / background the watch app during an active measurement.
   Confirm the watch audio engine stops within 5 s (verified via Console
   logs or battery telemetry).

## Explicit Non-Goals

- No new features, widgets, or user-facing surfaces in this milestone.
- No external calibrated microphone work (separate future milestone).
- No masking polish (separate future milestone).
- No design system refresh.
- No CSV format change beyond locale correctness.

## Future Milestones

- External calibrated microphone & formal compliance workflow.
- Polished masking workflow and reusable masking profiles.
- Smart Stack interactive widget with level trend.

## Tasks

Ordered by risk (data-loss & correctness → concurrency/perf → cleanup):

- `agent/tasks/milestone-6-code-audit-remediation/task-1-dsp-correctness.md`
- `agent/tasks/milestone-6-code-audit-remediation/task-2-recording-persistence-integrity.md`
- `agent/tasks/milestone-6-code-audit-remediation/task-3-watchconnectivity-consolidation.md`
- `agent/tasks/milestone-6-code-audit-remediation/task-4-complication-app-group.md`
- `agent/tasks/milestone-6-code-audit-remediation/task-5-spectrogram-metal-threading.md`
- `agent/tasks/milestone-6-code-audit-remediation/task-6-audio-thread-realtime-safety.md`
- `agent/tasks/milestone-6-code-audit-remediation/task-7-watch-lifecycle-and-battery.md`
- `agent/tasks/milestone-6-code-audit-remediation/task-8-ios-ui-state-hygiene.md`
- `agent/tasks/milestone-6-code-audit-remediation/task-9-dead-code-purge.md`
- `agent/tasks/milestone-6-code-audit-remediation/task-10-acceptance.md`
