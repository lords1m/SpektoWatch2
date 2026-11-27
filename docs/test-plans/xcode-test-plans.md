# Test plan: Xcode iOS suite

**File:** `TestPlans/spekto-watch2.xctestplan`  
**xcodebuild:** `-testPlan spekto-watch2` (default on scheme `SpektoWatch2`)

## Targets

- `SpektoWatch2Tests` (not parallelized)
- `SpektoWatch2UITests`

This plan does not run the watchOS unit-test target. Run it separately with the
`SpektoWatchTests` scheme and `TestPlans/watch-tests.xctestplan`:

```sh
xcodebuild test \
  -project SpektoWatch2.xcodeproj \
  -scheme SpektoWatchTests \
  -testPlan watch-tests \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' \
  -resultBundlePath TestResults/watch-tests.xcresult
```

`run_tests.sh` runs this Watch plan after its iOS smoke subset. Override
`DESTINATION_WATCH` when the selected simulator is unavailable.
For Xcode Cloud, configure a separate Test action with the `SpektoWatchTests`
scheme and a watchOS simulator; the Cloud workflow selection is managed outside
this repository.

## Options

- Code coverage on target `SpektoWatch2`
- `language=en`, `region=US`, `userInterfaceStyle=light`, `TZ=UTC`
- Random test order, timeouts enabled, checked allocations on

## Example

```sh
xcodebuild test \
  -project SpektoWatch2.xcodeproj \
  -scheme SpektoWatch2 \
  -testPlan spekto-watch2 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -resultBundlePath TestResults/spekto-watch2.xcresult
```

For snapshot-only or UI-only runs, use [snapshots](snapshot-testing.md) or [ui-tests](ui-tests.md).
