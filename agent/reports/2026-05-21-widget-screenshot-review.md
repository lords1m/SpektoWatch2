# Widget Screenshot Review

Date: 2026-05-21
Evidence: `Spectowatch Widget Screenshots /`
Scope: M8 widget sizing acceptance and M9 widget audit input

## Summary

The screenshot set contains 39 full-device iPhone captures (`1125×2436`) from
the widget-size screenshot preset. It is useful runtime evidence that the
preset pages can be installed and captured on hardware, but it does not close
M8 acceptance by itself.

M8 should remain open until either a focused manual pass confirms the fresh
dashboard, legacy-dashboard migration, and reorder behaviour, or those checks
are separately recorded.

## Observations

- `IMG_2550.PNG` through `IMG_2590.PNG` show the screenshot preset pages for
  multiple widget types.
- The dashboard page selector and header are visible across the run, confirming
  that multiple preset pages were generated and can be navigated.
- The debug overlay `DEBUG UI VISIBLE` overlaps the dashboard title/header in
  every sampled screenshot. This is not necessarily an M8 sizing bug, but it
  makes the captures unsuitable as clean product screenshots.
- The page indicator sits close to or over the first visible widget on several
  pages (`IMG_2550.PNG`, `IMG_2555.PNG`, `IMG_2560.PNG`, `IMG_2581.PNG`).
- Bottom controls obscure lower widgets in the screenshot preset. This is
  expected for a live dashboard with fixed bottom controls, but it means the
  screenshot set is not a complete visibility proof for every generated size.
- `IMG_2570.PNG` and `IMG_2573.PNG` show frequency display pages that are
  visually blank apart from axes/grid in the captured state.
- `IMG_2576.PNG` shows level-meter sizes, but much of the page consists of
  empty vertical space around the meter control at larger/taller sizes.
- `IMG_2577.PNG` shows phase-meter fallback text. The fallback is legible in
  larger sizes, but tight and multi-line in narrow/tall sizes.
- `IMG_2578.PNG` shows single-value widgets fitting their allowed sizes well.
- `IMG_2580.PNG` and `IMG_2581.PNG` show tone-generator controls. The page is
  functional, but preset buttons are cramped/truncated on wider captured state
  (`8k` is clipped at the right edge in `IMG_2581.PNG`).
- `IMG_2585.PNG` shows spektralanalyse-lab controls. The small repeated widget
  has truncated segmented-control labels (`10...`, `2...`, `4...`, etc.).
- `IMG_2590.PNG` shows masking widgets largely blank/faint in the captured
  state, with only the `MASKING` heading clearly visible.

## Design Audit

### Global dashboard chrome

The screenshot preset is working as a runtime catalog, but the surrounding
dashboard chrome currently makes it hard to judge the widgets cleanly:

- The yellow `DEBUG UI VISIBLE` badge overlaps the title area in every sampled
  screenshot. This should be hidden for presentation/screenshot mode.
- The header card is visually heavy and consumes enough vertical space that
  the first row of widgets starts under or very close to it.
- The page dots often sit on top of widget content. This is especially visible
  in spectrogram, level-history, tone-generator, and masking captures.
- The fixed bottom control bar obscures the last visible widget on almost every
  long page. That is acceptable in the live dashboard, but not in a preset that
  is meant to prove every size can be captured.
- Long preset names truncate in the header (`Frequenz-Spekt...`,
  `Spektralanalyse...`). The header should either use shorter screenshot-mode
  names or a secondary compact title treatment.

Recommendation: add a presentation/screenshot mode that hides the debug badge,
uses compact header spacing, reserves a safe area for page dots, and either
hides the bottom transport controls or increases the scroll content inset so
every widget can be fully captured.

### Spectrogram

Status: strong at medium and large sizes.

The spectrogram is the most visually distinctive widget in the set. Large
captures such as `IMG_2551.PNG` and `IMG_2552.PNG` make the product feel
technical and alive. Frequency labels are useful and the color field gives
immediate context.

Issues:

- The first/top widgets are partially covered by header/page-dot chrome.
- Small or freshly initialized states can look dark or empty before enough data
  is present.
- Axis labels sit directly over the signal and can become visually busy at the
  smallest supported sizes.

Recommendation: keep the current visual direction, but introduce compact label
density by size. For the minimum size, reduce the number of frequency labels
and reserve a small safe inset for page dots or hide them in screenshot mode.

### Waterfall

Status: expressive, but not equally successful across shapes.

The waterfall view has a strong sense of depth and motion in wide sizes, but
the tall/narrow variants spend too much space on perspective and black
background. Some captures show the data mass pushed high in the frame, leaving
the lower area underused.

Issues:

- Tall/narrow variants look less informative than wide variants.
- Top labels and timestamps can crowd the signal.
- Large dark empty areas make the widget feel less precise than the
  spectrogram, even though it is likely rendering valid data.

Recommendation: use a flatter compact waterfall treatment for narrow/tall
sizes and reserve the full 3D/perspective rendering for larger sizes.

### Pegelverlauf

Status: useful chart, needs overlay cleanup.

The level-history graph is readable and gives quick trend information. The
blue line and fill are clear against the grid.

Issues:

- The `LAF` badge collides visually with the y-axis top label around `110`.
- `phon` and `sone` badges occupy chart area and can dominate smaller widgets.
- Tall sizes have large unused vertical space, while the meaningful signal
  remains near the bottom.

Recommendation: move the measurement badge into a title/header row, make
psychoacoustic values conditional by size, and auto-scale the y-domain more
aggressively so tall widgets use their height.

