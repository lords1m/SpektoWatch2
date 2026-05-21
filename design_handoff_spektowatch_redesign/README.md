# SpektoWatch — UX Redesign Handoff

## Overview

This bundle contains a redesign of the SpektoWatch iOS app — a scientific audio measurement instrument (spectrogram, waterfall, LAF time-series, frequency spectrum, level meter, tone generator, masking, FFT lab) and its accompanying Apple Watch app + Complications.

The goals of the redesign were:

1. **Scientific clarity** — every measurement should be unambiguous at a glance
2. **iOS 26 Liquid Glass aesthetic** — translucent layered surfaces, subtle highlights, generous backdrop blur
3. **Highly customizable** — theme, accent, density, numerals, colormap all live-toggleable
4. **Consistent visual language** across charts — every widget canvas is a dark scientific instrument display, regardless of theme

## About the Design Files

The files in this bundle are **design references created in HTML** — interactive prototypes showing the intended look and behaviour. They are **not production code to copy directly**.

The existing SpektoWatch app is built in **SwiftUI** for iOS and watchOS. The task is to **recreate these HTML designs in SwiftUI** using the codebase's existing patterns (Liquid Glass via `.glassEffect()`, `Material.thinMaterial`, `.background(.regularMaterial)`, etc.). Component implementations like `ChartRenderer`, `SpectrogramView`, `WaterfallView`, `LAFGraphView`, `SingleValueWidget`, `ToneGeneratorWidget`, and `ControlBarView` already exist — the redesign primarily changes their **chrome, header, transport, theming, and navigation**, not the rendering kernels.

## Fidelity

**High-fidelity.** The mockups are pixel-precise with final colors, typography, spacing, border-radii, shadows, and motion behaviours. Recreate them in SwiftUI exactly:

- All measurements (paddings, gaps, radii) are in the HTML CSS — use them as-is
- All colors are in **OKLCH** — map to SwiftUI `Color(hue:saturation:brightness:)` or use the existing palette tokens
- Typography uses **Inter** (UI) and **JetBrains Mono** (numerals); on iOS use **SF Pro** + **SF Mono** (already system-default)

## Screens / Views

### 1. Dashboard Shell

The new dashboard chrome consists of:

#### 1a. Floating Header Pill
- **Position:** top of screen, 16pt margin all sides, sits below the iOS status bar (~62pt from top)
- **Material:** `.regularMaterial` + subtle inner highlight + 28pt corner radius
- **Layout:** two-column flex; left: title stack; right: 3 icon buttons
- **Left content:**
  - Eyebrow: `DASHBOARD · LIVE` — 9pt, JetBrains Mono, letter-spacing 0.18em, uppercase, color `secondaryLabel` (oklch 0.50)
  - Title: current preset name — 17pt, Inter SemiBold, letter-spacing -0.02em, `label` color
- **Right content:** three 34pt circular glass icon buttons: gear (Einstellungen), layers (Layouts), pencil (Bearbeiten)
- **Edit-mode variant:**
  - Eyebrow text changes to `LAYOUT BEARBEITEN`
  - Gear + layers icons hide
  - Pencil icon becomes a green Checkmark "Done" button with accent fill

#### 1b. Preset Rail (horizontal scrolling pill bar)
- **Position:** directly below header (~130pt from screen top), full width, horizontal scroll
- **Pill chips:** 8pt vertical / 14pt horizontal padding, `pill` shape, 12pt Inter Medium label
- **Default chip:** background `oklch(0.22 0.015 255)` (very dark navy), border `oklch(0.45 0.012 255)`, text `oklch(0.92 0.005 255)`
- **Active chip:** solid accent fill (`oklch(0.84 0.18 145)` phosphor green by default), dark text, +`box-shadow: 0 0 16px accent/30%` glow
- **All 11 presets:** Übersicht · Spektrogramm · Wasserfall · Pegelverlauf · Frequenz-Spektrum · Phasen-Meter · Pegel-Meter · Einzelwert · Tongenerator · Sound Masking · Spektralanalyse-Labor
- The bar scrolls horizontally — no dot indicators (the named chips replace them)

