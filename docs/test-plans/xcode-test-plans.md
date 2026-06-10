# Test plan: Xcode default suite

**File:** `TestPlans/spekto-watch2.xctestplan`  
**xcodebuild:** `-testPlan spekto-watch2` (default on scheme `SpektoWatch2`)

## Targets

- `SpektoWatch2Tests` (not parallelized)
- `SpektoWatch2UITests`

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
