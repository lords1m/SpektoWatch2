# Task 1: Compile Gate

Status: completed  
Created: 2026-05-12  
Completed: 2026-05-12  
Milestone: `milestone-3-dashboard-and-recording-polish`

## Objective

Verify that the untracked `WaterfallView.swift` and `WaterfallDataBuilder.swift`
are included in the Xcode project and that a build-for-testing pass succeeds.

## Scope

- Confirm both files are referenced in `SpektoWatch2.xcodeproj`.
- Run `xcodebuild build-for-testing` and record the result.
- Document any compile errors and fix them before proceeding to later tasks.

## Acceptance

- `TEST BUILD SUCCEEDED` (or failures are triaged with file references).
- Both Waterfall files are tracked in the project (not just untracked on disk).

## Steps

```sh
# Check project membership
grep -r "WaterfallView\|WaterfallDataBuilder" SpektoWatch2.xcodeproj/

# Build gate
xcodebuild build-for-testing \
  -project SpektoWatch2.xcodeproj \
  -scheme SpektoWatch2 \
  -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" \
  2>&1 | tail -20
```

## Non-Goals

- Do not change any application logic in this task.
