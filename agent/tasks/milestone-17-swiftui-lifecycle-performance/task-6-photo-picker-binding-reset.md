# Task 6: PhotoPickerView isPresented Binding Reset

Status: completed
Created: 2026-05-25

## Goal

Reset the `isPresented` binding when the photo picker is dismissed,
so re-presentation works after the first selection.

## Source

UI-6 (Medium) — `agent/reports/2026-05-24-code-review-synthesis.md`
lines ~319–324.

File: `SpektoWatch2/Views/PhotoPickerView.swift` lines ~27–38.

## Sub-items

- **Sub-1**: Plumb `isPresented: Binding<Bool>` from the SwiftUI
  wrapper into the `PHPickerViewControllerDelegate` coordinator so
  the delegate can clear it.
- **Sub-2**: In the delegate callback
  (`picker(_:didFinishPicking:)`), set `isPresented.wrappedValue = false`
  alongside the existing `picker.dismiss` call.
- **Sub-3**: Confirm cancellation path (user taps Cancel without
  selecting) also reaches `isPresented = false`. PHPickerViewController
  fires `didFinishPicking:` with an empty results array in that case,
  so a single reset covers both.

## Acceptance

- Re-presenting the picker after a selection works.
- iOS build green.
- Manual regression: open photo picker on a recording detail, pick a
  photo, dismiss; reopen the picker — appears every time.

Milestone: `milestone-17-swiftui-lifecycle-performance`
