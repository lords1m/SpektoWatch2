# Snapshot testing restored (2026-06-02)

## What changed

- Restored `SnapshotTestSupport.swift`, `PDFReportSnapshotTests.swift`, and committed baselines under `SpektoWatch2Tests/__Snapshots__/PDFReportSnapshotTests/`.
- Added `TestPlans/snapshots.xctestplan` (unit tests only, pinned `en`/`US`/`light`/`TZ=UTC`, `checkedAllocations` required for Xcode to parse the plan).
- Trimmed SPM: `SnapshotTesting` only on `SpektoWatch2Tests`; removed from `SpektoWatch2UITests`; dropped unused `InlineSnapshotTesting` and `SnapshotTestingCustomDump`.
- Added `agent/scripts/record-snapshots.sh` and `docs/test-plans/snapshot-testing.md`.

## Verify locally

```sh
xcodebuild test \
  -project SpektoWatch2.xcodeproj \
  -scheme SpektoWatch2 \
  -testPlan snapshots \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:SpektoWatch2Tests/PDFReportSnapshotTests \
  CODE_SIGNING_ALLOWED=NO
```

Both PDF snapshot tests passed on 2026-06-02.

## Record baselines

```sh
RECORD_SNAPSHOTS=YES ./agent/scripts/record-snapshots.sh \
  'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Commit updated files under `__Snapshots__/`. Never leave `RECORD_SNAPSHOTS=YES` on the default CI verify workflow.

## Xcode Cloud

Add a **Snapshots** workflow (or configuration) that runs the `Snapshots` test plan on a **fixed** simulator OS. Use `RECORD_SNAPSHOTS=YES` only for intentional baseline refresh runs.

## Follow-ups (M8 / backlog)

- Spectrogram CPU bitmap snapshots (`HighEndSpectrogramAdapter`).
- Watch complication snapshots via `ImageRenderer`.
- Optional: filter `Snapshots` plan to `PDFReportSnapshotTests` only once a valid `selectedTests` schema is confirmed in Xcode UI.
