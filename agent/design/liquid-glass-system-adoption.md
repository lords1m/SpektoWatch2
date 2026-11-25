# Liquid Glass — System Adoption Plan

Status: proposed · 2026-11-25
Builds on: M12 (Liquid Glass Redesign, code-complete, acceptance pending) and the
Ferrite design system (`SpektoWatch2/DesignSystem/`).

## 1. Where we are

The groundwork is good. Ferrite already states the right rule ("liquid glass is for
the floating navigation layer only, never glass on glass") and routes almost all
glass through one modifier, `ferriteGlass(in:interactive:)`, which:

- uses the system `.glassEffect` on iOS 26+,
- falls back to `.ultraThinMaterial` + `FerriteGlass` fill/stroke/edge/shadow below that,
- becomes opaque `background` + `label` outline under Reduce Transparency.

Deployment targets stay **iOS 18.0 / watchOS 11.0**. Every glass API below is gated
inside the Ferrite layer, never at call sites.

What is still missing is everything that makes glass feel like *one material*
instead of separate frosted stickers:

| Gap | Evidence |
|---|---|
| No `GlassEffectContainer` anywhere | header pill, page indicator, dock, edit-bar buttons are isolated glass shapes that can't blend, morph or share sampling |
| Hand-built glass buttons on iOS 26 | `FerriteGlassButtonStyle` wraps `ferriteGlass`; the system `.glass` / `.glassProminent` styles give press physics, tint and container morphing for free |
| No morphing between states | edit mode swaps header ↔ `HomeEditBar` with `.move + .opacity` (`ModularDashboardView.swift:55`) |
| Bars use `safeAreaInset`, not `safeAreaBar` | no scroll-edge effect under the header/dock on iOS 26 |
| Fixed radii on screen-edge glass | dock uses `FerriteRadius.dock`; doesn't follow device corners (iPhone Duo outer display, iPad windows) |
| Off-system materials | undo snackbar `.regularMaterial` + hand shadow (`ModularDashboardView.swift:241`), `AudioWidgets.swift:115`, `ViewPolish.swift:35,67`, `WatchAppSettingsView.swift:207`, `WatchGlassCard`/`WatchGlassBar` |
| Misleading / dead helpers | `liquidGlassCard` and `glassCard` are *not* glass (solid Ferrite cards); `glassBar`, `glassCardLite`, `backgroundExtensionEffect(cornerRadius:)` have 0 callers — and the last one shadows the iOS 26 system `backgroundExtensionEffect()` |
| Increase Contrast not handled | no `colorSchemeContrast` reads in the fallback path |
| Watch has no system glass | watch chrome is all `.thin/.ultraThinMaterial` |

## 2. The layer model (the one rule, made concrete)

| Layer | Surfaces | Material |
|---|---|---|
| **Content** | tile wall, widget cards, inner canvases (spectrogram, waterfall, LAF, charts), list rows, recording-detail cards, editor panels | Solid Ferrite (`surface`, `label` hairline). **Never glass, never material.** |
| **Navigation** (floats above content) | header pill, page indicator, dock/transport, edit bar, undo snackbar, nav/toolbars, partial-height sheets, watch control buttons | Liquid Glass via Ferrite API only |
| **Accent** (inside glass) | record button, "Fertig", the single primary action per bar | `.glassProminent` tinted with the `FerriteLine` colour — the only coloured glass |

Rules that follow from it:

- One prominent (tinted) glass control per bar, maximum.
- Glass never reacts to live audio (no level-driven tint/shape/size). The dock floats over
  a 60 Hz spectrogram; animating the glass itself per frame would re-render it every frame.
- `interactive()` only on things you can tap.
- Lenses *inside* glass (e.g. `GlassIconButton`'s `fillStrong` circle) stay solid fills.

## 3. Foundation API (Phase 1 — `DesignSystem/`)

All new API lives in Ferrite; call sites never write `#available`.

```swift
// FerriteGlassGroup.swift — groups neighbouring glass so it blends and morphs.
struct FerriteGlassGroup<Content: View>: View {
    var spacing: CGFloat = FerriteSpace.s
    @ContentBuilder var content: Content

    var body: some View {
        if #available(iOS 26, watchOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
```

```swift
// FerriteEffects.swift — extend the existing surface, don't fork it.
extension View {
    func ferriteGlass<S: Shape>(
        in shape: S,
        tint: FerriteLine? = nil,          // accent glass only
        interactive: Bool = false,
        id: AnyHashable? = nil,            // morph identity
        namespace: Namespace.ID? = nil
    ) -> some View
}
```

On iOS 26 this maps to
`.glassEffect(.regular.tint(tint?.color).interactive(interactive), in: shape)` plus
`.glassEffectID(id, in: namespace)` when both are set. The fallback path is today's code,
plus a stronger stroke when `colorSchemeContrast == .increased`.

Buttons — **as built**: `FerriteGlassButtonStyle` stays, but on iOS 26 it draws
interactive system glass (`.prominent` = line-tinted glass) and drops its own 96 % press
scale, since interactive glass supplies the press response. It also accepts a morph identity:
`.buttonStyle(.ferriteGlass(.round, id: "rec", in: ns))`. *Why not the system `.glass` /
`.glassProminent` styles:* their size depends on `controlSize`, so they can't guarantee
Ferrite's 44 pt minimum, and a `ButtonStyle` can't hand off to a system style. The visual
result (interactive glass that morphs inside a container) is the same.

Screen-edge glass — **as built**: a modifier, not a `Shape` wrapper.
`ConcentricRectangle` resolves its corners from the container, which a custom `Shape`'s
`path(in:)` can't see:

```swift
.ferriteEdgeGlass(minimumRadius: FerriteRadius.dock)
// iOS 26: glass in ConcentricRectangle(corners: .concentric(minimum: .fixed(r)), isUniform: true)
// else:   ferriteGlass in RoundedRectangle(cornerRadius: r)
```

Also added: `ferriteGlassUnion(id:namespace:)`, which merges sibling glass into one shape.

Bars:

```swift
extension View {
    /// `safeAreaBar` (scroll-edge effect) on iOS 26, `safeAreaInset` before.
    func ferriteBar<Bar: View>(edge: VerticalEdge, @ContentBuilder _ bar: () -> Bar) -> some View
}
```

Clean-up in the same phase:

- Delete `glassBar`, `GlassBar`, `glassCardLite`, `GlassCardLite`, and the custom
  `backgroundExtensionEffect(cornerRadius:)` (0 callers; name clash with the system API).
- Rename `liquidGlassCard` → `widgetCardChrome(isEditing:)` (1 caller; `ferriteCard` was
  already taken) so "glass" only ever means glass; its ignored `accent` parameter is gone.
  `glassCard` (23 callers) → `ferriteCard()` as a mechanical rename; optional, low risk.
- Update `FerriteGallery` to show every glass variant under light/dark/Reduce Transparency.

## 4. Phases

### Phase 1 — Foundation (above) — code landed 2026-11-25
Files: `DesignSystem/FerriteEffects.swift`, `FerriteComponents.swift`, `FerriteGallery.swift`,
new `FerriteGlassGroup.swift` and `FerriteBar.swift`, `GlassStyle.swift`, `DesignTokens.swift`,
`WidgetCardView.swift` (1-line rename).
Done when: Gallery renders every variant; iOS 18 and iOS 26 builds green; no call-site changes yet.
Deferred: `glassCard` → `ferriteCard` rename (23 callers, all in files with uncommitted
changes; do it once those are committed).

### Phase 2 — Home shell (the screen people live on)
Files: `ModularDashboardView.swift`, `DashboardHeaderView.swift`, `ControlBarView.swift`,
`HomeScreen/HomeScreenViews.swift`, `GlassIconButton.swift`.

1. **Top bar**: header pill and `HomeEditBar` in one `FerriteGlassGroup` with a shared
   `@Namespace`. Entering edit mode morphs the pill into the edit bar's three controls
   (`glassEffectID`) instead of sliding a second bar in. Reduce Motion → crossfade.
2. **Bottom stack**: page indicator + dock in one `FerriteGlassGroup`; dock shape →
   `FerriteEdgeShape`. Both top and bottom attach via `ferriteBar(edge:)` so the
   tile wall gets a soft scroll-edge effect under them.
3. **Transport**: play/stop/settings → `ferriteGlassButton(.round)`; record →
   `.prominent` with `FerriteLine.u2` tint. Idle → recording morphs the record
   control (wider capsule with elapsed time) via `glassEffectID`, not a view swap.
   REC blink stays on the text, not the glass.
4. **Undo snackbar** → `ferriteGlass(in: Capsule())`; drop `.regularMaterial`, the white
   stroke and the hand shadow.
5. **Edit-bar buttons** → `ferriteGlassButton`, grouped so "Seiten" + "Fertig" read as one cluster.

Done when: the three acceptance checks in §6 pass on the home screen.

**As built (2026-11-25, verified on the iPhone 17 / iOS 26.5 simulator):**
- There is no header pill on the home screen, so item 1 became: the edit-bar buttons sit in
  one `FerriteGlassGroup`, and the slide-in falls back to a fade under Reduce Motion.
- The transport stays as solid Home Screen icon tiles on the glass dock; item 3 was dropped.
  Glass buttons would break the M23 Home Screen look, and solid tiles on a glass platter
  already follow the "solid content inside glass" rule.
- Dock → `ferriteEdgeGlass` (concentric corners). Page indicator + dock share one
  `FerriteGlassGroup(spacing: 0)`; the bottom stack attaches via `ferriteBar`.
- Undo snackbar → `ferriteGlass` (no material, hand stroke or shadow). Not checked on screen.
- Removed the dead `footerBarHeight` GeometryReader/preference measurement.
- **Finding:** `safeAreaBar` holding the conditionally inserted edit bar left it offset
  horizontally by 10–28 pt after exit → re-enter. `HEAD` with `safeAreaInset` doesn't do this, and
  removing the glass group doesn't help. The top bar therefore stays on `safeAreaInset`;
  `ferriteBar` is documented as persistent-bars-only. Apply the same rule in Phase 3.
- Pre-existing, unchanged: tall widgets are clipped at the page indicator in edit mode
  (same on `HEAD`).

### Phase 3 — Secondary screens & sheets
Files: `Views/RecordingsListView.swift`, `Views/RecordingDetailView.swift`,
`AudioEditor/*`, `SpectrogramSettingsView.swift`, `WidgetSettingsView.swift`,
`WatchAppSettingsView.swift`, `ViewPolish.swift`, `AudioWidgets.swift`.

- Pushed screens use system `NavigationStack` toolbars, which become glass automatically
  on iOS 26. Group related items with `ToolbarItemGroup`; split clusters with
  `ToolbarSpacer(.fixed)` (iOS 26); put the one primary action in `.confirmationAction`
  / `.primaryAction`. No `toolbarBackground` overrides (none today; keep it that way).
- Sheets: medium-detent sheets get system glass on iOS 26 only if their root doesn't paint
  an opaque background. Audit each `.sheet` root: drop the fill for short sheets, keep
  `backgroundRaised` for `.large` / dense forms. Retire `FerriteGlassSheet` (Gallery-only)
  in favour of system sheets + `presentationDetents`.
- Ad-hoc materials: `AudioWidgets.swift:115` capsule sits *inside a card* → content layer →
  solid `surfaceSunken`. `ViewPolish.swift` toast → `ferriteGlass`. `WatchAppSettingsView.swift:207`
  → remove or route through `ferriteGlass` depending on whether it floats.
- Audio editor transport (floats over the waveform) → same treatment as the home dock.
- Keep the existing zoom transition (`matchedTransitionSource` / `.navigationTransition(.zoom)`).

**As built (2026-11-25, iPhone 17 / iOS 26.5 simulator):**
- Toolbars already had at most one item per side, so nothing needed grouping. "Abbrechen"
  buttons (audio editor, masking suggestion, trigger acquisition ×2) and the feature
  full-screen close now use `.cancellationAction`. The close glyph changed from
  `xmark.circle.fill` to `xmark`, because the iOS 26 toolbar already draws the glass circle.
  `RecordingDetailView`'s deprecated `.navigationBarTrailing` → `.topBarTrailing`.
- Sheets: all use `polishedFormChrome` (an opaque Ferrite background behind dense forms), so they
  stay opaque by design. Toolbar items on them are system glass and the nav bar gets the
  scroll-edge effect (checked: Settings, Layouts). `FerriteGlassSheet` retired (Gallery-only).
- Watch settings sync bar → floating `ferriteGlass` panel attached via `ferriteBar`
  (it stays on screen, so `safeAreaBar` is safe); the solid sync button stays inside it. Checked on screen.
- Materials inside content removed: the spectrum legend capsule → solid `surfaceSunken`.
  Deleted unused `canvasControlButton`, `transportGlassButton`, `CanvasReadoutPill`.
  The iOS target has no `Material` left outside `DesignSystem/`.
- Audio editor: no floating transport exists (panels are solid cards), so the item was dropped.
- Not checked on screen: the feature full-screen close button, the spectrum legend, iOS 18.

### Phase 4 — watchOS
Files: `SpektoWatch Watch App/WatchDashboardView.swift`, `WatchRecordButton.swift`, faces.

- `WatchGlassBar` → `ferriteGlass` (gated `watchOS 26`). `WatchGlassCard` is content → solid
  card, no material, no shadow.
- Record button → `.prominent` tinted glass; other controls `.glass`. Toolbars on watch go
  glass automatically.
- No glass over live spectrogram/level canvases on the faces (battery, and legibility in
  Always-On). When `isLuminanceReduced`, glass becomes a solid dim fill.

**As built (2026-11-25, Apple Watch SE 3 40 mm / watchOS 26.5 simulator):**
- `WatchGlassStyle.swift`: `watchGlass(in:tint:interactive:)` draws system glass on watchOS 26
  and a solid fallback (tint at 80 %, or a dark grey with a rim) on watchOS 11–25, with
  Reduce Transparency, in Always-On (the tint dimmed to 35 %), and wherever the
  `watchGlassOverLiveCanvas` environment flag is set. `WatchGlassCard` → solid `watchCard`
  (meter hero, recording detail); unused `WatchGlassBar` removed.
- One `WatchRecordToggle` replaces two copies of the record logic (tinted glass: blue idle,
  red recording). `WatchLiveCaptureFooter` now uses it, which fixes the doubled status dot
  on the meter, spectrogram and level screens.
- Spectrogram and level-graph footers float over live canvases, so they set
  `watchGlassOverLiveCanvas` and show the solid fallback (checked on screen).
- Tone generator PLAY/PAUSE → tinted interactive glass (green/red, white text); checked on
  screen in both states. Toolbars and back buttons get system glass automatically.
- Pills over canvases (spectrogram status, STFT, source indicator) were already solid; unchanged.
- Found, not changed: `WatchDashboardView`, `WatchPegelmesserFace` and `WatchModularFace`
  aren't reachable from `WatchContentView` (dead code?); on 40 mm the meter screen's
  content is taller than the screen, so its footer (record button) is cut off. The
  record button is 22 pt across, small for a watch tap target.

### Phase 5 — Performance, accessibility, acceptance
- **GPU budget**: with the dock and header over a live spectrogram + waterfall, record an
  Instruments (Hitches + Metal System Trace) run on iOS 26 against the M19 baseline. Budget:
  no new hitches, ≤ 1 ms added frame time. Mitigations if over: fewer separate glass shapes
  (containers), drop `interactive()` from non-tappables, never animate glass geometry
  continuously.
- **Accessibility matrix**: Reduce Transparency, Increase Contrast, Reduce Motion (morphs →
  crossfades), Dynamic Type AX5 (dock falls back via `ViewThatFits`), VoiceOver labels and
  identifiers unchanged (UI tests rely on them), 44 pt targets.
- **Snapshots**: add iOS 18 fallback, iOS 26 glass, Reduce Transparency, dark — for header,
  dock, edit bar, a sheet, and the Gallery.
- **Resizability**: iPad split view and iPhone Duo outer/inner displays — dock width capped on
  regular width, concentric corners correct on both Duo displays.

### Spatial depth pass (2026-11-26)

Goal: glass and Home Screen objects read as lit, layered 3D objects instead of flat
frosted stickers. References (Mobbin, iOS 26 apps): Moonly player (domed glass transport
buttons with a lit top rim), Grok voice bar (glass capsule with a gradient rim), Reddit /
Alan / IMDb floating tab bars (selected lens inside the glass, soft wide shadow under the bar).

As built — one light source, top/slightly leading, all from static shapes (`FerriteDepth.swift`):
- `FerriteSpecularRim`: 1 pt lit rim along the top, faint reflection on the far edge, 2.5 pt
  bevel shade on the lower inner edge. Works with `ConcentricRectangle` (2× stroke clipped).
- `FerriteSheen`: soft light over the upper half, under the content.
- `FerriteDropShadow`: contact + ambient shadow with the shape's interior knocked out
  (`destinationOut`), so glass never samples a shadow fill and live kernels never invalidate
  the blur.
- Tokens: `FerriteDepth` (rim, reflect, bevel, sheen) and `FerriteElevation.raised` /
  `.floating` in `FerriteTokens.swift`. `FerriteGlass.edge/shadowRadius/shadowY` removed.
- Applied in `FerriteGlassSurface` / `FerriteEdgeGlassSurface` (every glass variant: bars,
  dock, page indicator, glass buttons, snackbar, watch-settings sync panel), the
  `FerriteGlassBar` selection lens, `HomeIconGlyph` (Home icons + dock tiles: sheen between
  ink and symbol, rim, `raised` shadow) and the `.homeWidget` card chrome (rim + `raised`).
- Reduce Transparency: no sheen, rim or shadow (opaque + outline as before).
- Not changed: content-layer cards, canvases, rows (still flat Ferrite), watchOS (Phase 4).
- Not yet checked on screen (no macOS in this session): iOS 26 glass + rim, iOS 18 fallback,
  dark mode, jiggle-mode performance with per-tile shadows, Instruments budget (Phase 5).

## 5. Relationship to M12

Fold M12 task-6 (hardware acceptance) into Phase 5 rather than running it twice: Phases 2–4
change exactly the chrome M12's checklist verifies. Proposed as **M24 — Liquid Glass System
Adoption**, one task per phase. Start it on a branch after the ~40 currently uncommitted files on
`main` are committed.

## 6. Acceptance

1. On iOS 26, entering/leaving edit mode visibly morphs the top glass; the dock and page
   indicator read as one glass group; content scrolling under bars shows the edge effect.
2. On iOS 18, every screen looks like today's fallback (no regressions in snapshots).
3. Reduce Transparency → zero translucent surfaces anywhere, iOS and watch.
4. `grep` finds no `Material` and no `glassEffect` outside `DesignSystem/`.
5. No new hitches over the live spectrogram (Instruments, vs M19 baseline).
6. iOS + watchOS builds green; UI tests pass unchanged.

## 7. Out of scope

- Rendering kernels (Metal, Charts, LAF) and the Ferrite palette/tile language.
- Raising deployment targets.
- A tab bar: the home screen stays a paged preset wall + dock.

## 8. References (Mobbin, saved 2026-11-25)

Links open only for the account owner and their team (private saves).

| Reference | What it shows | Bearing on this plan |
|---|---|---|
| [Opal – Time Keeper](https://mobbin.com/screens/a26d6de7-c2ce-4be6-be6a-69f71a0ebe32) | Short config form in a translucent dark sheet over the blurred rules list; rows as rounded capsules; round glass back/edit buttons; tinted "+"; wide "Hold to Commit" primary | Counter-example to "all sheets opaque" → candidate A |
| [Cal AI – Progress](https://mobbin.com/screens/61178e40-0dea-465d-8537-64da93a26343) | Solid dark content cards; floating glass tab-bar capsule with selected pill; separate round "+" primary action beside it | Confirms the layer model (solid content, glass nav). The separate primary circle doesn't fit the M23 icon dock; revisit only if the dock is redesigned |
| [Crumbl Cookies – naming dialog](https://mobbin.com/screens/4a901e96-7f48-4700-8853-c44a84d4935b) | Clear glass card over a busy photo: text field, outlined Cancel, dimmed Save capsule | Pattern for short in-place prompts (e.g. naming a recording) instead of full sheets |
| [Apple Music – Subscribing flow](https://mobbin.com/flows/54f3f242-a9de-4b2e-be96-8d64010fc59d?tab=screens) | Standard iOS 26 chrome: floating glass tab bar + "Now Playing" accessory pill above it; content scrolls underneath | Confirms the Phase 2 bottom stack (status/page pill above the dock) → candidate B |

**Takeaways already reflected in Phases 1–3:** content stays solid; only floating controls
are glass; one tinted primary per bar; an accessory pill above the bottom bar.

## 9. Follow-up candidates (proposed, not scheduled)

**A — Glass for short sheets.** Phase 3 kept every sheet opaque (`polishedFormChrome`).
Following Opal, sheets with only a few rows (widget settings, masking save sheet, Tweaks)
could drop the opaque background at `.medium` so the system sheet glass shows, with rows
grouped as rounded capsules. Dense forms (Settings, Apple Watch, audio export) stay opaque.
- Needs: a `polishedShortSheetChrome()` variant (no background at `.medium`, Ferrite
  `backgroundRaised` at `.large`); legibility check of Form rows over glass in both themes;
  Reduce Transparency → opaque.
- Risk: Ferrite's black/white tile language says solid surfaces for anything you read.
  Decide per sheet, not globally.

**B — Live recording pill.** Following Apple Music's Now Playing accessory, the status/page
pill above the dock (`HomePageIndicator` + `HomeStatusLabel`) could expand while recording
to show elapsed time and the current LAF level, and tap through to the recording.
- Needs: the pill reads the same 1 Hz throttled metrics as the M20 Live Activity, *not*
  the 60 Hz stream (the rule from §2: glass never reacts to live audio per frame).
  Expansion uses `glassEffectID` morphing inside the existing bottom `FerriteGlassGroup`.
- Scope: a new feature, not restyling, so it should get its own task, after Phase 5's
  performance pass sets the GPU baseline.

## Appendix — unrelated modernization spotted (not part of this plan)

- `GlassIconButton.swift`: `UIImpactFeedbackGenerator` → `sensoryFeedback()`; badge uses
  `.caption2` + `fontWeight(.bold)` → a larger style + `bold()`.
- `ModularDashboardView.swift`: footer height measured via `GeometryReader` + preference key;
  with `safeAreaBar` the measurement is likely unnecessary.
