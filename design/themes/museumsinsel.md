# Museumsinsel

*U5 · Max Dudler, opened 2021*

Max Dudler made the vault over the tracks a deep blue barrel vault set
with more than 6,600 points of light. It is a tribute to Karl Friedrich
Schinkel's 1816 night-sky stage set for *Die Zauberflöte*: with no
daylight underground, the station builds its own sky.

The theme takes that idea literally. **The chart canvas is always night**,
even in light mode. A spectrogram becomes a sky being filled with stars:
silence is the blue vault, and signal is starlight.

## Idea

- Night blue is the ground, not a colour accent. In dark mode it covers
  everything. In light mode it stays only on canvases, like looking up
  from a lit platform into the vault.
- Starlight gold (`#F2C14E`) is the station colour (*Kennfarbe*). Keep it
  rare: the lit meter tile, the primary button, the record marker.
- Light mode is pale plaster and stone, the platform you stand on.

## Palette

| Token | Light | Dark |
|---|---|---|
| `background` | `#F4F2EC` | `#0A1338` |
| `backgroundRaised` | `#EAE7DE` | `#0F1A45` |
| `surface` | `#FFFFFF` | `#111D4C` |
| `surfaceSunken` | `#E2DED2` | `#1A2860` |
| `canvas` | `#0A1338` | `#070D29` |
| `canvasLabel` | `#F4EEDC` | `#F4EEDC` |
| `separator` | `#CFCAB9` | `#2A3A78` |
| `grout` | `#1F2C66` | `#1F2C66` |
| `label` | `#0E1A4A` | `#F4EEDC` |
| `labelSecondary` | `#3E4870` | `#C3C8DE` |
| `labelTertiary` | `#535C80` | `#9AA2C4` |
| `kennfarbe` | `#F2C14E` | `#F2C14E` |
| `onKennfarbe` | `#0E1A4A` | `#0A1338` |

`canvasLabel` is new to this theme. Because the canvas stays night blue
in light mode, ticks and annotations on it use starlight white rather
than `label`. Every other theme sets `canvasLabel = label`.

## Spectral ramp

```
0.00  vault-deep    #050A20
0.12  vault         #0A1338
0.25  schinkel      #1B2D7A
0.38  lapis         #2F4FB8
0.50  dusk-blue     #5B7FD6
0.62  pale-sky      #9DB4EA
0.76  moonlight     #E8D9A8
0.88  starlight     #F2C14E
1.00  star-core     #FFF6DC
```

The ramp runs from blue to gold without passing through green or red, so
it stays inside the vault's colours.

## Motif: star field

This replaces Ferrite's square tile grout. Canvases and the Home Screen
wall get a sparse, fixed field of 1pt dots at 8–20 % opacity: in
`canvasLabel` on canvases, and in `label` on the wall, so the stars still
show on the pale light-mode plaster. It is seeded (deterministic), never animated, and has about one
dot per 24×24pt tile, which is the station's density of lights. It is
decorative only and turns off under Reduce Transparency.

## Typography

- Titles: SF Pro, **New York** design (`.serif`), regular weight, for the
  Schinkel and Neoclassical register.
- Everything else is Ferrite as it is: SF Pro, bold eyebrows, tabular
  digits.

## Departures from Ferrite

- The canvas ignores the light/dark choice and is always night.
- The card outline is `separator`, not `label`: a full ink outline would
  break up the sky.

## Best used for

Quiet listening, night-time recordings, long-running spectrograms, and
anyone who wants dark mode to feel like a place rather than an inverted
page.
