import SwiftUI

// MARK: - Eyebrow

/// Uppercase bold platform-sign label: "LEVEL · INPUT 01". Noun, then
/// qualifier, joined with " · ", under ~24 characters. The square tile
/// marker in the current line colour is the only coloured part.
struct FerriteEyebrow: View {
    enum Style {
        /// Square tile marker in the line colour (default).
        case marker
        /// Plain section header, `label-secondary`, no marker.
        case quiet
        /// Under a heavy 6pt ink rule, like the bar on a platform sign.
        case bar
    }

    let text: String
    var style: Style = .marker

    @Environment(\.ferriteLine) private var line

    init(text: String, style: Style = .marker) {
        self.text = text
        self.style = style
    }

    /// Compatibility: `showsMarker: false` is the quiet style.
    init(text: String, showsMarker: Bool) {
        self.init(text: text, style: showsMarker ? .marker : .quiet)
    }

    var body: some View {
        HStack(spacing: FerriteSpace.s) {
            if style == .marker {
                Rectangle()
                    .fill(line.color)
                    .frame(width: 8, height: 8)
                    .overlay(Rectangle().strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
                    .accessibilityHidden(true)
            }
            Text(text.uppercased())
                .foregroundStyle(style == .quiet ? FerriteColor.labelSecondary : FerriteColor.label)
        }
        .font(FerriteFont.eyebrow)
        .tracking(FerriteTracking.eyebrow)
        .lineLimit(1)
        .padding(.top, style == .bar ? FerriteSpace.s : 0)
        .overlay(alignment: .top) {
            if style == .bar {
                Rectangle().fill(FerriteColor.label).frame(height: FerriteStroke.bar)
                    .frame(maxWidth: .infinity)
                    .offset(y: -FerriteStroke.bar)
            }
        }
    }
}

// MARK: - Card

/// Standard container: `surface` fill, square corners, 1pt `label`
/// outline, no shadow. `isLined` adds a 6pt top bar in the line colour;
/// `isSelected` adds a 2pt inner ink line.
struct FerriteCard: ViewModifier {
    var padding: CGFloat = FerriteSpace.l
    var isLined: Bool = false
    var isSelected: Bool = false

    @Environment(\.ferriteLine) private var line

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .padding(.top, isLined ? FerriteStroke.bar : 0)
            .background(FerriteColor.surface)
            .overlay(alignment: .top) {
                if isLined {
                    Rectangle().fill(line.color).frame(height: FerriteStroke.bar)
                }
            }
            .overlay(Rectangle().strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
            .overlay {
                if isSelected {
                    Rectangle()
                        .strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.line)
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - Canvas

/// The tiled wall charts draw on: square, 1pt `label` outline, grout grid
/// every 24pt. Follows the theme (white tiles in light, black in dark)
/// unless `forceDark`. No scanlines, brackets or glow. Keep the height a
/// multiple of 24pt so the grid ends on a full tile.
struct FerriteCanvas: ViewModifier {
    var showsGrid: Bool = true
    var forceDark: Bool = false

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    forceDark ? FerriteColor.canvasDark : FerriteColor.canvas
                    if showsGrid {
                        FerriteTileGrid(color: forceDark ? FerriteColor.groutDark : FerriteColor.grout)
                    }
                }
            }
            .clipShape(Rectangle())
            .overlay(Rectangle().strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
            .modifier(ForcedDarkScheme(isActive: forceDark))
    }
}

/// Resolves the canvas subtree as dark only when the canvas is forced dark,
/// so traces drawn in `label` stay legible on it.
private struct ForcedDarkScheme: ViewModifier {
    let isActive: Bool
    func body(content: Content) -> some View {
        if isActive { content.environment(\.colorScheme, .dark) } else { content }
    }
}

extension View {
    func ferriteCard(padding: CGFloat = FerriteSpace.l, isLined: Bool = false, isSelected: Bool = false) -> some View {
        modifier(FerriteCard(padding: padding, isLined: isLined, isSelected: isSelected))
    }

