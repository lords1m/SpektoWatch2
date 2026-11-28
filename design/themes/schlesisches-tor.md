# Schlesisches Tor

*U1 · elevated line, opened 1902*

Schlesisches Tor is one of the oldest stations in the network, and is not
underground at all. It sits on the Stammlinie's steel viaduct, more than
7 km of riveted steel, about six metres above Kreuzberg. The station
building is brick and sandstone over riveted iron and steel, decorated
with columns, faces and flourishes.

This is the industrial theme: **brick, sandstone and rivets, in
daylight**. It is the one look that is meant to be at its best in light
mode.

## Idea

- Sandstone is the ground in light mode. Dark mode is steel under the
  viaduct at night, cool and near-black.
- Brick red (`#A6402A` light, `#C4563A` dark) is the Kennfarbe: primary
  button, lit meter tiles, the record marker.
- Steel is the ink. `label` is a blue-black steel tone, not pure black.

## Palette

| Token | Light | Dark |
|---|---|---|
| `background` | `#EFE8DC` | `#121416` |
| `backgroundRaised` | `#E5DCCB` | `#181B1E` |
| `surface` | `#F8F3EA` | `#1C2023` |
| `surfaceSunken` | `#DAD0BC` | `#272C30` |
| `canvas` | `#EFE8DC` | `#0F1113` |
| `canvasLabel` | `#1E2224` | `#F0EADF` |
| `separator` | `#C5B9A2` | `#3A4146` |
| `grout` | `#D2C7B2` | `#2A3035` |
| `label` | `#1E2224` | `#F0EADF` |
| `labelSecondary` | `#464C50` | `#C2BFB7` |
| `labelTertiary` | `#53595D` | `#9C9A94` |
| `kennfarbe` | `#A6402A` | `#C4563A` |
| `onKennfarbe` | `#FFFFFF` | `#000000` |

## Spectral ramp

```
0.00  steel-night   #0F1113
0.12  girder        #262B2F
0.25  rivet-grey    #3F474D
0.38  rust-deep     #6B3A2C
0.50  brick         #A6402A
0.62  brick-lit     #D0704A
0.76  terracotta    #E3A877
0.88  sandstone     #EFD8B4
1.00  daylight      #FBF5EA
```

The ramp goes from cold steel to warm brick to sunlit sandstone: from
under the viaduct out into the street.

## Motif: rivet line

Card headers and the Home Screen dock get a row of 3pt circles on a 12pt
pitch along the top edge, in `separator`, like a riveted girder flange.
Canvases keep Ferrite's square grout, but at a 48pt pitch, for the
viaduct's larger bays. It is decorative only and turns off under Reduce
Transparency.

## Typography

- Large titles, eyebrows and the hero value use **SF Pro Condensed**
  (`.width(.condensed)`), heavy, like painted signage on a girder.
- Body stays SF Pro regular.

## Departures from Ferrite

- Condensed, heavy display type.
- `FerriteStroke.bar` goes from 6pt to 8pt. The eyebrow bar reads as a
  steel flange.
- Ink is steel blue-black, not pure black.

## Best used for

Outdoor and street recordings, traffic and environmental noise, and loud
places. A theme built to stay readable in sunlight.