### Frequenz-Spektrum

Status: currently reads as blank in the screenshot state.

The grid and axes are clean, but the captured pages (`IMG_2570.PNG`,
`IMG_2573.PNG`) show no visible spectrum trace. In a screenshot catalog, this
looks broken even if the underlying state is simply idle or waiting for data.

Issues:

- No visible empty-state message or placeholder trace.
- Header title truncates.
- Large blank chart area has low perceived value.

Recommendation: add an explicit idle state such as `Warte auf Spektrum`, a
subtle reference/noise-floor line, or deterministic demo data for screenshot
mode. This widget should never present as an empty grid in marketing or QA
captures.

### Pegel-Meter

Status: biggest size-adaptation issue.

The level meter is legible, but tall captures use the available space poorly:
the meter remains a small horizontal component near the bottom while most of
the card is empty.

Issues:

- Tall/narrow sizes need a vertical meter or large numeric readout.
- Current layout does not communicate more information when the widget grows.
- The visual weight is too low compared with neighboring chart widgets.

Recommendation: switch layout by aspect ratio. Use a vertical meter and large
dB value in tall/narrow cards; use the current horizontal meter in wide cards.

### Phasen-Meter

Status: acceptable fallback, but too verbose at small sizes.

The missing-stereo state is understandable. It communicates why the widget is
not drawing data.

Issues:

- The fallback copy wraps tightly in narrow cards.
- Repeating the full explanation in every size makes the catalog feel noisy.

Recommendation: use a compact fallback at small sizes (`Stereo aus` plus a
settings glyph) and keep the full explanation for larger cards.

### Einzelwert

Status: strongest adaptive widget.

Single-value widgets fit the size matrix well. The value hierarchy is clear,
the unit is readable, and the widget remains understandable at every sampled
size.

Issues:

- Very tall variants have a lot of empty space.

Recommendation: keep the base design. Consider adding optional context in
larger variants only, such as min/max, short trend, or measurement mode.

### Tongenerator

Status: strong feature widget, dense controls need size rules.

The tone generator feels like a real instrument panel. The oscilloscope-style
display, frequency readout, slider, waveform picker, and play control give it
personality and utility.

Issues:

- Preset chips clip at the right edge in `IMG_2581.PNG` and `IMG_2582.PNG`.
- The smallest viable size is control-dense; waveform, volume, preset chips,
  and play compete for space.
- The bottom transport bar can cover the widget's own play area in the
  screenshot page.

Recommendation: introduce compact/expanded tone-generator layouts. Compact
mode should prioritize frequency, play/stop, and one input method. The planned
optional piano frequency input should replace the chip row when active rather
than being added beside every existing control.

### Spektralanalyse-Labor

Status: excellent as a full-width tool, poor as a small widget.

The large configuration panel looks capable and well organized. It behaves
more like a specialist tool surface than a passive dashboard widget, which is
appropriate for this feature.

Issues:

- Small variants truncate segmented-control labels (`10...`, `2...`, `4...`,
  `81...`, `16...`).
- There are too many controls for minimum widget sizes.
- The page title also truncates in the dashboard header.

Recommendation: set a larger practical minimum for the full control surface,
or provide a compact summary-only widget for small sizes. Replace segmented
controls with menus or stepped controls when width is constrained.

### Sound Masking

Status: highest priority visual fix.

The masking page reads as nearly empty in the screenshot set. Headings and the
`IDLE · TIPPEN` text are visible, but the chart/spectrum content is extremely
low contrast or absent.

Issues:

- Empty/idle state is not visually actionable.
- Repeated masking cards look blank, especially in larger sizes.
- Low contrast makes the widget feel disabled or unfinished.

Recommendation: create a clear idle state with a primary action, active profile
name, and placeholder masking curve. Increase contrast for axes and spectrum
content. In screenshot mode, seed representative masking data so the widget can
be evaluated.

## Priority

1. Presentation mode: hide debug badge, fix page dots, and prevent footer
   overlap in screenshot captures.
2. Masking: make idle/empty state visible and useful.
3. Level meter: add aspect-ratio-specific vertical/tall layout.
4. Frequency spectrum: avoid blank grid captures.
5. Spektralanalyse-lab: prevent segmented-control truncation at small sizes.
6. Tone generator: stop preset-chip clipping and define compact mode.
7. Level history: clean up overlays and chart scaling.

## M8 Acceptance Impact

Code-side M8 checks remain valid:

- Spectrogram and single-value clamping paths are verified in code.
- Legacy `Double` row decoding has XCTest coverage.
- PDF/widget config decode compatibility was verified by code inspection.

Runtime checks still not fully closed by the screenshots:

- Fresh dashboard default page was not separately documented.
- Existing legacy dashboard visual clamp behaviour was not separately
  documented.
- Drag-and-drop reorder was not captured.
- The screenshot preset pages reveal layout quality issues that belong in M9
  widget audit, and a few may need cleanup before treating screenshots as
  clean acceptance evidence.

## Recommendation

Keep M8 `task-2-acceptance` in progress.

Use this screenshot folder as M9 audit input. For M8 closure, capture or record
a short focused manual pass:

1. Fresh dashboard opens with spectrogram `3×3` and level history `3×2`.
2. Legacy `Double` row dashboard opens and clamps visibly without crashing.
3. Drag-and-drop reorder still works after M8 sizing changes.
4. Resize handles enforce spectrogram min `2×2` and single-value max `2×2`.
