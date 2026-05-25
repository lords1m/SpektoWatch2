# Task 8: Xcode Cloud Screenshot Artifact Pipeline

Status: pending
Created: 2026-05-25

## Goal

Surface the screenshots produced by the UI-test bundle in both local
runs and Xcode Cloud build reports, with a documented one-command
workflow.

## Source

User request 2026-05-25 (Track B of M18). Builds on task-6 + task-7.

Existing infrastructure:
- `SpektoWatch2.xctestplan` already includes `SpektoWatch2UITests`.
- `agent/scripts/capture-screenshots.py` extracts PNG attachments
  from a `.xcresult` bundle.
- `ci_scripts/ci_pre_xcodebuild.sh` is the Xcode Cloud pre-build hook
  (Apple's convention — `ci_post_xcodebuild.sh` runs post-build).

## Sub-items

- **Sub-1 (Xcode Cloud)**: Add `ci_scripts/ci_post_xcodebuild.sh` that:
  - Locates the latest `.xcresult` under `$CI_DERIVED_DATA_PATH` /
    `$CI_RESULT_BUNDLE_PATH` (use whichever Apple env var ships today).
  - Runs `python3 agent/scripts/capture-screenshots.py <xcresult-path>
    --output $CI_RESULT_BUNDLE_PATH/Screenshots`.
  - Confirms ≥ 1 PNG was produced; emit a CI-visible warning if zero
    (paired with the TT-6 fix from task-5, this catches future format
    drift).
- **Sub-2 (Xcode Cloud)**: Verify the Xcode Cloud workflow runs the
  UI-test bundle. If `SpektoWatch2UITests` is currently excluded from
  the Cloud action, add it. Document the workflow change inline (since
  Xcode Cloud workflow config lives in Apple's web UI, not the repo,
  put the steps in `agent/scripts/README` or similar).
- **Sub-3 (Local)**: Update the docstring at the top of
  `capture-screenshots.py` with a one-command local recipe:
  ```sh
  xcodebuild test \
    -scheme SpektoWatch2 \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    -resultBundlePath ./TestResults/local.xcresult \
    -only-testing:SpektoWatch2UITests
  python3 agent/scripts/capture-screenshots.py ./TestResults/local.xcresult \
    --output ./TestResults/Screenshots
  ```
- **Sub-4**: Add `TestResults/` and `Screenshots/` patterns to
  `.gitignore` if not already present.
- **Sub-5**: Smoke-test the local recipe end-to-end (acknowledging
  AGENT.md says local sim is broken — fall back to documenting the
  recipe verbatim and verifying syntax via `--help` / dry-run).

## Acceptance

- `ci_scripts/ci_post_xcodebuild.sh` exists and is executable.
- Local recipe documented in `capture-screenshots.py` header.
- `.gitignore` covers test artifacts.
- Future Xcode Cloud runs upload screenshots as build artifacts (gated
  on a real Cloud run for full confirmation — flag as hardware-pending).
- iOS UI-test target build green.

## Hardware / Cloud acceptance

- One Xcode Cloud run completes with the UI-test bundle enabled and
  screenshot artifacts visible in the build report. Gated on the user
  triggering a Cloud workflow.

Milestone: `milestone-18-test-tooling-debt`
