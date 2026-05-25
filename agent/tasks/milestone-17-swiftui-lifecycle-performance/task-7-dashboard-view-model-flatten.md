# Task 7: Flatten DashboardViewModel's Nested ObservableObject

Status: completed
Created: 2026-05-25

## Goal

Eliminate the brittle manual `objectWillChange` forwarding from
`DashboardManager` into `DashboardViewModel` by removing the
`@Published` wrapper around `dashboardManager`.

## Source

UI-7 (Medium) — `agent/reports/2026-05-24-code-review-synthesis.md`
lines ~326–332.

File: `SpektoWatch2/DashboardViewModel.swift` line ~7.

## Sub-items

- **Sub-1**: Change `@Published var dashboardManager = DashboardManager()`
  to `let dashboardManager: DashboardManager` (or take it via init
  injection from `AppServices`).
- **Sub-2**: Remove the manual `objectWillChange` forwarding
  subscription if one exists.
- **Sub-3**: Audit consumers. SwiftUI views observing
  `viewModel.dashboardManager.<published-property>` may need to be
  rewritten as `@ObservedObject var dashboardManager = viewModel.dashboardManager`
  or move to `@EnvironmentObject` if `AppServices` already exposes it.
  This is the breaking part — there may be 5–10 sites.
- **Sub-4**: If full consumer migration is too broad for a single
  task, scope this to: (a) flatten the declaration in
  `DashboardViewModel`, and (b) add `@ObservedObject` at the next
  consuming layer only. Document any remaining migration as a
  follow-up.

## Acceptance

- `DashboardViewModel.dashboardManager` is no longer `@Published`.
- All consumers compile and re-render correctly on
  `DashboardManager.@Published` changes.
- iOS build green.

## Risk note

This is the broadest task in M17. If migration scope exceeds a
single session, split into Phase 1 (flatten + nearest consumer) and
Phase 2 (deep consumer migration). The other tasks (1–6) are
independent and can land first.

Milestone: `milestone-17-swiftui-lifecycle-performance`
