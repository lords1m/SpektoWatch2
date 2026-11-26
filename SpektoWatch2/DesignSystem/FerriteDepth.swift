import SwiftUI

// MARK: - Spatial depth
//
// The pieces that make glass and Home Screen icons look like lit objects
// at different heights instead of flat stickers. All of them are drawn
// from the static shape, so they cost nothing per frame even when the
// surface floats over a live spectrogram. Tokens live in `FerriteDepth`
// and `FerriteElevation`.

/// Lit rim + far-edge reflection + lower bevel shade, drawn inside `shape`.
/// Works with any `Shape` (including `ConcentricRectangle`, which isn't
/// insettable): each stroke is twice the wanted width and clipped to the
/// shape, leaving only its inner half.
struct FerriteSpecularRim<S: Shape>: View {
    var shape: S

    var body: some View {
        ZStack {
            shape.stroke(
                LinearGradient(
                    stops: [
                        .init(color: FerriteDepth.rimLight, location: 0),
                        .init(color: .clear, location: 0.45),
                        .init(color: .clear, location: 0.75),
                        .init(color: FerriteDepth.rimReflect, location: 1),
                    ],
                    startPoint: UnitPoint(x: 0.35, y: 0),
                    endPoint: UnitPoint(x: 0.65, y: 1)
                ),
                lineWidth: FerriteDepth.rimWidth * 2
            )
            shape.stroke(
                LinearGradient(colors: [.clear, FerriteDepth.bevelShade], startPoint: .center, endPoint: .bottom),
                lineWidth: FerriteDepth.bevelWidth * 2
            )
        }
        .clipShape(shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Soft light over the upper half of a surface, under its content.
struct FerriteSheen<S: Shape>: View {
    var shape: S
    var color: Color = FerriteDepth.sheen

    var body: some View {
        shape
            .fill(LinearGradient(colors: [color, .clear], startPoint: .top, endPoint: .center))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Contact + ambient shadow cast by `shape`, with the shape's own interior
/// knocked out. Glass above it therefore samples the real content, not a
/// shadow fill, and live content inside never invalidates the blur.
struct FerriteDropShadow<S: Shape>: View {
    var shape: S
    var elevation: FerriteElevation

    var body: some View {
        ZStack {
            shape.fill(Color.black)
                .shadow(color: elevation.ambientColor, radius: elevation.ambientRadius, y: elevation.ambientY)
            shape.fill(Color.black)
                .shadow(color: elevation.contactColor, radius: elevation.contactRadius, y: elevation.contactY)
            shape.fill(Color.black)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Rim over the content plus the drop shadow, for solid surfaces whose
/// fill is opaque (a sheen there belongs between fill and content, so
/// callers add `FerriteSheen` themselves where it fits).
private struct FerriteSolidDepth<S: Shape>: ViewModifier {
    var shape: S
    var elevation: FerriteElevation

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .overlay { FerriteSpecularRim(shape: shape).opacity(reduceTransparency ? 0 : 1) }
            .background { FerriteDropShadow(shape: shape, elevation: elevation).opacity(reduceTransparency ? 0 : 1) }
    }
}

extension View {
    /// Spatial light for a solid surface (Home Screen icons and widgets).
    /// Never on canvases, cards inside screens, or rows.
    func ferriteDepth<S: Shape>(in shape: S, elevation: FerriteElevation = .raised) -> some View {
        modifier(FerriteSolidDepth(shape: shape, elevation: elevation))
    }
}
