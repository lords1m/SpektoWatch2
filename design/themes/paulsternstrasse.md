# Paulsternstraße

*U7 · Rainer G. Rümmler, opened 1984, listed monument since 2017*

Rümmler designed more of West Berlin's U-Bahn stations than anyone else,
and his stations of the 1970s and 80s are known for loud colour and
symbolism. Paulsternstraße tells the story of a carriage ride from Berlin
to Spandau about 200 years ago. Its walls and pillars show the flowers,
trees and meadows along the road, and stars for the night: white and red
tile mosaics of flowers on a dark blue ground.

This is the playful theme. It is the only one that allows **two**
colours, red bloom and meadow green, and the only one with rounded type.

## Idea

- Dark blue is the ground, as on the station's walls. Unlike Museumsinsel,
  which is calm, this blue is busy with bloom.
- Mosaic red (`#D42F25` light, `#E8453A` dark) is the Kennfarbe: buttons,
  the record marker, lit meter tiles.
- Meadow green (`#6BBF59`) is a second accent, and is reserved for one
  job: the *live / OK* state. Red is always action, green is always
  "running".

## Palette

| Token | Light | Dark |
|---|---|---|
| `background` | `#FAF8F3` | `#0F1B3D` |
| `backgroundRaised` | `#F0EEE8` | `#142350` |
| `surface` | `#FFFFFF` | `#172856` |
| `surfaceSunken` | `#E7E5DF` | `#203468` |
| `canvas` | `#FAF8F3` | `#0A1230` |
| `canvasLabel` | `#0F1B3D` | `#FFFFFF` |
| `separator` | `#D3D1CB` | `#324A85` |
| `grout` | `#DCDAD3` | `#2A3E75` |
| `label` | `#0F1B3D` | `#FFFFFF` |
| `labelSecondary` | `#3B4670` | `#C9D2EA` |
| `labelTertiary` | `#56608A` | `#A0ACD0` |
| `kennfarbe` | `#D42F25` | `#E8453A` |
| `onKennfarbe` | `#FFFFFF` | `#000000` |
| `meadow` (status · live) | `#6BBF59` | `#6BBF59` |

## Spectral ramp

```
0.00  night-road    #0A1230
0.12  wall-blue     #15265C
0.25  teal-dusk     #1F5A6E
0.38  meadow-deep   #3E8F55
0.50  meadow        #8DBF3F
0.62  buttercup     #F0C419
0.76  poppy-orange  #F07A1E
0.88  mosaic-red    #E0352B
1.00  bloom-white   #FFF4EC
```

The ramp follows the carriage ride: night road, then meadow, flowers in
bloom, and a white blossom at the peak. It is deliberately rainbow-like.
Offer it as a fun colormap, and keep Viridis as the default for
measurement.

## Motif: bloom mosaic

The Home Screen wall (never chart canvases) gets a sparse four-petal
flower made of 6pt squares: four `kennfarbe` petals around a `canvasLabel`
centre. It repeats on a 96pt diagonal grid at 10–15 % opacity. Chart
canvases keep the plain tile grout so data stays readable. It is
decorative only and turns off under Reduce Transparency.

## Typography

- Titles and the hero value use **SF Pro Rounded** (`.rounded`), bold,
  for the postmodern and friendly register.
- Body and readouts stay SF Pro with tabular digits.

## Departures from Ferrite

- Two accent colours. Green is only ever the live state, so it never
  competes with the Kennfarbe.
- Rounded type.
- `FerriteRadius.card` goes from 0 to 6pt. It is still tiled, but softer.

## Best used for

Kids and classroom use, the tone generator and piano, and anyone who
wants the app to feel like a toy and an instrument at once.