#### 1c. Compact Transport Bar
- **Position:** bottom of screen, 16pt margin, ~44pt above the iOS home indicator
- **Material:** `.regularMaterial`, 24pt corner radius, 8/10/8/16pt padding
- **Layout:** two-column; left: LED + status text; right: 3 round buttons (Play/Pause, Record/Stop, Folder)
- **LED:** 6pt circle — gray default; pulsing accent-green when "Live"; solid red when "Rec"
- **Status text:** 12pt Inter, with a 11pt JetBrains Mono cursor `00:14.2` — tabular nums
- **Buttons:** 38pt round, neutral glass background; Play turns accent when active; Record turns red-tinted when recording

### 2. Widget Card

Every chart/metric card uses the same chrome:

- **Outer card:** `.regularMaterial` background, 22pt corner radius, 14pt padding, 10pt gap between header and content
- **Header:** flex row, baseline-aligned
  - Title (left): 12pt icon + 10pt JetBrains Mono uppercase label, letter-spacing 0.18em, `secondaryLabel`
  - Meta (right): 10pt JetBrains Mono numerics — main metric value bold (`label`), units dim (`tertiaryLabel`)
- **Inner canvas:** ALWAYS dark, regardless of light/dark theme. Background:
  ```
  radial-gradient(120% 80% at 50% 0%, oklch(0.16 0.03 250 / 0.4), transparent 60%),
  linear-gradient(180deg, oklch(0.10 0.015 255), oklch(0.07 0.012 255))
  ```
  14pt corner radius, hairline border `oklch(0.30 0.02 255 / 0.4)`. Rationale: scientific data renders against a calibrated dark substrate — perceptually-uniform colormaps (viridis/inferno/magma) are designed for dark backgrounds.

### 3. Presets (Widget Compositions)

| ID | Title | Primary visualization |
|---|---|---|
| `overview` | Übersicht | 4 stacked: Hero LAF · LAF Verlauf · Spektrogramm Mini · Stereo L/R |
| `spectrogram` | Spektrogramm | Full-bleed STFT canvas + Y-axis (20k → 31 Hz) + readout pill |
| `waterfall` | Wasserfall | 3D ridge plot, viridis/inferno per row |
| `level-time` | Pegelverlauf | LAF time series with phosphor fill, 5s window |
| `spectrum` | Frequenz-Spektrum | Instantaneous spectrum, log x-axis, 1/3 octave |
| `level-meter` | Pegel-Meter | Two horizontal meters with color zones |
| `single` | Einzelwert | 2×2 grid of huge readouts |
| `tone` | Tongenerator | Oscilloscope + freq slider + preset chips + wave-shape segmented |
| `phase` | Phasen-Meter | Lissajous goniometer + empty state for mono signal |
| `masking` | Sound Masking | Bar chart per source + per-source state pills |
| `lab` | Spektralanalyse-Labor | Tabbed FFT config: Blockgröße, Fenster, Overlap, Δf/Δt/Bins metrics |

#### Readout Pill (inside canvases)
- Position: top-right of canvas, 10pt offset
- Background: `oklch(0 0 0 / 0.55)` + 10pt blur, 10pt corner radius
- Content: 10pt JetBrains Mono, tabular nums, 9pt uppercase labels in `tertiaryLabel` color
- Min-width 96pt; rows: label (left) — value (right)

### 4. Edit Mode

Triggered by pencil icon in header. Behaviours:

- Header switches: eyebrow → `LAYOUT BEARBEITEN`; gear+layers icons hide; pencil → green checkmark "Done"
- Every widget card animates a subtle `±0.4°` rotation jiggle (iOS-style; alternating delays per card)
- Card border switches to accent color with subtle outer glow (`box-shadow: 0 0 0 1px accent/20%`)
- Each card gets two floating handles:
  - **Top-left, accent-filled, 28pt circle:** drag handle (grip dots), `cursor: grab`
  - **Top-right, red-filled, 28pt circle:** delete X
