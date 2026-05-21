# Task 3: Record & Commit Baselines

Status: pending
Created: 2026-05-20
Milestone: `milestone-7-xcode-cloud-snapshot-testing`
Depends on: task-1, task-2

## Objective

Capture the first set of snapshot baselines under Xcode Cloud (the only
viable test environment) and commit them so subsequent runs verify against
them.

## Scope

1. **One-shot record run.**
   - In App Store Connect > Xcode Cloud > Snapshots workflow, set
     `RECORD_SNAPSHOTS = YES`.
   - Trigger a run on the M7 branch.
   - `ciAssertSnapshot` will see record mode is on and re-record everything
     in the bundled `__Snapshots__/PDFReportSnapshotTests/` directory.
   - The run will report failures (snapshot-testing always fails on record
     mode runs — that is the contract).

2. **Retrieve baselines.**
   - Download the result bundle from the Xcode Cloud run.
   - Extract the freshly recorded PNG and `.lines` files from the bundle's
     attachments and copy them into the local working tree under
     `SpektoWatch2Tests/__Snapshots__/PDFReportSnapshotTests/`.
   - Alternative: re-record locally on a developer machine that uses the
     exact same pinned simulator from the test plan. Acceptable only if
     the local result matches the Cloud renderer byte-for-byte at the
     chosen `perceptualPrecision` floor; verify with a second Cloud run.

3. **Commit and clear record flag.**
   - Commit the new baseline files. Verify the file count matches the
     number of `ciAssertSnapshot` calls in `PDFReportSnapshotTests`.
   - Set `RECORD_SNAPSHOTS` back to empty (or remove the env var override
     entirely for the default workflow).

4. **Second run.**
   - Trigger a second Xcode Cloud run with no code or baseline changes.
   - All snapshot tests pass.

## Acceptance

- `SpektoWatch2Tests/__Snapshots__/PDFReportSnapshotTests/` contains at
  least two baseline files (one `.png`, one `.lines.txt` or similar) and
  they are tracked in git.
- Xcode Cloud "Snapshots" workflow runs green on the M7 branch with no
  recording.
- A third run, triggered after a deliberate one-character change in the
  PDF report copy, fails on the `.lines` snapshot test as expected.
- A fourth run, after reverting the change, is green again.

## Non-Goals

- Recording snapshots for any subject other than `PDFReportGenerator`.
- Wiring up post-build diff HTML reporting (backlog).

## Notes

- If the first Cloud run records baselines that diff from a developer's
  local run by more than the `perceptualPrecision: 0.98` floor, that
  signals an unpinned input (locale, dynamic type, dark mode, or font
  fallback). Audit the test plan configuration before raising the floor.
- Never let `record: true` reach `main`. Grep CI for `record: true` and
  `RECORD_SNAPSHOTS=YES` in the workflow definition before merging.
