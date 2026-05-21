# Task 7: Review Follow-ups

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-12-liquid-glass-redesign`
Depends on: task-2, task-3, task-4

## Goal

Close the remaining bug / fidelity items flagged in the M12 code
review (see commit log around `redesign/liquid-glass`). Issues 1 and
9 were already resolved in the "kernel inside card" follow-up to
task-2.

## Checklist

- [x] **#2 metaText floor.** `WidgetCardView.metaText` filtered with
  `v > -120` — legitimately quiet rooms (~ -100 dB(A)) display, but
  the noise-floor sentinel can slip through under specific weighting
  combinations. Tightened to `v.isFinite && v > -119.5` and added a
  `data.broadbandLevel > -119` precondition so all-quiet frames
  collapse to nil.
- [x] **#3 pencil button a11y.** Added `accessibilityLabel` and
  `accessibilityHint` on the edit-mode toggle in
  `DashboardHeaderView`; the icon-only button now reads as "Layout
  bearbeiten" / "Fertig" to VoiceOver.
- [x] **#4 stable jiggle phase.** `WidgetCardView.jigglePhase`
  switched from `uuidString.hashValue` (per-launch salt) to a stable
  sum over the UUID's `uuid` bytes, so each card keeps the same
  rotation phase across cold launches.
- [x] **#5 Pegelmesser min/max reset.** Watch face resets `minDB` /
  `maxDB` on `audioEngine.isRecording` rising edge — a new
  recording session starts a fresh min/max window. Long-press on
  the readout also resets (haptic feedback on tap).
- [x] **#6 shared peak-bar range constant.** Hardcoded 30-110 dB
  range pulled into a single `PeakBarRange` constant in
  `WatchPegelmesserFace.swift`. Flagged for re-use when M9's level-
  meter audit lands its range fix.
- [ ] **#10 `single` preset 2×2 cluster.** Mock shows a 2×2 tile
  cluster; current 4 × 1×1 widgets flow L→R with a free cell per
  row. **Deferred** — needs a `GridPosition`-aware composer and the
  dashboard grid currently ignores `gridPosition.index` for layout
  (placement is sequential). Pickup with the audit-driven grid
  refactor.
- [ ] **#11 standalone Tweaks affordance.** The dedicated sparkles
  icon was consolidated into the accent Menu's "Mehr Optionen…"
  entry. **Won't fix** — accent is the most-used token; burying
  everything else under one Menu was intentional. Re-add a
  separate icon only if the audit shows users hunting for it.
- [ ] **#7 enumPicker generic constraint** and **#8 OKLCH→sRGB
  drift** were marked Low and stay as-is. **Won't fix** this pass.

## Validation

- iOS build: `xcodebuild -scheme SpektoWatch2 -destination 'generic/
  platform=iOS Simulator' build` → `** BUILD SUCCEEDED **`.
- Watch build: `xcodebuild -scheme "SpektoWatch Watch App"
  -destination 'generic/platform=watchOS Simulator' build` →
  `** BUILD SUCCEEDED **`.
- Hardware visual pass still gated on task-6.
