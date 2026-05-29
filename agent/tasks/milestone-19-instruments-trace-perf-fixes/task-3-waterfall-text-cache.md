# Task 3: WaterfallView Frequency-Label Cache

Status: completed
Created: 2026-05-29
Priority: P1

## Problem

The 2026-05-29 trace shows **67+ samples** of
`-[NSCoreTypesetter _stringDrawingCoreTextEngineWithOriginalString:...]`
— the full CoreText layout pipeline.

The direct call path to `WaterfallView.drawText(_:at:anchor:context:)`
accounts for 12 of those samples. The function is called from a Canvas
draw callback (`WaterfallView.draw(in:context:)`) and runs the full
CoreText layout + typesetting pipeline — including glyph encoding, pair-
kerning (OTL `GPOS::ApplyPairPos`), line truncation, and text state flush
— **on every render tick**.

Additional frames observed in the same rows:
- `TGlyphIterator::Next`
- `OTL::GPOS::ApplyPairPos`
- `-[_NSCoreTypesetterLayoutCache getCTLine:...]`
- `CTLineCreateWithString`
- CoreGraphics font state push/pop

Frequency labels on the waterfall do not change every frame — they are
a function of the current frequency scale and zoom level, which change
only on user interaction.

## Acceptance

- `WaterfallView.drawText` does not call into `NSCoreTypesetter` during
  steady-state rendering (no user interaction, no scale change).
- Frequency labels are cached; the cache is invalidated only when the
  label string, font size, or drawing attributes change.
- `NSCoreTypesetter` does not appear in the top 20 Time Profiler frames
  in a 76-second re-trace under normal use.
- Visual output of waterfall frequency labels is unchanged.
- iOS build succeeds.

## Implementation notes

- Identify the label strings rendered by `drawText` — these are likely
  frequency values like "1 kHz", "4 kHz" derived from the waterfall's
  frequency axis. They change only when `minFreq`/`maxFreq`/zoom changes.
- Cache strategy: a `[String: CGImage]` or `[String: NSAttributedString]`
  keyed on the label text + font descriptor. Pre-render to `CGImage` using
  `ImageRenderer` (iOS 16+) or a `CGBitmapContext` at the appropriate
  scale factor.
- Alternative (simpler): use SwiftUI `Canvas` with `context.draw(Text(...))`
  directly — SwiftUI caches the resolved glyph runs internally and avoids
  the full NSCoreTypesetter path for static labels.
- If `drawText` is called in a `TimelineView` / `Canvas` scheduled at
  display refresh rate, verify it is only called for frame-varying elements
  (e.g. the time cursor) and not for static labels.
- The `WaterfallView.drawUnifiedScene(plot:context:)` call site (15 samples)
  calls `drawText` inside it — cache at the scene level so the cache lookup
  is O(1) per frame.

Milestone: `milestone-19-instruments-trace-perf-fixes`
Source: 2026-05-29 Instruments trace — 67 NSCoreTypesetter samples
