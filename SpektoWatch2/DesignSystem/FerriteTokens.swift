import SwiftUI
import UIKit

// MARK: - Ferrite design system
//
// Taken from the platform of U-Bahnhof Paradestraße in Berlin: a wide hall
// of small square white tiles, crisp black signage, and accent tiles in the
// colours of the Berlin U-Bahn lines.
//
// The one rule: black and white tile, with line colours as accents.
// Surfaces and text are only `background`, `label` and the quiet greys.
// Colour comes only from the nine `FerriteLine` colours, and only as fills
// (a tile, a bar, a chip, a button) — never text, rules or the focus ring.
// No glow, no scanlines, no mono face. Liquid glass is for the floating
// navigation layer only. State is carried by words, fills, patterns and
// shapes; colour may reinforce it, but only as an accent fill (a marker,
// a tile, a bar) beside the word or shape — never as text or rules.
//
// Mirrors the "Ferrite" design-system artifact (tokens.json); every token
// there names its counterpart here.

// MARK: - Dynamic color helper

extension Color {
    /// A color that resolves per trait collection, so it follows both the
    /// system appearance and `.preferredColorScheme(_:)` overrides.
    init(ferriteLight light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(ferriteHex: dark, alpha: darkAlpha)
                : UIColor(ferriteHex: light, alpha: lightAlpha)
        })
    }

    /// Same value in both themes.
    init(ferrite hex: UInt32) {
        self.init(ferriteLight: hex, dark: hex)
    }
}

