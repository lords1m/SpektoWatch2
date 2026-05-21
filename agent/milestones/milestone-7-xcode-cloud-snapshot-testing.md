# Milestone 7: Xcode Cloud Snapshot Testing

Status: in_progress
Created: 2026-05-20
Source design: this milestone file (ad-hoc — no separate clarification cycle,
research summary lives in the M7 handoff thread)

## Goal

Stand up a working snapshot-testing pipeline that runs cleanly under Xcode
Cloud — the only viable test environment for this repo (local simulator is
broken per AGENT.md). First subject is `PDFReportGenerator`, chosen because
it is fully deterministic (no GPU, no Metal, no live audio), exercises both
visual layout and copy, and the pipeline was already routed through
`RecordingManager` in M6 task-2.

The library is `pointfreeco/swift-snapshot-testing` (>= 1.17.4). The
integration uses the bundled-resources pattern: snapshot baselines ship as
test-bundle resources, and a project-local `ciAssertSnapshot` helper resolves
the snapshot directory from `Bundle(for:)` on the runner rather than from
`#filePath` (which is baked at build time on a different machine). Research
verified this as the de facto standard — `invia-flights/swift-xcode-cloud-snapshot-testing`
is abandoned and SPM-only, Point-Free upstream has no native Xcode Cloud
support.

The helper and an example test file were scaffolded ahead of this milestone
and are guarded by `#if canImport(SnapshotTesting)`:

- `SpektoWatch2Tests/SnapshotTestSupport.swift`
- `SpektoWatch2Tests/PDFReportSnapshotTests.swift`

This milestone wires the package, fleshes the fixtures, records baselines,
and verifies two green Xcode Cloud runs back-to-back.

## Completion Criteria

- `swift-snapshot-testing` (>= 1.17.4) is a Swift Package dependency of the
  `SpektoWatch2Tests` target only.
- A test-plan configuration exists that pins simulator device, OS, locale,
  region, appearance, and dynamic-type size for snapshot tests.
- `SpektoWatch2Tests/__Snapshots__/PDFReportSnapshotTests/` exists as a
  folder reference (blue folder) in the test target, with committed baseline
  PNG and `.lines` artifacts.
- `PDFReportSnapshotTests` runs without `XCTSkip` and asserts against
  committed baselines (no `record: true` left in tree).
- Two consecutive Xcode Cloud runs pass without re-recording.
- A handoff report documents the workflow, the `RECORD_SNAPSHOTS=YES` env
  var contract, and pointers for adding the next snapshot subjects.

## Manual Acceptance

1. Push the M7 branch to Xcode Cloud.
2. First run completes with all snapshot tests green (after baselines were
   recorded in a prior `RECORD_SNAPSHOTS=YES` run and committed).
3. Re-run the same workflow without code changes; tests stay green.
4. Make a deliberate one-character copy change in `PDFReportGenerator`
   output; confirm the `.lines` snapshot test fails on the next run.
5. Revert the change; confirm green.

## Explicit Non-Goals

- No spectrogram or waterfall image snapshots in this milestone. The
  `HighEndSpectrogramAdapter` CPU bitmap is a strong candidate but defer
  until M8 — it needs a deterministic colormap fixture and the Metal
  threading is freshly hardened (M6 task-5).
- No watch complication snapshots in this milestone. Requires per-family
  `ImageRenderer` paths; defer until M8.
- No S3 / external baseline storage. Repo size is small; in-repo baselines
  are fine.
- No `ci_post_xcodebuild.sh` diff-to-HTML report. Native Xcode Cloud result
  bundle attachments are enough for the first pass.
- No Swift Testing (`@Test`) snapshot integration. The library's Swift
  Testing trait still has the open Xcode Cloud `implementation-only` issue;
  stay on XCTest until upstream resolves discussion #970.

## Future Milestones / Backlog

- M8 candidate: spectrogram CPU bitmap snapshots (`HighEndSpectrogramAdapter`
  data buffer, not the Metal view).
- M8 candidate: watch complication snapshots for the four WidgetKit families
  via `ImageRenderer`.
- Backlog: `ci_post_xcodebuild.sh` that runs `xcresulttool` over the result
  bundle and uploads side-by-side HTML diff reports as build artifacts.
- Backlog: revisit Swift Testing integration once
  `swift-snapshot-testing` discussion #970 (TestScoping / implementation-only
  import) is resolved upstream.
- Backlog: external calibrated microphone compliance workflow (unchanged
  from prior milestones).

## Tasks

- `agent/tasks/milestone-7-xcode-cloud-snapshot-testing/task-1-package-and-test-target-wiring.md`
- `agent/tasks/milestone-7-xcode-cloud-snapshot-testing/task-2-pdf-report-fixture.md`
- `agent/tasks/milestone-7-xcode-cloud-snapshot-testing/task-3-record-and-commit-baselines.md`
- `agent/tasks/milestone-7-xcode-cloud-snapshot-testing/task-4-acceptance.md`