- Preset rail + transport bar + canvas readouts dim to 35% opacity
- Below the widget list, a dashed-border "+ Widget hinzufügen" button appears, accent-colored, calls `openWidgetPicker()`

### 5. Tweaks (Live Customization)

A floating panel (top-right toggle in iOS app; bottom-right in the design preview) lets the user toggle:

- **Theme:** Dark (default) / Light
- **Canvas in light theme:** Light / Dark (lets scientific viewers keep dark canvas in a light UI)
- **Accent:** Phosphor (default `oklch 0.84 0.18 145`) / Amber / Cyan / Magenta / Paper
- **Density:** Compact / Standard / Luftig (changes padding + gaps)
- **Numerals:** Mono (JetBrains Mono) / Sans (SF Pro)
- **Colormap:** Viridis / Inferno / Magma

These should map to `@AppStorage` properties in SwiftUI.

### 6. Apple Watch — 3 Watch Faces

#### 6a. Pegelmesser
- Big LAF number (64pt Inter Light, accent color), unit "dB(A)"
- Peak bar at bottom (color gradient green→yellow→red)
- MIN/MAX values below

#### 6b. Spektrogramm
- Full-screen STFT canvas (viridis)
- Top status bar: pulsing LED · time · "STFT" label
- Bottom strip: "● STFT · 1024"

#### 6c. Tongenerator
- "FREQUENZ" label · big "1.00 kHz"
- Mini sine wave with glow filter
- "PAUSE" button (red-tinted) + λ wavelength readout

### 7. Apple Watch — Complications

Five complication slots, all using JetBrains Mono numerals + accent green:

| Slot | Layout |
|---|---|
| **Circular Small** | Arc progress around centered "50 dB(A)" |
| **Corner / Modular** | "LAF · slow" label, big "50.2", peak bar |
| **Rectangular / Smart Stack** | Full strip: live LAF + sparkline + Leq/Lmax/Δ stats |
| **Inline (Modular Face)** | "SPEKTO  50.2 dB(A) ┃ peak 78" — single horizontal pill |
| **Graphic Bezel** | Arc + center number + sidebar with A-bewertet / Leq / Lmax |

### 8. Apple Watch — Modular 4-Slot Face

Four data slots in one face:
1. Hero LAF (big number)
2. Mini spectrogram strip (32pt tall)
3. PEAK (small tile)
4. Leq (small tile)

## Interactions & Behavior

- **Preset switching:** tap any chip in the rail; rail scrolls to center the selected chip; content cross-fades
- **Edit mode:** tap pencil → all cards jiggle, handles appear, transport+rail dim; tap green check → snap back to live
- **Add widget:** dashed button opens a sheet (not designed yet; implement as standard SwiftUI sheet with widget list grouped by category)
- **Drag-reorder:** standard `.onDrag` / `.onDrop` in SwiftUI; haptic on pickup
- **Delete:** tap red X → confirmation toast (`Widget entfernt · Rückgängig`); 4-second auto-dismiss
- **Tweaks panel:** floating top-right gear → modal sheet on small screens, popover on larger; persist via `@AppStorage`

## State Management

```swift
// AppStorage-backed user preferences
@AppStorage("theme") var theme: ThemeMode = .dark
@AppStorage("accent") var accent: AccentColor = .phosphor
@AppStorage("density") var density: Density = .standard
@AppStorage("numerals") var numerals: NumeralStyle = .mono
@AppStorage("colormap") var colormap: Colormap = .viridis
@AppStorage("canvasInLight") var canvasInLight: CanvasMode = .light

// Per-dashboard state
@State var activePresetID: String = "overview"
@State var editingLayout: Bool = false
@State var playing: Bool = false
@State var recording: Bool = false
```

## Design Tokens

### Color (OKLCH; convert via existing palette tools)

