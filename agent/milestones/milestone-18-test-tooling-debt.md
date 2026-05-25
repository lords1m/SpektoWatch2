# Milestone 18: Test & Tooling Debt + UI Screenshot Coverage

Status: in_progress
Created: 2026-05-25
Priority: medium
Estimated: 1.5 weeks

## Goal

Close two intersecting tracks:

**Track A — Test-debt fixes** from the 2026-05-24 multi-agent code-review
synthesis (`agent/reports/2026-05-24-code-review-synthesis.md` §TT). Eight
broken / false-positive / fragile tests and five new coverage gaps. Today
several test acceptance claims in M15 / M16 / M17 acceptance reports rest on
tests that either don't compile in the target, swallow failures silently, or
race their own assertions.

**Track B — UI screenshot coverage** (new, requested 2026-05-25). The
existing `ScreenshotCatalogTests.capture()` helper proves the pattern:
`XCUIScreen.main.screenshot()` → `XCTAttachment(...).lifetime = .keepAlways`
plus a temp-dir PNG sidecar. Today it lives in one test file only. Promote
to a shared base / extension so **every** UI test the suite touches
produces named screenshots automatically, surfaced in both local
`xcresult` bundles and Xcode Cloud build reports.

Binary acceptance:

1. **No false-positive cancellation tests.** TT-2 and TT-3 fixed — the
   tests reliably observe `CancellationError` on fast hosts and surface
   unexpected errors as `XCTFail`.
2. **Test fixtures and teardown are robust.** TT-4 / TT-7 / TT-8 +
   coverage gaps 3 + 4 closed. No `try!` in test fixture creation, no
   `Float.random` in deterministic assertions, no `fatalError`-vulnerable
   backup/restore in test bodies, no shared-Documents pollution between
   parallel runs.
3. **No `Thread.sleep` on the main runloop in tests.** TT-9 closed.
   `WatchDSPParityTests` covers the production `performVisualDCT`
   function directly (coverage gap 5).
4. **`acp-validate` covers M6–M17 acceptance records** (TT-5 + coverage
   gap 1) — deleting any milestone task record fails validation.
5. **`capture-screenshots.py` tolerates non-legacy `xcresult` format**
   (TT-6) and has unit-test coverage (coverage gap 2).
6. **A shared `UITestCase` (or `XCTestCase` extension) exposes
   `capture(_:)`.** Every UI-test file uses it; screenshots appear as
   `XCTAttachment` entries in `xcresult` bundles, named by device +
   screen, with `.keepAlways` lifetime.
7. **Initial UI screenshot coverage** expands beyond `ScreenshotCatalog`
   to: recording lifecycle, export flow, weighting picker, watch face
   carousel (where reachable from iOS simulator).
8. **Xcode Cloud artifact pipeline** exports the `xcresult` bundle (or
   a derived PNG zip) as a downloadable build artifact. Local
   invocation documented in `agent/scripts/capture-screenshots.py`'s
   header.

## Why now

M15 / M16 / M17 acceptance reports cite tests that may not be running or
may pass for the wrong reasons. M18 makes those acceptance claims
verifiable. Track B was explicitly requested 2026-05-25 — folded in here
because the UI tests are a natural extension of the screenshot helper
that already exists in this target, and shipping the test-debt fixes
without screenshot expansion would leave the regression-detection story
half-built.

## Non-goals

- Snapshot-test (PDF-output) coverage — that's M7 (Xcode Cloud Snapshot
  Testing) and remains parked behind its own RECORD_SNAPSHOTS=YES
  baseline run.
- Backlog items PE-5…PE-8.
- Hardware-only acceptance pending from M15 / M16 / M17 — those still
  require paired-device runs.
- Adding a UI Testing Bundle target — one already exists
  (`SpektoWatch2UITests`).

## Tasks

1. task-1-cancellation-race-fix — TT-2 (Critical) + TT-3 (High)
2. task-2-test-hygiene — TT-4 (High) + TT-7 (Medium) + TT-8 (Medium) +
   coverage gaps 3, 4
3. task-3-pdf-no-sleep-watch-coverage — TT-9 (Medium) + coverage gap 5
4. task-4-acp-validate-expand — TT-5 (High) + coverage gap 1
5. task-5-screenshots-py-robustness — TT-6 (High) + coverage gap 2
6. task-6-shared-screenshot-helper — promote `capture()` to a reusable
   `UITestCase` / `XCTestCase` extension
7. task-7-expand-ui-test-screenshots — initial coverage across
   recording lifecycle, export, weighting picker, plus auto-capture on
   every test-step anchor
8. task-8-xcode-cloud-screenshot-artifacts — ensure `xcresult`
   attachments surface in Xcode Cloud + local docs
9. task-9-acceptance — verdicts + cross-cut checks

Source: `agent/reports/2026-05-24-code-review-synthesis.md`
