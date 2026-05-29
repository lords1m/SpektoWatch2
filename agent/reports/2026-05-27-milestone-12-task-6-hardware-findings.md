# Milestone 12 — Task 6 Hardware Acceptance Findings (2026-05-27)

Walking the 8-item M12 task-6 checklist on hardware
(branch `redesign/liquid-glass`, iPhone 12 mini "iPhone SB" +
Apple Watch Series 10 "Apple Watch von Simeon").

Source checklist: `agent/tasks/milestone-12-liquid-glass-redesign/task-6-acceptance.md`.

This document is filled in live as findings come in. Build installed
via `xcrun devicectl device install app` from
`build/DerivedData_Device/Build/Products/Debug-iphoneos/SpektoWatch2.app`
(2026-05-27 14:57 local).

## 1. Cold launch under every theme

For each combination below, cold-launch the app and confirm:
chrome renders cleanly, no overlap, no color bleed, transport bar +
preset rail readable, no missing icons.

| Theme  | Accent    | Status | Notes |
|--------|-----------|:------:|-------|
| Dark   | Phosphor  | ⏳     | (default) |
| Dark   | Amber     | ⏳     |       |
| Dark   | Cyan      | ⏳     |       |
| Dark   | Magenta   | ⏳     |       |
| Dark   | Paper     | ⏳     |       |
| Light  | Phosphor  | ⏳     |       |
| Light  | Amber     | ⏳     |       |
| Light  | Cyan      | ⏳     |       |
| Light  | Magenta   | ⏳     |       |
| Light  | Paper     | ⏳     |       |

## 2. All 11 presets at minimum widget sizes

| Preset | Smallest size | Status | Notes |
|--------|--------------:|:------:|-------|
| single                | 1×2 | ⏳ | UX polish 2026-05-27: shrunk SingleValueWidget cell height |
| dual                  |     | ⏳ |       |
| triple                |     | ⏳ |       |
| spectrogram           |     | ⏳ |       |
| spectrogram + meter   |     | ⏳ |       |
| waterfall             |     | ⏳ |       |
| spektralanalyse-labor |     | ⏳ |       |
| level history         |     | ⏳ |       |
| sound masking         |     | ⏳ |       |
| frequency display     |     | ⏳ |       |
| tone generator        |     | ⏳ |       |

## 3. Edit mode

- [ ] Jiggle visible on every card.
- [ ] Accent border + glow present on each card.
- [ ] Drag / delete circles tappable (44 pt min target).
- [ ] Preset rail + transport dim to ~35% opacity.
- [ ] Drag-reorder still works (within the grid).

## 4. Tweaks panel

For every toggle: takes effect immediately, persists across cold
launch (kill from app switcher, relaunch).

| Toggle | Immediate effect | Persists | Notes |
|--------|:----------------:|:--------:|-------|
| (to be enumerated on hardware) | ⏳ | ⏳ | |

## 5. Transport bar

- [ ] LED pulses **live** (engine running, not recording).
- [ ] LED pulses **recording** (record mode).
- [ ] Record button tints red when active.
- [ ] Play button tints accent when active.

## 6. (covered above as item 5 in code-side report — leaving here as the doc's item-6 placeholder; renumber on close)

## 7. Watch app

| Face                       | Selectable | New chrome | Notes |
|----------------------------|:----------:|:----------:|-------|
| WatchPegelmesserFace       | ⏳          | ⏳         |       |
| WatchModularFace           | ⏳          | ⏳         |       |
| WatchTonegeneratorFace     | ⏳          | ⏳         |       |
| WatchDashboardView         | ⏳          | n/a (legacy) |     |
| WatchSpectrogramView       | ⏳          | n/a (legacy) |     |
| WatchLevelMeterView        | ⏳          | n/a (legacy) |     |

Navigation: TabView page style — swipe horizontally between faces.

Complications (added in M12 task-4):
- [ ] Slot 1 — chrome matches Liquid Glass tokens.
- [ ] Slot 2 — same.
- [ ] Slot 3 — same.
- [ ] Complications update on iOS data changes (no stale ghosts).

## 8. Regression scan

- [ ] PDF export still produces a valid report.
- [ ] Recording flow unchanged (start → stop → file saved → playback works).
- [ ] Masking unchanged.

---

## Issues found

(Filled in as we go; each entry: severity, area, repro, expected, actual, suggested fix.)

### 2026-05-27 — UX polish (already landed, listed for traceability)

- **SingleValueWidget** vertical height: too much padding around the
  big number, especially in the `single` preset. **Fix landed** (task #27).
- **Preset rail** highlight: not updating when changing layout by
  swipe. **Fix landed** (task #28).

---

## Walkthrough log (chronological)

- 14:57 — fresh build installed to iPhone SB. Watch app already
  installed (pid 961). User reports they're in the app.
- 14:25 (pre-rebuild) — user submitted screenshot of `single` preset
  layout showing 4 SingleValueWidget cards with excessive vertical
  whitespace + preset rail not following swipes; both addressed in
  the rebuild now on device.
