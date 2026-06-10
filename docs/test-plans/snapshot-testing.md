# Test plan: snapshot testing

Point-Free [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) with a Xcode Cloud–friendly `ciAssertSnapshot` helper (`SpektoWatch2Tests/SnapshotTestSupport.swift`).

## Layout

```
SpektoWatch2Tests/
  SnapshotTestSupport.swift
  PDFReportSnapshotTests.swift
  __Snapshots__/
    PDFReportSnapshotTests/     ← baselines (png + txt); bundled into .xctest
```

## Running

- **Verify (CI / local):** Scheme `SpektoWatch2` → test plan **snapshots** (`TestPlans/snapshots.xctestplan`), or:
  ```sh
  xcodebuild test \
    -project SpektoWatch2.xcodeproj \
    -scheme SpektoWatch2 \
    -testPlan snapshots \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
    -resultBundlePath TestResults/Snapshots.xcresult
  ```
- **Record baselines:** Set `RECORD_SNAPSHOTS=YES` (Xcode Cloud workflow env or shell). Re-run, then commit files under `__Snapshots__/`. Never leave `RECORD_SNAPSHOTS=YES` on the default verify workflow.

  ```sh
  ./agent/scripts/record-snapshots.sh
  ```

## Pins

The **snapshots** test plan fixes `language=en`, `region=US`, `UI=light`, `TZ=UTC`. Image snapshots are sensitive to OS/Xcode; re-record after major SDK upgrades.

## UI screenshots

Full-screen visual catalog lives in `SpektoWatch2UITests` (`UITestScreenshot.swift`) — attachments for human/agent review, not Point-Free diffs. See [ui-tests.md](ui-tests.md).
