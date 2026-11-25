import SwiftUI

// MARK: - Tiles

/// Grout lines on the tile pitch: the platform wall, and the chart grid on
/// canvases. Static (redrawn only on size change), so it costs nothing per
/// frame under a live spectrogram. Decorative; never carries meaning.
struct FerriteTileGrid: View {
    var pitch: CGFloat = FerriteSpace.tile
    var color: Color = FerriteColor.grout

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x < size.width {
                path.addRect(CGRect(x: x, y: 0, width: FerriteStroke.hairline, height: size.height))
                x += pitch
            }
            var y: CGFloat = 0
            while y < size.height {
                path.addRect(CGRect(x: 0, y: y, width: size.width, height: FerriteStroke.hairline))
                y += pitch
            }
            context.fill(path, with: .color(color))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 135° hatch used for the caution zone of `FerriteMeter`: zones differ by
/// pattern, not hue.
struct FerriteStripes: View {
    var ink: Color = FerriteColor.label
    var ground: Color = FerriteColor.background
    var period: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ground))
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += period
            }
            context.stroke(path, with: .color(ink), lineWidth: period / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Equilateral triangle marker (CLIP badge).
struct FerriteTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Blink

/// On/off blink for the REC marker — the only repeating motion in the
/// system. Holds solid under Reduce Motion.
struct FerriteBlink: ViewModifier {
    var isActive: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if isActive && !reduceMotion {
            TimelineView(.periodic(from: .now, by: FerriteMotion.blinkHalfPeriod)) { timeline in
                let tick = Int(timeline.date.timeIntervalSinceReferenceDate / FerriteMotion.blinkHalfPeriod)
                content.opacity(tick.isMultiple(of: 2) ? 1 : 0)
            }
        } else {
            content
        }
    }
}

// MARK: - Liquid glass surface

/// The floating-layer material — the only place the app draws glass.
///
/// - iOS 26+: the system `.glassEffect`, optionally tinted with a line
///   colour (accent glass), interactive, and tagged with a morph identity.
/// - Earlier: `glass-fill` over a blur with a `glass-stroke` rim, a
///   `glass-edge` highlight and the single `shadow-glass`; tinted glass is
///   a solid line fill with an ink edge. Increase Contrast swaps the rim
///   for a `label` outline.
/// - Reduce Transparency (any version): opaque `background` (or the line
///   colour when tinted) with a `label` outline.
struct FerriteGlassSurface<S: InsettableShape>: ViewModifier {
    var shape: S
    var tint: FerriteLine? = nil
    var interactive: Bool = false
    var glassID: String? = nil
    var namespace: Namespace.ID? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(tint?.color ?? FerriteColor.background, in: shape)
                .overlay(shape.strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(tint?.color).interactive(interactive), in: shape)
                .modifier(FerriteGlassIdentity(id: glassID, namespace: namespace))
        } else if let tint {
            content
                .background(tint.color, in: shape)
                .overlay(shape.strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
                .shadow(color: FerriteGlass.shadow, radius: FerriteGlass.shadowRadius, y: FerriteGlass.shadowY)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(FerriteGlass.fill, in: shape)
                .overlay(shape.strokeBorder(rimColor, lineWidth: FerriteStroke.hairline))
                .overlay(
                    shape.inset(by: 0.5)
                        .stroke(
                            LinearGradient(colors: [FerriteGlass.edge, .clear], startPoint: .top, endPoint: .center),
                            lineWidth: FerriteStroke.hairline
                        )
                        .allowsHitTesting(false)
                )
                .shadow(color: FerriteGlass.shadow, radius: FerriteGlass.shadowRadius, y: FerriteGlass.shadowY)
        }
    }

    private var rimColor: Color {
        contrast == .increased ? FerriteColor.label : FerriteGlass.stroke
    }
}

/// Glass that sits against a screen or sheet edge (dock, bottom bars). On
/// iOS 26 its corners are concentric with the display — correct on every
/// device, including iPhone Duo's outer display and iPad windows — never
/// tighter than `minimumRadius`. Earlier versions use `minimumRadius` as a
/// fixed radius.
struct FerriteEdgeGlassSurface: ViewModifier {
    var minimumRadius: CGFloat
    var interactive: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(minimumRadius)), isUniform: true)
            if reduceTransparency {
                content
                    .background(FerriteColor.background, in: shape)
                    .overlay {
                        // ConcentricRectangle isn't insettable: a 2× stroke
                        // clipped to the shape leaves a 1pt inner outline.
                        shape.stroke(FerriteColor.label, lineWidth: FerriteStroke.hairline * 2)
                            .clipShape(shape)
                            .allowsHitTesting(false)
                    }
            } else {
                content.glassEffect(.regular.interactive(interactive), in: shape)
            }
        } else {
            content.modifier(FerriteGlassSurface(
                shape: RoundedRectangle(cornerRadius: minimumRadius, style: .continuous),
                interactive: interactive
            ))
        }
    }
}

/// Morph identity for glass inside a `FerriteGlassGroup` (iOS 26+). No-op
/// when either the id or the namespace is missing.
@available(iOS 26.0, *)
private struct FerriteGlassIdentity: ViewModifier {
    var id: String?
    var namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let id, let namespace {
            content.glassEffectID(id, in: namespace)
        } else {
            content
        }
    }
}

/// Merges separately laid-out glass shapes into one continuous piece of
/// glass (iOS 26+); no visual change earlier.
private struct FerriteGlassUnion: ViewModifier {
    var id: String
    var namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffectUnion(id: id, namespace: namespace)
        } else {
            content
        }
    }
}

extension View {
    /// Liquid glass for the floating navigation layer only. Never on cards,
    /// canvases, rows or body text; never glass on glass.
    ///
    /// - Parameters:
    ///   - tint: a line colour for accent glass — at most one per bar.
    ///   - interactive: only for tappable glass.
    ///   - id / namespace: morph identity inside a `FerriteGlassGroup`.
    ///     Never drive the shape, size or tint from live audio values.
    func ferriteGlass<S: InsettableShape>(
        in shape: S,
        tint: FerriteLine? = nil,
        interactive: Bool = false,
        id: String? = nil,
        namespace: Namespace.ID? = nil
    ) -> some View {
        modifier(FerriteGlassSurface(shape: shape, tint: tint, interactive: interactive, glassID: id, namespace: namespace))
    }

    /// Capsule-shaped glass (bars and buttons).
    func ferriteGlass(
        tint: FerriteLine? = nil,
        interactive: Bool = false,
        id: String? = nil,
        namespace: Namespace.ID? = nil
    ) -> some View {
        ferriteGlass(in: Capsule(), tint: tint, interactive: interactive, id: id, namespace: namespace)
    }

    /// Glass whose corners follow the screen edge it sits against.
    func ferriteEdgeGlass(minimumRadius: CGFloat = FerriteRadius.dock, interactive: Bool = false) -> some View {
        modifier(FerriteEdgeGlassSurface(minimumRadius: minimumRadius, interactive: interactive))
    }

    /// Joins this glass with every sibling sharing `id` into one shape.
    func ferriteGlassUnion(id: String, namespace: Namespace.ID) -> some View {
        modifier(FerriteGlassUnion(id: id, namespace: namespace))
    }

    func ferriteBlink(_ isActive: Bool = true) -> some View {
        modifier(FerriteBlink(isActive: isActive))
    }
}
