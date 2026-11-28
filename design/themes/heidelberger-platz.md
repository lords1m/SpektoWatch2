# Heidelberger Platz

*U3 · Wilhelm Leitgebel, opened 1913*

Heidelberger Platz lies deep below the Ringbahn, which let Leitgebel
build it more lavishly than any other Wilmersdorf station: a double row
of cross-groined vaults on squat piers, with large chandeliers hanging
over the waiting passengers. It is often compared to a cathedral, or to
the palace stations of the Moscow Metro.

This is the ceremonial theme: **warm lamplight under a stone vault**. It
is the only Ferrite variant with a serif and with warm, ambient light.

## Idea

- The ground is lime plaster in light mode and smoke-dark stone in dark
  mode, both warm and never neutral grey.
- Brass (`#B8862B` light, `#D9A441` dark) is the Kennfarbe: the colour of
  the chandeliers' light. It fills the primary button and lit meter tiles.
- In dark mode, cards get a faint top-down glow (a brass radial gradient
  at 6 %) as if lit from a chandelier above. This is the only theme where
  light has a colour.

## Palette

| Token | Light | Dark |
|---|---|---|
| `background` | `#F1EADC` | `#15110C` |
| `backgroundRaised` | `#E8DFCD` | `#1C1711` |
| `surface` | `#FAF5EA` | `#201A13` |
| `surfaceSunken` | `#DDD2BC` | `#2C241A` |
| `canvas` | `#F1EADC` | `#0E0B08` |
| `canvasLabel` | `#231C14` | `#F3EAD8` |
| `separator` | `#C9BCA0` | `#3E3426` |
| `grout` | `#D6CAB2` | `#2E2619` |
| `label` | `#231C14` | `#F3EAD8` |
| `labelSecondary` | `#4E4335` | `#C9BDA5` |
| `labelTertiary` | `#625543` | `#A0937A` |
| `kennfarbe` | `#B8862B` | `#D9A441` |
| `onKennfarbe` | `#000000` | `#000000` |

The light-mode brass is only 2.7:1 against the background, which is fine
for a fill but not for a 1pt line. Never use it for thin strokes; use
`label` there.

## Spectral ramp

```
0.00  crypt         #0E0B08
0.12  smoke         #2A2117
0.25  umber         #4A3A25
0.38  bronze-deep   #7A5A2C
0.50  bronze        #A8782F
0.62  brass         #D9A441
0.76  candle        #F0CE7A
0.88  flame-pale    #FBEBC0
1.00  incandescent  #FFFBEF
```

The ramp goes from dark to lamp-hot in a single warm family. It sits
close to Inferno but never turns red.

## Motif: groined vault

Instead of square grout, the Home Screen wall and empty canvases get
intersecting quarter-arcs drawn in `grout` at 1pt on a 48pt bay, two rows
deep along the top edge. This reads as the line of the cross vaults seen
from below. Below the "vault" the wall is plain. It is decorative only
and turns off under Reduce Transparency.

## Typography

- Large titles and card titles use **New York** (`.serif`), semibold.
- The hero value stays SF Pro bold with tabular digits, because
  measurement stays modern.
- Eyebrows: SF Pro, bold, tracked caps as in Ferrite.

## Departures from Ferrite

- Coloured ambient light (the brass glow) in dark mode. It is purely
  decorative and turns off under Reduce Transparency.
- Serif titles.

## Best used for

Concert and rehearsal recording, room acoustics and reverb measurement,
and evening use. It is the theme for listening in a resonant space.
