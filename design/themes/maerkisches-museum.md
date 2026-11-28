# Märkisches Museum

*U2 · Alfred Grenander, opened 1913*

Grenander gave his stations a *Kennfarbe*, an identifying colour, so that
each one looks clearly different from its neighbours. At Märkisches
Museum it is green: green-fired glazed tiles, and green-framed panels on
the side walls. When the original tiles were knocked off during a
renovation, they were fired again true to the originals.

This theme is the Grenander system applied to the app. One glazed green
is the colour, cream is the joint, and **the frame is the ornament**.

## Idea

- Bottle-green glaze (`#2E6B4F`) is the Kennfarbe. It fills buttons and
  lit meter tiles, and also draws the card frames.
- The ground is warm cream, like the joints and plaster between tiles,
  not paper-white.
- Dark mode is the same tile at night: deep green-black, with the glaze
  lifted to `#4E9A74` so it still reads.

## Palette

| Token | Light | Dark |
|---|---|---|
| `background` | `#F2EFE3` | `#0C1A14` |
| `backgroundRaised` | `#E9E5D6` | `#10221A` |
| `surface` | `#FBF9F2` | `#132820` |
| `surfaceSunken` | `#E0DBC9` | `#1B3529` |
| `canvas` | `#F2EFE3` | `#0C1A14` |
| `canvasLabel` | `#14271E` | `#EEF0E4` |
| `separator` | `#CFC8B2` | `#2A4A3A` |
| `grout` | `#D8D2BE` | `#234033` |
| `label` | `#14271E` | `#EEF0E4` |
| `labelSecondary` | `#3D4F45` | `#BCC7BC` |
| `labelTertiary` | `#4F5F55` | `#93A398` |
| `kennfarbe` | `#2E6B4F` | `#4E9A74` |
| `onKennfarbe` | `#FFFFFF` | `#000000` |

## Spectral ramp

```
0.00  tile-night    #0C1A14
0.12  moss-deep     #173A2B
0.25  fir           #22573F
0.38  glaze         #2E6B4F
0.50  glaze-lit     #4E9A74
0.62  sage          #8CC39A
0.76  pale-sage     #C9DDA6
0.88  cream-glow    #EFE9C8
1.00  joint         #FBF9F2
```

This is a single-hue ramp from deep green to glaze highlight. Treat it as
an alternative to Viridis, not a replacement: peaks read as the light
caught on a glazed tile.

## Motif: running-bond tile

Grenander's glazed tiles are rectangles, not Paradestraße's squares.
Canvases and the Home Screen wall use a **24 × 12pt running bond**, with
each row offset by half a tile, drawn in `grout` at 1pt. It is
decorative only and turns off under Reduce Transparency.

## The green frame

Cards get a 2pt frame in `kennfarbe` instead of the 1pt `label` outline,
inset 4pt from a second 1pt `separator` line. This recalls the
green-framed panels on the station's walls. One framed card per screen
carries the hero value. The rest keep the plain hairline.

## Typography

SF Pro, as in Ferrite: bold titles, tracked uppercase eyebrows, tabular
digits. The frame and the tile carry the 1913 character, so the type
stays plain.

## Departures from Ferrite

- The Kennfarbe may draw a rule (the frame). Ferrite forbids coloured
  rules. Here it is allowed only for the frame, never for text.
- The U-line picker stays available, but the default is the green
  Kennfarbe, not ink.

## Best used for

Daytime use, measurements in the field, and anyone who finds pure black
and white too clinical. It is the warmest of the light themes.
