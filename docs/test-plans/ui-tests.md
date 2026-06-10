# Test plan: UI tests

`SpektoWatch2UITests` produces labeled PNG screenshots attached to the xcresult bundle and exportable by `agent/scripts/capture-screenshots.py`.

For **Point-Free snapshot baselines** (PDF layout/copy regression), see [snapshot-testing.md](snapshot-testing.md) and the **snapshots** test plan (`TestPlans/snapshots.xctestplan`).

## Xcode test plan

- **File:** `TestPlans/ui-tests.xctestplan`
- **xcodebuild:** `-testPlan ui-tests`
- **Targets:** `SpektoWatch2UITests` only (used by the `SpektoWatch2UITests` scheme and as an alternate plan on `SpektoWatch2`)

## Launch arguments

| Argument | Value | Effect |
|---|---|---|
| `-SeedTestData` | `YES` | Seeds pre-built recordings into the app so screenshot tests don't need a live microphone. |
| `-UIAnimationsDisabled` | `YES` | Passed by screenshot tests for future deterministic-animation handling. The app does not currently consume it. |
| `-ResetState` | `YES` | Clears any persisted state before launch. |
| `-SnapshotCatalog` | `YES` | Reserved screenshot-catalog marker. The app does not currently consume it. |

## Screenshot tests

| File | Coverage |
|---|---|
| `ScreenshotCatalogTests.swift` | Full dashboard catalog: default, edit, widget settings, widget picker, app settings, recordings list, recording detail, layouts, empty dashboard (~12 shots) |
| `RecordingFlowScreenshotTests.swift` | Recording lifecycle: idle → start tap → in-progress → stop → recordings list → detail (~5 shots) |
| `ExportFlowScreenshotTests.swift` | Export overlays: PDF, CSV, spectrogram PNG (open + dismiss each; ~6 shots) |
| `WeightingPickerScreenshotTests.swift` | Playback weighting picker: Z → A → C → Z (~4 shots) |
| `WidgetGridScreenshotTests.swift` | Widget-size grid pages and allowed widget dimensions |
| `WatchAppScreenshotTests.swift` | Watch app states (requires watchOS simulator) |

## Running locally

```sh
xcodebuild test \
  -scheme SpektoWatch2 \
  -testPlan ui-tests \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -resultBundlePath ./TestResults/local.xcresult
python3 agent/scripts/capture-screenshots.py \
  --xcresult ./TestResults/local.xcresult \
  --output ./TestResults/Screenshots
```

## Xcode Cloud

Screenshots are uploaded as build artifacts by `ci_scripts/ci_post_xcodebuild.sh`.

1. In the Xcode Cloud workflow editor, ensure the **Test** action includes `SpektoWatch2UITests` (or the `SpektoWatch2` scheme with the **spekto-watch2** test plan).
2. After a successful run, find "Screenshots" under **Build Artifacts** in the Xcode Cloud build report.

See `ci_scripts/ci_post_xcodebuild.sh` for the extraction command.
