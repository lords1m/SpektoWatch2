# Task 2: Split RecordingDetailView

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-13-architecture-hygiene`
Source finding: A6 in `2026-05-21-architecture-review.md`
Depends on: task-1.

## Goal

Split `SpektoWatch2/Views/RecordingDetailView.swift` (1496 LOC,
5 features in one file) into a coordinator + per-feature subviews.

## Landed (2026-05-21) — Phase 1: standalone helpers extracted

Three self-contained helper types extracted from
`RecordingDetailView.swift`. Each shares no state with the main
view, so the extraction is purely mechanical and zero-risk:

- `SpektoWatch2/Views/RecordingDetailComponents.swift` — new
  (96 LOC). Contains `MiniLineChart` + `StatRow`.
- `SpektoWatch2/Views/AudioPlayerManager.swift` — new (161 LOC).
  `AVAudioEngine`-backed playback for the detail view's
  transport.
- `SpektoWatch2/Views/PhotoPickerView.swift` — new (39 LOC).
  `PHPickerViewController` wrapper.

`RecordingDetailView.swift` dropped from **1496 LOC → 1211 LOC**
(–285). The remaining file structure:
- Lines 1-274  — struct definition + state + body
- Lines 275-790 — tab-content cards (overview / analysis /
  waterfall)
- Lines 791-964 — actions (export, share, photo trigger)
- Lines 965-1166 — helpers (data loading, derived values)
- Lines 1176+ — private `ExportActionButton` (kept; only used
  by this file)

## Deferred — Phase 2: per-tab card split (not landed)

The original task scope called for splitting the cards into
`RecordingPlaybackSection`, `RecordingMarkersSection`,
`RecordingExportSection`, `RecordingNotesSection`,
`RecordingMetadataSection` — each ≤ 300 LOC.

That step is **deferred** in this milestone for two reasons:

1. **Shared state graph.** The main view holds 29+ `@State` /
   `@StateObject` properties that span all three tabs (e.g.
   `spectrogramHistory`, `playbackWidgets`, `recording` itself).
   A clean per-tab split needs a `RecordingDetailViewModel`
   ObservableObject to host the shared state, with each section
   reading the subset it needs. That's a non-trivial refactor and
   is exactly the kind of change that can silently regress the
   waveform / marker / export flows without a hardware acceptance
   pass.
2. **Risk vs. M13 budget.** Phase 1 already removes the file's
   highest-LOC offenders (`AudioPlayerManager` alone is 161 LOC of
   AVFoundation glue) with zero risk. Phase 2's wins are
   compile-time + reviewability — real but lower priority than
   the AudioEngine decomposition that follows (tasks 3-5).

Recommended timing for Phase 2: after M13 task-4
(`LiveAcousticState` extract) — the
`RecordingDetailViewModel` would be a natural consumer of the
new live-state child object pattern.

## Validation

- `xcodebuild -scheme SpektoWatch2 -destination 'generic/platform=
  iOS Simulator' build` → `** BUILD SUCCEEDED **`.
- No consumer of any extracted type was touched (existing
  `MiniLineChart` / `StatRow` / `AudioPlayerManager` / `PhotoPickerView`
  call sites in `RecordingDetailView.swift` keep working with the
  extracted definitions).
- Hardware functional acceptance gated on M13 task-9.

## Acceptance status

- [x] Three standalone helper files exist; each ≤ 200 LOC.
- [ ] RecordingDetailView.swift ≤ 300 LOC — **not met**. Currently
  1211 LOC. Achieving ≤ 300 requires Phase 2 (deferred).
- [x] `RecordingDetailView` body semantics unchanged.
- [x] iOS build green.
- [ ] Existing snapshot tests still pass — code-side OK; can't
  run locally per AGENT.md. Gated on Xcode Cloud / hardware.

Task stays `in_progress` until Phase 2 lands (or until acceptance
is renegotiated with the user to accept Phase 1 as sufficient).
