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

## Watch unit tests

**File:** `TestPlans/watch-tests.xctestplan`  
**xcodebuild:** `-testPlan watch-tests` (default on schemes `SpektoWatchTests` and `SpektoWatch Watch App`)

Target: `SpektoWatchTests` (not parallelized).

```sh
xcodebuild test \
  -project SpektoWatch2.xcodeproj \
  -scheme SpektoWatchTests \
  -testPlan watch-tests \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'
```

## Scheme ↔ plan mapping

| Scheme | Test plans (default first) |
|---|---|
| `SpektoWatch2` | `spekto-watch2`, `ui-tests`, `snapshots` |
| `SpektoWatch2UITests` | `ui-tests` |
| `SpektoWatchTests` | `watch-tests` |
| `SpektoWatch Watch App` | `watch-tests` |

The plans list the test targets; the schemes carry no separate `Testables`.
