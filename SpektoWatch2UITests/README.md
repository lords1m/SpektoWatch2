# SpektoWatch2UITests

UI test target for SpektoWatch2. Produces labeled PNG screenshots attached to the
xcresult bundle and exportable by `agent/scripts/capture-screenshots.py`.

## Launch arguments

| Argument | Value | Effect |
|---|---|---|
| `-SeedTestData` | `YES` | Seeds pre-built recordings into the app so screenshot tests don't need a live microphone. |
| `-SeedRecordingState` | `running` | (Future) Seeds the recording-in-progress state for live-meter screenshots. |
| `-UIAnimationsDisabled` | `YES` | Disables UIKit animations for faster, deterministic screenshots. |
| `-ResetState` | `YES` | Clears any persisted state before launch. |
| `-SnapshotCatalog` | `YES` | Activates the full screenshot catalog path in `ScreenshotCatalogTests`. |

## Screenshot tests

| File | Coverage |
|---|---|
| `ScreenshotCatalogTests.swift` | Full dashboard catalog: default, edit, widget settings, widget picker, app settings, recordings list, recording detail, layouts, empty dashboard (~12 shots) |
| `RecordingFlowScreenshotTests.swift` | Recording lifecycle: idle → start tap → in-progress → stop → recordings list → detail (~5 shots) |
| `ExportFlowScreenshotTests.swift` | Export overlays: PDF, CSV, spectrogram PNG (open + dismiss each; ~6 shots) |
| `WeightingPickerScreenshotTests.swift` | Playback weighting picker: Z → A → C → Z (~4 shots) |
| `WatchAppScreenshotTests.swift` | Watch app states (requires watchOS simulator) |

## Running locally

```sh
xcodebuild test \
  -scheme SpektoWatch2 \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -resultBundlePath ./TestResults/local.xcresult \
  -only-testing:SpektoWatch2UITests
python3 agent/scripts/capture-screenshots.py \
  --xcresult ./TestResults/local.xcresult \
  --output ./TestResults/Screenshots
```

## Xcode Cloud

Screenshots are uploaded as build artifacts by `ci_scripts/ci_post_xcodebuild.sh`.
To enable:
1. In the Xcode Cloud workflow editor, ensure the **Test** action includes the
   `SpektoWatch2UITests` target (or the full `SpektoWatch2` scheme with the
   test plan enabled).
2. After a successful run, find "Screenshots" under **Build Artifacts** in the
   Xcode Cloud build report.

See `ci_scripts/ci_post_xcodebuild.sh` for the extraction command.
