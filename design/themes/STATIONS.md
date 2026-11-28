# Station themes

Ferrite's default look comes from the platform of **U-Bahnhof
Paradestraße**: white square tiles, black signage, U-line colours as
accents. Each theme here takes a different Berlin station as its source,
in the same way.

| Theme | Line | Source | Kennfarbe | Ground | Type | Motif |
|---|---|---|---|---|---|---|
| Paradestraße *(default)* | U6 | white tile hall | ink | white / black | SF Pro | square tile |
| [Museumsinsel](museumsinsel.md) | U5 | Dudler's star vault (2021) | starlight `#F2C14E` | night blue, canvas always night | New York titles | star field |
| [Märkisches Museum](maerkisches-museum.md) | U2 | Grenander's green glazed tile (1913) | glaze `#2E6B4F` | cream / green-black | SF Pro | running bond, green frame |
| [Paulsternstraße](paulsternstrasse.md) | U7 | Rümmler's flower mosaic (1984) | mosaic red `#D42F25` + meadow | flower white / dark blue | SF Rounded | bloom mosaic |
| [Heidelberger Platz](heidelberger-platz.md) | U3 | Leitgebel's chandelier vault (1913) | brass `#B8862B` | lime plaster / smoke stone | New York titles | groined vault |
| [Schlesisches Tor](schlesisches-tor.md) | U1 | riveted elevated viaduct (1902) | brick `#A6402A` | sandstone / steel | SF Condensed | rivet line |

## Shared rules

- **Same token slots as `FerriteColor`**, plus `canvasLabel` and
  `kennfarbe` / `onKennfarbe`. A theme swaps values, not structure. The
  machine-readable values are in
  [`station-themes.tokens.json`](station-themes.tokens.json).
- **The Kennfarbe replaces ink as the default line colour.** The U1–U9
  picker still works on top of any theme.
- **Status keeps meaning:** live, recording, warning and info still come
  from the U-line palette (`FerriteStatus`), always next to a word or
  shape. Paulsternstraße is the one exception: its meadow green carries
  *live*.
- **Contrast, checked for every pair:** `label` ≥ 7:1 and
  `labelSecondary` / `labelTertiary` ≥ 4.5:1 on all four grounds
  (`background`, `backgroundRaised`, `surface`, `surfaceSunken`).
  `onKennfarbe` ≥ 4.5:1 on `kennfarbe`. `canvasLabel` ≥ 13:1 on
  `canvas`.
- **Motifs are decoration.** They never carry meaning and they turn off
  under Reduce Transparency, like Ferrite's depth effects.
- **Type stays native.** Every title variant (`.serif`, `.rounded`,
  `.width(.condensed)`) is a built-in SF design, so no fonts need to be
  bundled.
- **Spectral ramps are optional colormaps.** Viridis, Inferno and Magma
  stay the scientific defaults. Each station ramp is offered as an extra
  colormap that goes with its theme.
