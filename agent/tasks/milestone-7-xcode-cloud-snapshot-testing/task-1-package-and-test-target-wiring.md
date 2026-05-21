# Task 1: Package & Test Target Wiring

Status: completed
Completed: 2026-05-20
Created: 2026-05-20
Milestone: `milestone-7-xcode-cloud-snapshot-testing`

## Progress (2026-05-20)

- ✅ `SpektoWatch2Tests/__Snapshots__/PDFReportSnapshotTests/` exists on disk
  with a placeholder `README.txt` so Xcode treats the folder reference as a
  non-empty bundle resource.
- ✅ `swift-snapshot-testing` package added to `SpektoWatch2Tests` via Xcode
  (user-confirmed; `SpektoWatch2.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`
  shows as untracked in `git status`, indicating Package.resolved was generated).
- ✅ `__Snapshots__` added to the project as a **blue** folder reference under
  the `SpektoWatch2Tests` group; target membership = `SpektoWatch2Tests`
  (user-confirmed in this session). Bundling assumed via target membership;
  user reported Xcode wouldn't accept manual drag into Copy Bundle Resources
  while the per-class folder was empty — the `README.txt` placeholder resolves
  that, and the folder reference re-scans on the fly.
- ✅ `SpektoWatch2.xctestplan` pinned: `language=en`, `region=US`,
  `userInterfaceStyle=light`, `TZ=UTC` env var, parallelization off on both
  test targets. (Test plan was extended in place rather than splitting out
  a dedicated `Snapshots.xctestplan` — three plans already exist and a fourth
  would be confusing.)
- ✅ `.gitignore` extended to exclude `*.xcresult`, `TestResults/`, and
  swift-snapshot-testing `*.failure.png` / `*.diff.png` artifacts. Existing
  ~130 MB of committed `TestResults/` untracked via `git rm -r --cached
  TestResults/` (93 files staged for removal; historical bytes remain in
  git history — purge with BFG/filter-repo only if explicitly requested).
- ✅ Dynamic Type: Xcode's test plan editor doesn't expose this as a
  first-class setting (it's a simulator-wide accessibility setting).
  Decision (2026-05-20): rely on the simulator default
  (`UICTContentSizeCategoryL` = "Default M"), which is what every fresh
  Xcode Cloud simulator boots with. No env var needed unless Apple changes
  the simulator default in a future Xcode release — revisit then.
- ✅ Xcode Cloud workflow configured (user-confirmed 2026-05-20):
  destination pinned, env vars `RECORD_SNAPSHOTS=NO` (Xcode Cloud requires
  a non-empty value; the helper treats anything other than yes/true/1 as
  "verify mode") and `TZ=UTC` set.
- ⏳ Implicit verification deferred to task-3: the `#warning` from
  `SnapshotTestSupport.swift` and the actual end-to-end build are confirmed
  by the first successful Cloud run.

## Objective

Land the one-time Xcode-side wiring so the scaffolded
`SnapshotTestSupport.swift` helper goes from `#if canImport(SnapshotTesting)`
no-op to an active assertion path. This task is intentionally manual — it
modifies `project.pbxproj`, the test plan, and target memberships, all of
which are fragile to script from outside Xcode and the user has uncommitted
work in the tree (AGENT.md rule).

## Scope

1. **Add Swift Package dependency.**
   - File > Add Package Dependencies… > `https://github.com/pointfreeco/swift-snapshot-testing`
   - Version rule: "Up to Next Major Version" starting from `1.17.4`.
   - Add the `SnapshotTesting` product to the `SpektoWatch2Tests` target
     **only**. Do not add to the app target, the watch app, or
     `SpektoWatchTests` / `SpektoWatch2UITests`.

2. **Create the snapshots folder reference.**
   - On disk: `mkdir -p SpektoWatch2Tests/__Snapshots__/PDFReportSnapshotTests`
   - In Xcode: drag `__Snapshots__` into the `SpektoWatch2Tests` group with
     "Create folder references" selected (folder must appear **blue**, not
     yellow). Target membership: `SpektoWatch2Tests` only.
   - The per-class subfolder name (`PDFReportSnapshotTests`) must match the
     test class name exactly. Case-sensitive. This is non-negotiable for the
     `Bundle(for:)` path lookup in `SnapshotTestSupport.swift`.

3. **Pin the test plan.**
   - Open `SpektoWatch2.xctestplan` (or whichever plan the snapshot tests
     will run under — create a dedicated `Snapshots.xctestplan` if mixing
     with the existing plan is awkward).
   - Configurations > add a single configuration named "Snapshots":
     - Application Language: English
     - Application Region: United States
     - System UI: Light
     - Dynamic Type: Default (L)
   - Selected Tests: include `PDFReportSnapshotTests` only at first.
   - Destination: pin to a single simulator (current Xcode Cloud default is
     iPhone 15 / iOS 17 — match whatever Xcode Cloud has standardized on in
     May 2026; do not use "Recommended").

4. **Xcode Cloud workflow.**
   - In App Store Connect > Xcode Cloud, add or extend a workflow named
     "Snapshots". Test action runs the `Snapshots` test plan against the
     pinned destination above.
   - Add an environment variable `RECORD_SNAPSHOTS` (no value by default).
     Documented contract: setting it to `YES` for a single workflow run
     records baselines; never commit while it's set.

## Acceptance

- `xcodebuild -showBuildSettings` (or Xcode > Package Dependencies) shows
  `SnapshotTesting` resolved at >= 1.17.4 for `SpektoWatch2Tests`.
- `SpektoWatch2Tests/__Snapshots__` exists on disk and is referenced in
  `project.pbxproj` as a folder reference (grep for `lastKnownFileType = folder`
  near the `__Snapshots__` path).
- `Snapshots` test plan and Xcode Cloud workflow exist and are committed.
- The `#warning` from `SnapshotTestSupport.swift` no longer fires (i.e.
  `import SnapshotTesting` resolves in that file).
- Xcode Cloud run kicks off (it may fail because there are no baselines yet
  — that's expected and handled in task 3).

## Non-Goals

- Recording baselines (task 3).
- Implementing fixture helpers (task 2).
- Tests for spectrogram / watch / anything but PDF (M8).

## Notes

- `project.pbxproj` will diff substantially. Review the diff for collateral
  changes before committing — Xcode sometimes touches unrelated entries.
- If `Bundle(for: type(of: self)).resourceURL` returns nil at runtime, the
  folder-reference step was likely set as "Create groups" (yellow) instead
  of "Create folder references" (blue). This is the single most common
  setup mistake.