private extension UIColor {
    convenience init(ferriteHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: - Neutrals
//
// Pure: white tile and black ink in light, black tile and white ink in dark.
enum FerriteColor {
    /// `bg-base` — the screen behind everything.
    static let background       = Color(ferriteLight: 0xFFFFFF, dark: 0x000000)
    /// `bg-raised` — grouped lists and sheets, one step off the base.
    static let backgroundRaised = Color(ferriteLight: 0xF5F5F5, dark: 0x0D0D0D)
    /// `surface` — cards and grouped cells; always drawn with a 1pt `label` outline.
    static let surface          = Color(ferriteLight: 0xFFFFFF, dark: 0x0A0A0A)
    /// `surface-sunken` — nested fills: fields, segmented tracks, pressed rows, unlit meter tiles.
    static let surfaceSunken    = Color(ferriteLight: 0xEBEBEB, dark: 0x1C1C1C)
    /// `canvas` — chart canvases: the tiled platform wall. Follows the theme.
    static let canvas           = Color(ferriteLight: 0xFFFFFF, dark: 0x000000)
    /// Canvas forced dark (Tweaks › "Diagramm (heller Modus)": dark), any theme.
    static let canvasDark       = Color(ferrite: 0x000000)

    /// `separator` — list separators and dividers between rows.
    static let separator        = Color(ferriteLight: 0xD4D4D4, dark: 0x333333)
    /// `grout` — tile joints on canvases and tiled grounds. Decorative only.
    static let grout            = Color(ferriteLight: 0xD9D9D9, dark: 0x2A2A2A)
    /// Grout on a forced-dark canvas.
    static let groutDark        = Color(ferrite: 0x2A2A2A)
    /// `hairline` — quiet outline for swatches and chips where a full
    /// `label` outline would be too loud.
    static let hairline         = Color(ferriteLight: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.12, darkAlpha: 0.16)

    /// `label` — primary text, card outlines, traces, lit meter tiles.
    static let label            = Color(ferriteLight: 0x000000, dark: 0xFFFFFF)
    /// `label-secondary` — units, supporting text, tick labels.
    static let labelSecondary   = Color(ferriteLight: 0x4D4D4D, dark: 0xB3B3B3)
    /// `label-tertiary` — status lines, timestamps, placeholders, STANDBY.
    static let labelTertiary    = Color(ferriteLight: 0x666666, dark: 0x999999)

    /// `accent` — pure ink. Focus ring and selection are always ink.
    static let accent           = Color(ferriteLight: 0x000000, dark: 0xFFFFFF)
    /// `on-accent` — text and icons on a filled accent.
    static let onAccent         = Color(ferriteLight: 0xFFFFFF, dark: 0x000000)
}

// MARK: - Line colour (user-selectable)
//
// Ink (default) or one of the nine Berlin U-Bahn line colours. The chosen
// line colours primary buttons, the eyebrow tile marker, card top bars,
// lit meter tiles and the prominent glass button. One line per screen.
enum FerriteLine: String, CaseIterable, Identifiable, Sendable {
    case ink, u1, u2, u3, u4, u5, u6, u7, u8, u9

    static let storageKey = "ferrite.line"
    static let `default`: FerriteLine = .ink

    var id: String { rawValue }

    /// Line number 1…9, `nil` for ink.
    var number: Int? {
        switch self {
        case .ink: return nil
        case .u1: return 1
        case .u2: return 2
        case .u3: return 3
        case .u4: return 4
        case .u5: return 5
        case .u6: return 6
        case .u7: return 7
        case .u8: return 8
        case .u9: return 9
        }
    }

    /// "Ink", "U1" … "U9".
    var label: String { number.map { "U\($0)" } ?? "Ink" }

    /// `line-*` fill. Ink is `accent`.
    var color: Color {
        switch self {
        case .ink: return FerriteColor.accent
        case .u1:  return Color(ferrite: 0x5CC23A)                      // green
        case .u2:  return Color(ferrite: 0xFF3B1F)                      // red
        case .u3:  return Color(ferrite: 0x00A06A)                      // dark green
        case .u4:  return Color(ferrite: 0xFFDE00)                      // yellow
        case .u5:  return Color(ferriteLight: 0xA0581C, dark: 0xC06A24) // brown
        case .u6:  return Color(ferrite: 0x9A4FE0)                      // purple
        case .u7:  return Color(ferrite: 0x2F9BFF)                      // blue
        case .u8:  return Color(ferriteLight: 0x1C5FD9, dark: 0x3D7DFF) // dark blue
        case .u9:  return Color(ferrite: 0xFF7A00)                      // orange
        }
    }

    /// `on-line-*` — text and icons on the filled line colour (≥ 4.5:1).
    var onColor: Color {
        switch self {
        case .ink: return FerriteColor.onAccent
        case .u5, .u8: return Color(ferriteLight: 0xFFFFFF, dark: 0x000000)
        case .u6: return Color(ferrite: 0xFFFFFF)
        default: return Color(ferrite: 0x000000)
        }
    }

    /// The nine line colours in order (no ink).
    static let lines: [FerriteLine] = [.u1, .u2, .u3, .u4, .u5, .u6, .u7, .u8, .u9]
}

// MARK: - Grey band
//
// `band-0` … `band-9`: ten grey steps, the Paradestraße colour series in
// black and white. Contrast against `background` rises with the number.
enum FerriteBand {
    static let steps: [Color] = [
        Color(ferriteLight: 0xF2F2F2, dark: 0x141414),
        Color(ferriteLight: 0xE0E0E0, dark: 0x262626),
        Color(ferriteLight: 0xCCCCCC, dark: 0x383838),
        Color(ferriteLight: 0xB3B3B3, dark: 0x4D4D4D),
        Color(ferriteLight: 0x999999, dark: 0x666666),
        Color(ferriteLight: 0x808080, dark: 0x808080),
        Color(ferriteLight: 0x666666, dark: 0x9E9E9E),
        Color(ferriteLight: 0x4D4D4D, dark: 0xBDBDBD),
        Color(ferriteLight: 0x262626, dark: 0xDEDEDE),
        Color(ferriteLight: 0x000000, dark: 0xFFFFFF),
    ]

    static func step(_ index: Int) -> Color { steps[min(max(index, 0), steps.count - 1)] }
}

// MARK: - Status accents
//
// State colours, taken from the line palette so nothing introduces a hue
// outside the system. Accent fills only — badge markers, meter tiles,
// recording dots, chart zone fills — always beside a word, pattern or
// shape that carries the same state. Never text, rules or outlines.
enum FerriteStatus {
    static let live      = FerriteLine.u1.color
    static let recording = FerriteLine.u2.color
    static let warning   = FerriteLine.u9.color
    static let info      = FerriteLine.u7.color
}

// MARK: - Liquid glass
//
// Floating navigation layer only (bars, nav buttons, sheets over content).
// On iOS 26 the system `.glassEffect()` draws it; these values are the
// fallback and match its black-and-white look.
enum FerriteGlass {
    static let fill       = Color(ferriteLight: 0xFFFFFF, dark: 0x141414, lightAlpha: 0.70, darkAlpha: 0.70)
    static let fillStrong = Color(ferriteLight: 0xFFFFFF, dark: 0x141414, lightAlpha: 0.86, darkAlpha: 0.86)
    static let stroke     = Color(ferriteLight: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.14, darkAlpha: 0.18)
    /// `shadow-glass` — the ambient part of `FerriteElevation.floating`.
    static let shadow     = Color(ferriteLight: 0x000000, dark: 0x000000, lightAlpha: 0.12, darkAlpha: 0.60)
}

// MARK: - Depth (spatial light)
//
// One light source, above and slightly to the leading side. It gives
// glass and Home Screen icons a lit rim along the top, a faint reflection
// on the far edge, a bevel shade on the lower inner edge, and a two-part
// drop shadow (a tight contact shadow plus a wide ambient one) so they
// read as objects floating at different heights over the tile wall.
// Decorative only, never meaning; off under Reduce Transparency.
enum FerriteDepth {
    /// Specular rim along the lit (top) edge.
    static let rimLight   = Color(ferriteLight: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.95, darkAlpha: 0.50)
    /// Reflected light on the far (bottom) edge.
    static let rimReflect = Color(ferriteLight: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.45, darkAlpha: 0.16)
    /// Bevel shade on the lower inner edge.
    static let bevelShade = Color(ferriteLight: 0x000000, dark: 0x000000, lightAlpha: 0.08, darkAlpha: 0.40)
    /// Sheen over the upper half of a glass surface or icon.
    static let sheen      = Color(ferriteLight: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.30, darkAlpha: 0.08)
    /// Sheen on solid ink icons (stronger, the ink absorbs it).
    static let iconSheen  = Color(ferriteLight: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.22, darkAlpha: 0.30)
    /// Lit rim width (inside the shape).
    static let rimWidth: CGFloat = 1
    /// Bevel shade width (inside the shape).
    static let bevelWidth: CGFloat = 2.5
}

/// How high a surface floats. Shadows are drawn from the static shape
/// only (`FerriteDropShadow`), so live content inside never re-renders them.
struct FerriteElevation: Sendable {
    var contactColor: Color
    var contactRadius: CGFloat
    var contactY: CGFloat
    var ambientColor: Color
    var ambientRadius: CGFloat
    var ambientY: CGFloat

    /// Home Screen icons and widgets: resting on the wall.
    static let raised = FerriteElevation(
        contactColor: Color(ferriteLight: 0x000000, dark: 0x000000, lightAlpha: 0.14, darkAlpha: 0.60),
        contactRadius: 1.5, contactY: 1,
        ambientColor: Color(ferriteLight: 0x000000, dark: 0x000000, lightAlpha: 0.10, darkAlpha: 0.50),
        ambientRadius: 10, ambientY: 6
    )

    /// Navigation glass: bars, dock, glass buttons — the highest layer.
    static let floating = FerriteElevation(
        contactColor: Color(ferriteLight: 0x000000, dark: 0x000000, lightAlpha: 0.12, darkAlpha: 0.55),
        contactRadius: 2, contactY: 1.5,
        ambientColor: FerriteGlass.shadow,
        ambientRadius: 22, ambientY: 14
    )
}

// MARK: - Typography
//
// SF Pro only, one family, no mono, no serif. Titles, headlines and the
// hero are bold like station signage. All styles are Dynamic Type text
// styles so they scale; numerals use tabular digits so values don't jitter.
enum FerriteFont {
    static let largeTitle = Font.largeTitle.weight(.bold)
    static let title      = Font.title2.weight(.bold)
    static let headline   = Font.headline.weight(.bold)
    static let body       = Font.body
    static let callout    = Font.callout
    static let footnote   = Font.footnote
    static let caption    = Font.caption

    /// Uppercase bold platform-sign label. Pair with `FerriteTracking.eyebrow`.
    static let eyebrow    = Font.caption.weight(.bold)
    /// Units next to a readout ("dB(A)", "Hz").
    static let unit       = Font.footnote
    /// Inline values in rows and tickers.
    static let readout    = Font.body.weight(.bold).monospacedDigit()
    /// Axis ticks, canvas annotations, status lines.
    static let tick       = Font.caption2.weight(.medium).monospacedDigit()

    /// The one big value on a card: bold, tight tracking, tabular digits.
    static func hero(_ size: CGFloat = 64) -> Font {
        .system(size: size, weight: .bold).monospacedDigit()
    }
}

enum FerriteTracking {
    static let eyebrow: CGFloat = 1.2
    static let unit: CGFloat = 0.2
    static let tick: CGFloat = 0.4
    /// Hero tracking: -1.5pt at 64pt, scaled for other sizes.
    static func hero(_ size: CGFloat = 64) -> CGFloat { -1.5 * size / 64 }
}

// MARK: - Spacing, radius, stroke

enum FerriteSpace {
    static let xxs: CGFloat = 2
    static let xs: CGFloat  = 4
    static let s: CGFloat   = 8
    static let m: CGFloat   = 12
    /// Card padding and screen side margin.
    static let l: CGFloat   = 16
    /// One tile: the grout pitch, the band height, the gap between card groups.
    static let xl: CGFloat  = 24
    /// Two tiles: top of a screen to its first card.
    static let xxl: CGFloat = 48

    /// The tile pitch (same as `xl`).
    static let tile: CGFloat = 24
}

enum FerriteRadius {
    /// Cards and widget tiles: square.
    static let card: CGFloat    = 0
    /// Chart canvases: square.
    static let canvas: CGFloat  = 0
    /// Buttons, badges, fields and chips: a tile's slight edge.
    static let tile: CGFloat    = 2
    /// Floating glass panels and large glass buttons.
    static let glass: CGFloat   = 28
    /// Top corners of a glass sheet.
    static let sheet: CGFloat   = 34

    // The in-app Home Screen takes the iOS Home Screen's shapes (the one
    // place Ferrite rounds surfaces); colours stay Ferrite.
    /// Home Screen widgets (iOS widget corner).
    static let homeWidget: CGFloat = 24
    /// Home Screen app icon corner for a given icon size (iOS squircle ratio).
    static func homeIcon(_ size: CGFloat) -> CGFloat { (size * 0.225).rounded() }
    /// The Home Screen dock.
    static let dock: CGFloat = 32
}

enum FerriteStroke {
    /// `border-hair` — card, canvas and band outlines, grout lines.
    static let hairline: CGFloat = 1
    /// `border-line` — badges, secondary buttons, selection, focus ring.
    static let line: CGFloat = 2
    /// `border-bar` — the heavy rule on a station-sign eyebrow or card header.
    static let bar: CGFloat = 6
}

// MARK: - Motion

enum FerriteMotion {
    /// UI transitions — 0.28s snappy.
    static let standard = Animation.snappy(duration: 0.28)
    /// Data changes (meter fills, value ticks) — 0.18s ease-out.
    static let data     = Animation.easeOut(duration: 0.18)
    /// REC marker blink half-period (1.06s cycle). The only repeating
    /// motion; it stops under Reduce Motion.
    static let blinkHalfPeriod: Double = 0.53
}

// MARK: - Environment

private struct FerriteLineKey: EnvironmentKey {
    static let defaultValue: FerriteLine = .default
}

extension EnvironmentValues {
    /// The line colour in use for this subtree (`data-line` on the web).
    var ferriteLine: FerriteLine {
        get { self[FerriteLineKey.self] }
        set { self[FerriteLineKey.self] = newValue }
    }
}

/// Reads the persisted line choice and injects it into the subtree. Tint
/// stays ink: line colours never colour text or control foregrounds.
struct FerriteThemeRoot: ViewModifier {
    @AppStorage(FerriteLine.storageKey) private var lineRaw = FerriteLine.default.rawValue

    func body(content: Content) -> some View {
        let line = FerriteLine(rawValue: lineRaw) ?? .default
        content
            .environment(\.ferriteLine, line)
            .tint(FerriteColor.accent)
    }
}

extension View {
    func ferriteTheme() -> some View { modifier(FerriteThemeRoot()) }

    /// Override the line colour for one element or screen.
    func ferriteLine(_ line: FerriteLine) -> some View {
        environment(\.ferriteLine, line)
    }
}