| Token | Dark theme | Light theme |
|---|---|---|
| `bg-1`     | `oklch(0.13 0.02 255)`  | `oklch(0.97 0.003 255)` |
| `bg-2`     | `oklch(0.10 0.018 255)` | `oklch(0.94 0.004 255)` |
| `bg-3`     | `oklch(0.07 0.014 255)` | `oklch(0.91 0.005 255)` |
| `fg`       | `oklch(0.96 0.005 255)` | `oklch(0.15 0.01 255)` |
| `fg-muted` | `oklch(0.70 0.01 255)`  | `oklch(0.40 0.01 255)` |
| `fg-dim`   | `oklch(0.50 0.012 255)` | `oklch(0.55 0.01 255)` |

### Accent options

| Name | OKLCH |
|---|---|
| Phosphor (default) | `oklch(0.84 0.18 145)` |
| Amber              | `oklch(0.82 0.16 80)`  |
| Cyan               | `oklch(0.82 0.14 220)` |
| Magenta            | `oklch(0.78 0.18 340)` |
| Paper              | `oklch(0.92 0.005 255)` |

### Signal palette (perceptually-uniform; do NOT theme)

| Stop | OKLCH |
|---|---|
| Noise floor | `oklch(0.30 0.10 270)` |
| Mid         | `oklch(0.65 0.18 200)` |
| Hi          | `oklch(0.82 0.18 145)` |
| Peak        | `oklch(0.78 0.20 60)`  |
| Clip        | `oklch(0.65 0.24 25)`  |

### Spacing & Geometry

- Card corner radius: `22pt`
- Pill corner radius: `999pt`
- Chip corner radius: `12pt`
- Inner canvas radius: `14pt`
- Hairline: `0.5pt`
- Card padding: `14pt` (compact `10pt`, airy `18pt`)
- Card gap: `12pt` (compact `8pt`, airy `16pt`)

### Typography Scale

| Use | Family | Size | Weight | Letter spacing |
|---|---|---|---|---|
| Hero number | SF Pro Display | 56pt | 200 | -0.04em |
| Widget meta | SF Mono | 10pt | 400 | 0.05em |
| Widget title (eyebrow) | SF Mono | 10pt | 400 | 0.18em uppercase |
| Header title | SF Pro Text | 17pt | 600 | -0.02em |
| Header eyebrow | SF Mono | 9pt | 400 | 0.18em uppercase |
| Preset chip | SF Pro Text | 12pt | 500 | -0.005em |
| Tab/segmented | SF Mono | 11pt | 400 | 0.04em |
| Axis tick | SF Mono | 9pt | 400 | 0.02em |
| Big readout (single value) | SF Pro Display | 56pt | 200 | -0.04em |

### Shadow / Material

Liquid glass = `.regularMaterial` with these augmentations:

```swift
.background(.regularMaterial)
.overlay( // inner highlight
  RoundedRectangle(cornerRadius: 22)
    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
)
.shadow(color: Color.black.opacity(0.6), radius: 20, y: 10)
```

## Assets

No external image assets used. All visualizations are rendered:
- **Spectrogram:** Metal kernel (existing `HighEndSpectrogramAdapter.swift`)
- **Waterfall:** Existing `WaterfallDataBuilder` + custom SwiftUI shape
- **Charts:** Swift Charts framework or existing `ChartRenderer`
- **Icons:** SF Symbols (existing — the HTML uses Lucide-style inline SVGs as stand-ins; substitute SF Symbols by category)
  - Gear → `gearshape.fill`
  - Layers → `square.stack.3d.up`
  - Edit → `square.and.pencil`
  - Spectrogram → `waveform.path.ecg`
  - Frequency → `chart.bar`
  - Tone → `waveform`
  - Phase → `circle.lefthalf.filled`
  - Single value → `123.rectangle`
  - Grid → `square.grid.2x2`
  - Lab → `atom`

## Files in this bundle

- `SpektoWatch Redesign.html` — Main app prototype (interactive; preset rail + edit mode + tweaks)
- `SpektoWatch Watch + Complications.html` — Watch faces + 5 complications + Modular face
- `styles.css` — All design tokens & shared CSS
- `app.jsx` — Top-level app + tweaks wiring
- `app-core.jsx` — Icon library, header, preset rail, transport, widget chrome
- `screens.jsx` — All 11 preset screen implementations

These should be **read for reference** — the implementer should not ship the HTML.