    func ferriteCanvas(grid: Bool = true, forceDark: Bool = false) -> some View {
        modifier(FerriteCanvas(showsGrid: grid, forceDark: forceDark))
    }
}

// MARK: - Readout

/// The one big measurement on a card: bold numerals with tabular digits
/// in `label`, then the unit in `label-secondary`. Always print units.
struct FerriteReadout: View {
    let value: String
    let unit: String
    /// 64pt default; 40pt is the compact (`is-small`) size.
    var size: CGFloat = 64

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: FerriteSpace.s) {
            Text(value)
                .font(FerriteFont.hero(size))
                .tracking(FerriteTracking.hero(size))
                .foregroundStyle(FerriteColor.label)
                .contentTransition(.numericText())
            Text(unit)
                .font(FerriteFont.unit)
                .tracking(FerriteTracking.unit)
                .foregroundStyle(FerriteColor.labelSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Status badge

enum FerriteState {
    case live, recording, idle, warning

    /// Fixed status words: LIVE, REC, STANDBY, CLIP.
    var label: String {
        switch self {
        case .live:      return "Live"
        case .recording: return "Rec"
        case .idle:      return "Standby"
        case .warning:   return "Clip"
        }
    }

    /// Accent fill for the marker. STANDBY has none (hollow marker).
    var accent: Color? {
        switch self {
        case .live:      return FerriteStatus.live
        case .recording: return FerriteStatus.recording
        case .idle:      return nil
        case .warning:   return FerriteStatus.warning
        }
    }
}

/// Square label that shows what the instrument is doing. The word and the
/// form carry the state; the status colour is an accent on the marker only
/// (with an ink edge), never on the text or outline:
/// LIVE solid fill + square · REC 2pt outline + blinking round marker ·
/// STANDBY dashed tertiary outline + hollow marker · CLIP double outline +
/// triangle.
struct FerriteStatusBadge: View {
    let state: FerriteState

    private var ink: Color {
        switch state {
        case .live:  return FerriteColor.background
        case .idle:  return FerriteColor.labelTertiary
        default:     return FerriteColor.label
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FerriteRadius.tile, style: .continuous)
        HStack(spacing: FerriteSpace.s) {
            marker
            Text(state.label.uppercased())
                .font(FerriteFont.eyebrow)
                .tracking(FerriteTracking.eyebrow)
                .foregroundStyle(ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            if state == .live { shape.fill(FerriteColor.label) }
        }
        .overlay {
            switch state {
            case .idle:
                shape.strokeBorder(FerriteColor.labelTertiary,
                                   style: StrokeStyle(lineWidth: FerriteStroke.line, dash: [3, 2]))
            default:
                shape.strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.line)
            }
        }
        .padding(state == .warning ? 4 : 0)
        .overlay {
            if state == .warning {
                shape.strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.line)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.label)
    }

    @ViewBuilder
    private var marker: some View {
        let fill = state.accent ?? ink
        switch state {
        case .live:
            Rectangle().fill(fill)
                .overlay(Rectangle().strokeBorder(ink, lineWidth: FerriteStroke.hairline))
                .frame(width: 8, height: 8)
        case .recording:
            Circle().fill(fill)
                .overlay(Circle().strokeBorder(ink, lineWidth: FerriteStroke.hairline))
                .frame(width: 8, height: 8).ferriteBlink()
        case .idle:
            Rectangle().strokeBorder(ink, lineWidth: 1.5).frame(width: 8, height: 8)
        case .warning:
            ZStack {
                FerriteTriangle().fill(fill)
                FerriteTriangle().stroke(ink, lineWidth: FerriteStroke.hairline)
            }
            .frame(width: 9, height: 8)
        }
    }
}

// MARK: - Buttons

/// Full-width primary: solid line colour (ink by default) with `on-line`
/// text and a 2pt ink edge. Pressed 80% / 98%; disabled 40%.
struct FerritePrimaryButtonStyle: ButtonStyle {
    @Environment(\.ferriteLine) private var line
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: FerriteRadius.tile, style: .continuous)
        configuration.label
            .font(FerriteFont.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(line.onColor)
            .background(line.color, in: shape)
            .overlay(shape.strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.line))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
            .animation(FerriteMotion.standard, value: configuration.isPressed)
    }
}

/// Full-width secondary: ink text and a 2pt ink outline on the ground.
/// Pressed fills `surface-sunken`.
struct FerriteSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: FerriteRadius.tile, style: .continuous)
        configuration.label
            .font(FerriteFont.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(FerriteColor.accent)
            .background(configuration.isPressed ? FerriteColor.surfaceSunken : .clear, in: shape)
            .overlay(shape.strokeBorder(FerriteColor.accent, lineWidth: FerriteStroke.line))
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

extension ButtonStyle where Self == FerritePrimaryButtonStyle {
    static var ferritePrimary: FerritePrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == FerriteSecondaryButtonStyle {
    static var ferriteSecondary: FerriteSecondaryButtonStyle { .init() }
}

// MARK: - Meter

/// A level bar of 24 discrete tiles, lit from the left. Lit tiles are the
/// line colour with an ink edge; unlit are `surface-sunken` with a grout
/// edge. Above `cautionAt` lit tiles are striped in the warning accent;
/// above `loudAt` they are solid recording-accent and taller. Pattern and
/// height carry the zone; the colour is the accent on top.
struct FerriteMeter: View {
    /// 0...1
    let level: Double
    var segments: Int = 24
    var cautionAt: Double = 0.7
    var loudAt: Double = 0.9

    @Environment(\.ferriteLine) private var line

    var body: some View {
        HStack(alignment: .bottom, spacing: FerriteSpace.xxs) {
            ForEach(0..<segments, id: \.self) { i in
                tile(position: Double(i + 1) / Double(segments))
            }
        }
        .frame(height: 18, alignment: .bottom)
        .animation(FerriteMotion.data, value: level)
        .accessibilityElement()
        .accessibilityLabel("Level")
        .accessibilityValue("\(Int((min(max(level, 0), 1)) * 100)) percent")
    }

    @ViewBuilder
    private func tile(position: Double) -> some View {
        let lit = position <= level
        if !lit {
            Rectangle()
                .fill(FerriteColor.surfaceSunken)
                .overlay(Rectangle().strokeBorder(FerriteColor.grout, lineWidth: FerriteStroke.hairline))
                .frame(height: 10)
        } else if position > loudAt {
            Rectangle()
                .fill(FerriteStatus.recording)
                .overlay(Rectangle().strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
                .frame(height: 18)
        } else if position > cautionAt {
            FerriteStripes(ink: FerriteStatus.warning, ground: FerriteColor.label)
                .overlay(Rectangle().strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
                .frame(height: 10)
        } else {
            Rectangle()
                .fill(line.color)
                .overlay(Rectangle().strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
                .frame(height: 10)
        }
    }
}

// MARK: - Status line

/// One uppercase line at the foot of a card or canvas: text left, value
/// right, above a 1pt `separator` rule. Does not blink or animate.
struct FerriteStatusLine: View {
    let leading: String
    let trailing: String

    var body: some View {
        HStack(spacing: FerriteSpace.s) {
            Text(leading.uppercased())
            Spacer(minLength: FerriteSpace.s)
            Text(trailing.uppercased())
        }
        .font(FerriteFont.tick)
        .tracking(FerriteTracking.tick)
        .foregroundStyle(FerriteColor.labelTertiary)
        .lineLimit(1)
        .padding(.top, FerriteSpace.s)
        .overlay(alignment: .top) {
            Rectangle().fill(FerriteColor.separator).frame(height: FerriteStroke.hairline)
        }
    }
}

// MARK: - Line badge

/// The U-Bahn line chip: a filled line colour with its number and a thin
/// ink edge. The number is always shown, so colour is never the only signal.
struct FerriteLineBadge: View {
    let line: FerriteLine
    var isLarge: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FerriteRadius.tile, style: .continuous)
        Text(line.label)
            .font(.system(size: isLarge ? 18 : 14, weight: .bold))
            .tracking(0.2)
            .foregroundStyle(line.onColor)
            .padding(.horizontal, 6)
            .frame(minWidth: isLarge ? 44 : 32, minHeight: isLarge ? 32 : 24)
            .background(line.color, in: shape)
            .overlay(shape.strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
            .accessibilityLabel(line.number.map { "Linie U\($0)" } ?? "Ink")
    }
}

// MARK: - Line picker

/// Ten swatches (Ink, U1 … U9) bound to the persisted line colour. Drop
/// into a Settings `Section` as-is. The selected swatch gets a 2pt ink
/// outline and a bold label.
struct FerriteLinePicker: View {
    @AppStorage(FerriteLine.storageKey) private var lineRaw = FerriteLine.default.rawValue

    private let columns = Array(repeating: GridItem(.flexible(), spacing: FerriteSpace.m), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: FerriteSpace.m) {
            ForEach(FerriteLine.allCases) { choice in
                let selected = lineRaw == choice.rawValue
                Button {
                    withAnimation(FerriteMotion.standard) { lineRaw = choice.rawValue }
                } label: {
                    VStack(spacing: FerriteSpace.xs) {
                        Rectangle()
                            .fill(choice.color)
                            .frame(width: 36, height: 36)
                            .overlay(Rectangle().strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
                            .padding(FerriteSpace.xs)
                            .overlay(Rectangle().strokeBorder(selected ? FerriteColor.label : .clear,
                                                              lineWidth: FerriteStroke.line))
                        Text(choice.label)
                            .font(FerriteFont.caption.weight(selected ? .bold : .regular))
                            .foregroundStyle(selected ? FerriteColor.label : FerriteColor.labelSecondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.number.map { "Linie U\($0)" } ?? "Ink")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Tile band

/// A row of tiles: ten greys from white to black (`.grey`), or the nine
/// line colours in order (`.lines`). Decoration only — one per screen.
struct FerriteTileBand: View {
    enum Series { case grey, lines }
    enum Height {
        case thin, tile, tall
        var value: CGFloat {
            switch self {
            case .thin: return 8
            case .tile: return FerriteSpace.tile
            case .tall: return FerriteSpace.tile * 2
            }
        }
    }

    var series: Series = .grey
    var height: Height = .tile

    var body: some View {
        let colors = series == .grey ? FerriteBand.steps : FerriteLine.lines.map(\.color)
        HStack(spacing: 0) {
            ForEach(colors.indices, id: \.self) { i in
                Rectangle().fill(colors[i])
            }
        }
        .frame(height: height.value)
        .overlay(Rectangle().strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
        .accessibilityHidden(true)
    }
}

// MARK: - Glass bar

/// A floating glass capsule holding a tab bar or toolbar. Two to five
/// items; the selected one sits in an inner lens (`glass-fill-strong`)
/// rather than changing colour. One per screen, never inside a card.
struct FerriteGlassBar<Item: Hashable>: View {
    struct Entry: Identifiable {
        let id: Item
        let title: String
        let symbol: String
    }

    let items: [Entry]
    @Binding var selection: Item

    var body: some View {
        HStack(spacing: FerriteSpace.xxs) {
            ForEach(items) { item in
                let selected = item.id == selection
                Button {
                    withAnimation(FerriteMotion.standard) { selection = item.id }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: selected ? "\(item.symbol).fill" : item.symbol)
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 20, weight: .semibold))
                        Text(item.title)
                            .font(FerriteFont.caption.weight(.bold))
                    }
                    .foregroundStyle(FerriteColor.label)
                    .frame(minWidth: 72, minHeight: 52)
                    .padding(.horizontal, FerriteSpace.m)
                    .background {
                        if selected {
                            Capsule().fill(FerriteGlass.fillStrong)
                                .overlay(Capsule().strokeBorder(FerriteGlass.stroke, lineWidth: FerriteStroke.hairline))
                                .overlay { FerriteSpecularRim(shape: Capsule()) }
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(FerriteSpace.xs)
        .ferriteGlass()
    }
}

// MARK: - Glass button

/// Navigation-layer button: `.round` for a single symbol, `.capsule` for
/// symbol + word, `.prominent` for the one primary action (line-tinted
/// glass on iOS 26, a solid line fill with an ink edge earlier; `on-line`
/// text). 44pt minimum. On iOS 26 the glass is interactive and supplies its
/// own press response; earlier versions scale to 96% when pressed. Inside a
/// card or sheet body use `.ferritePrimary` / `.ferriteSecondary`.
///
/// Pass `glassID` + `namespace` to morph the button with other glass in the
/// same `FerriteGlassGroup`.
struct FerriteGlassButtonStyle: ButtonStyle {
    enum Kind { case round, capsule, prominent }
    var kind: Kind = .capsule
    var glassID: String? = nil
    var namespace: Namespace.ID? = nil

    @Environment(\.ferriteLine) private var line
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(FerriteFont.headline)
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, kind == .round ? 0 : FerriteSpace.m)

        Group {
            switch kind {
            case .prominent:
                label
                    .foregroundStyle(line.onColor)
                    .ferriteGlass(in: Capsule(), tint: line, interactive: true, id: glassID, namespace: namespace)
            case .round:
                label
                    .foregroundStyle(FerriteColor.label)
                    .frame(width: 44, height: 44)
                    .ferriteGlass(in: Circle(), interactive: true, id: glassID, namespace: namespace)
            case .capsule:
                label
                    .foregroundStyle(FerriteColor.label)
                    .ferriteGlass(interactive: true, id: glassID, namespace: namespace)
            }
        }
        .contentShape(Capsule())
        .scaleEffect(configuration.isPressed && !usesSystemGlass ? 0.96 : 1)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(FerriteMotion.standard, value: configuration.isPressed)
    }

    /// System interactive glass already reacts to touch; scaling on top of
    /// it would double the press response.
    private var usesSystemGlass: Bool {
        if #available(iOS 26.0, *) {
            return !reduceTransparency
        }
        return false
    }
}

extension ButtonStyle where Self == FerriteGlassButtonStyle {
    static var ferriteGlass: FerriteGlassButtonStyle { .init(kind: .capsule) }
    static var ferriteGlassRound: FerriteGlassButtonStyle { .init(kind: .round) }
    static var ferriteGlassProminent: FerriteGlassButtonStyle { .init(kind: .prominent) }

    /// Glass button with a morph identity inside a `FerriteGlassGroup`.
    static func ferriteGlass(_ kind: FerriteGlassButtonStyle.Kind, id: String, in namespace: Namespace.ID) -> FerriteGlassButtonStyle {
        .init(kind: kind, glassID: id, namespace: namespace)
    }
}
