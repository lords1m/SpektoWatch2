# Liquid Glass — Phase 5 acceptance (simulator pass + hardware checklist)

Date: 2026-11-25 · Branch: `main` · Plan: `agent/design/liquid-glass-system-adoption.md`
Commits covered: `ba6137c` (Phase 1), `b1671b7` (Phase 2), `615c1a3` (Phase 3), `e67027f` (Phase 4)
Supersedes M12 task-6 (its checklist is folded into §3).

## 1. Verified in the simulator

iPhone 17 / iOS 26.5 and Apple Watch SE 3 40 mm / watchOS 26.5.

| Check | Result |
|---|---|
| iOS + watchOS builds (Phases 1–5) | Pass, no new warnings |
| Glass inventory | Every glass surface goes through `ferriteGlass` / `ferriteEdgeGlass` / `watchGlass`. System glass APIs are only in `DesignSystem/` and `WatchGlassStyle.swift` |
| `interactive` only on tappables | Pass (glass buttons, watch record and play/pause) |
| Glass never driven by live audio | Pass. Tints change only on record/playback state; the status label inside the bottom pill updates at 1 Hz |
| Edit mode enter/exit, repeated cycles | Pass, after keeping the top bar on `safeAreaInset` (see plan §4 Phase 2) |
| Dynamic Type AX5: dock, page pill | Pass (fixed-size Home Screen chrome) |
| Dynamic Type AX5: edit bar | **Fixed in Phase 5.** Labels wrapped letter by letter; now falls back to icon-only glass buttons via `ViewThatFits`, with the same VoiceOver labels and test identifiers, plus the large content viewer |
| Dark + Increase Contrast | Pass: glass pill/dock get a visible rim; text and dock tiles legible |
| Watch tone generator PLAY/PAUSE glass, both states | Pass |
| Watch footer over live canvases → solid fallback | Pass (spectrogram screen) |
| Doubled status dot on watch footers | Fixed in Phase 4 |

## 2. Could not be verified here

| Item | Why | Where |
|---|---|---|
| Unit tests | **Test build fixed** (`IntegrationTests.swift`: captured `var` + `NSLock` → `OSAllocatedUnfairLock<Int>`; the Swift 6 error had been there since `bb8ef7b`). Full run on iPhone 17 / iOS 26.5: 524 tests, 10 skipped, 2 failures, both unrelated to the glass work: `PDFReportSnapshotTests.testPDFReport_documentOutline_matchesBaseline` (a one-space difference in extracted text, `(Z/A/C) Z` vs `(Z/A/C)Z`; baseline recorded on iPhone 17 Pro, and the PDF export changed in `083fc07`) and `AudioEngineCharacterizationTests.testWearableIngestFallbackIntegratesBandLeqWhenAbsent` (2 s timeout under full-suite load; passes 2/2 in isolation) | Re-record the PDF outline baseline on the reference device; consider a longer timeout for the wearable test |
| Reduce Transparency, Reduce Motion | The simulator's Settings app comes up blank | Hardware §3 |
| GPU cost / hitches | Simulator GPU numbers aren't representative | Hardware §3 |
| iOS 18 fallback rendering | No iOS 18 runtime installed | Hardware or an iOS 18 simulator |
| iPad / iPhone Duo | iPad turned off for now (`TARGETED_DEVICE_FAMILY = 1` for the app and widget extension, 2026-11-25). Duo not checked | Later |

## 3. Hardware checklist

Device: an iPhone on iOS 26 (and one on iOS 18 if available), plus a paired Apple Watch.

**Performance (plan §5)**
1. Instruments (Hitches + Metal System Trace), 60 s each: home page with a live spectrogram,
   idle vs live vs recording. Compare with the M19 baseline. Budget: no new hitches,
   ≤ 1 ms extra frame time.
2. Same trace with edit mode toggled 10×. Watch for any sustained GPU work after it settles.
3. Pulsing `StatusLED` inside the bottom glass pill while live/recording: confirm it doesn't
   keep the glass pill re-rendering at 60 Hz. Fallback if it does: stop the pulse when the
   app isn't recording.
4. Watch: 10 min recording on the spectrogram screen. Battery drain compared with before Phase 4
   should be unchanged (the footer is solid there).

**Accessibility**
5. Reduce Transparency on: no translucent surface anywhere (dock, page pill, edit bar, snackbar,
   sync bar; watch record and play/pause solid).
6. Reduce Motion on: the edit bar fades instead of sliding.
7. Increase Contrast, light mode: glass rims are visible.
8. VoiceOver: dock, edit bar (both label and icon-only variants), and the sync bar read as before.
9. Watch Always-On: record and play/pause become dimmed solid fills.

**Carried over from M12 task-6**
10. Cold launch under each theme/line colour, light and dark.
11. All presets render without overlap at the smallest widget sizes. (Known, pre-existing: tall
    widgets are clipped at the page pill in edit mode.)
12. Edit mode: jiggle, ink border, drag/delete handles tappable, drag-reorder works.
13. Tweaks panel toggles apply immediately and persist across cold launch.
14. Transport: LED pulses when live/recording; record tile state correct.
15. Watch faces and complications use the new chrome.
16. Regression scan: PDF export, recording flow, masking unchanged.

## 4. Known issues found during Phases 2–5 (not glass-related, not fixed)

- Spectrogram axis labels and the expand glyph scale with Dynamic Type and overlap at AX sizes.
- The status label ("Bereit") uses a fixed 12 pt size and doesn't scale.
- Watch meter screen (40 mm): content taller than the screen; the footer/record button is cut off.
- Watch record button is 22 pt, small for a watch tap target.
- Unreachable views: `DashboardHeaderView`, `ControlBarView` `.bar` style, `WatchDashboardView`,
  `WatchPegelmesserFace`, `WatchModularFace`.
- Edit mode: tall widgets are clipped at the page pill (same on `HEAD` before Phase 2).
