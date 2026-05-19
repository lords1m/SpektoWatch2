# Task 10: Acceptance

Status: completed
Created: 2026-05-18
Updated: 2026-05-19
Milestone: `milestone-6-code-audit-remediation`

## Result

Handoff report produced at `agent/reports/2026-05-19-milestone-6-acceptance.md`. Full coverage table for all 44 audit findings included there.

## Coverage tally

- **Landed in code:** 32 findings
- **Partial** (code-side complete, remainder is structural / Xcode UI / coordinated cross-target): 3 (`#12`, `#26`, `#28`)
- **Deferred** with explicit rationale: 4 (`#8`, `#11`, `#13`, `#14`)
- **Verification reversal** (audit claim did not survive verification): 5 (`#1`, `#2`, `#22`, `#30`, `#41`)

`32 + 3 + 4 + 5 = 44` ✓

## Negative checks (run)

- `grep -E "fatalError|try!|as!"` on M6 diff: no new occurrences introduced.
- `grep -rn "UserDefaults.standard" "SpektoWatch Complications/"`: only in a historical-note comment; no live cross-process default reads.
- `grep -rn "vDSP_DFT_zop"`: only in `WatchAudioEngine.swift:71` — intentional (audit `#1` verification reversal).

## Manual hardware acceptance — outstanding

The milestone-level acceptance criteria from `milestone-6-code-audit-remediation.md` require Apple Watch hardware paired with a development iPhone. The agent cannot run these. The list is reproduced in the handoff report under "Manual hardware acceptance".

## Pending Xcode-side work (outstanding)

App Group entitlement for Task 4 (`#26`) — see handoff report "Outstanding manual work".

## Follow-up backlog

Logged in the handoff report under "Follow-up tasklist". Candidates for a future M7 or the next planning cycle:

- DSP: window ENBW correction + calibration migration (`#11`).
- WatchConnectivity: format-version byte + A/C in payload (`#8`, `#12`); consolidation decision (`#13`).
- Metal: structural fix for the GPU/CPU texture race in `HighEndSpectrogramAdapter` (`#28`).
- iOS UI: `DashboardViewModel` granularity (`#30`).
- Bonus RT-safety cleanups discovered during M6: `widgetSpectralWeightingsLock`, `phaseLock`, `snapshotLock`.
- Product locale decision for CSV (`#14`).

## Objective

Confirm every audit finding is either fixed or explicitly deferred,
produce a handoff report, and validate the milestone-level acceptance
criteria from `agent/milestones/milestone-6-code-audit-remediation.md`.

## Scope

1. **Trace every audit reference.** For each of the 44 issues identified
   in the 2026-05-18 review, confirm the corresponding task file lists
   it under "Audit References" and the fix has landed (or a deferral
   rationale is in the task notes). Produce a coverage table in the
   handoff report.

2. **Run the milestone-level verification list** from
   `milestone-6-code-audit-remediation.md` → "Manual Acceptance":
   - Phone/watch SPL parity (±0.5 dB on 1 kHz tone).
   - Complication updates during a 5-minute session.
   - Crash-mid-recording → reopen → correct duration.
   - Reinstall app → previously saved recordings still playable.
   - Watch background → audio engine stops within 5 s.

3. **Regression sweep.** Re-run the SpektoWatch2 + SpektoWatchTests +
   IntegrationTests test plans on Xcode Cloud (local simulator is
   broken). Record results in the handoff.

4. **Negative checks:**
   - `git grep -nE '(fatalError|try!|as!)'` over `SpektoWatch2/` and
     `Shared/` shows no new occurrences introduced by this milestone.
   - `grep -rn "UserDefaults.standard" "SpektoWatch Complications/"`
     returns no app↔extension boundary crossings.
   - `grep -rn "vDSP_DFT_zop_CreateSetup"` returns no matches.

5. **Write the handoff report** under
   `agent/reports/milestone-6-handoff.md` with: fixes landed, fixes
   deferred (with rationale), known limitations, and follow-up
   recommendations (e.g. schema-version field for the recording binary
   format).

6. **Update `agent/progress.yaml`** — mark M6 as `completed`, set
   `current_milestone` and `current_task` to await the next request.

## Out of Scope

- Starting any new feature work.
- Schema migration of the recording binary format.
- Adopting Swift 6 strict concurrency project-wide.

## Acceptance

- All 10 tasks in M6 are status `completed`.
- Handoff report exists at `agent/reports/milestone-6-handoff.md`.
- Coverage table accounts for all 44 audit references.
- `progress.yaml` reflects M6 completion.
