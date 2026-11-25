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

/// The floating-layer material. iOS 26 uses the system `.glassEffect`;
/// earlier versions draw `glass-fill` over a blur with a `glass-stroke`
/// rim, a `glass-edge` highlight and the single `shadow-glass`. Under
/// Reduce Transparency it becomes an opaque `glass-fill-strong` fill with
/// a `label` outline.
struct FerriteGlassSurface<S: InsettableShape>: ViewModifier {
    var shape: S
    var interactive: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(FerriteColor.background, in: shape)
                .overlay(shape.strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(FerriteGlass.fill, in: shape)
                .overlay(shape.strokeBorder(FerriteGlass.stroke, lineWidth: FerriteStroke.hairline))
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
}

extension View {
    /// Liquid glass for the floating navigation layer only. Never on cards,
    /// canvases, rows or body text; never glass on glass.
    func ferriteGlass<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(FerriteGlassSurface(shape: shape, interactive: interactive))
    }

    /// Capsule-shaped glass (bars and buttons).
    func ferriteGlass(interactive: Bool = false) -> some View {
        modifier(FerriteGlassSurface(shape: Capsule(), interactive: interactive))
    }

    func ferriteBlink(_ isActive: Bool = true) -> some View {
        modifier(FerriteBlink(isActive: isActive))
    }
}
