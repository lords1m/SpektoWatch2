import SwiftUI

enum WatchStylePalette {
    static let accentBlue = Color(red: 0.23, green: 0.64, blue: 1.0)
    static let cardBorder = Color.white.opacity(0.22)
}

struct WatchAppBackground: View {
    var body: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.14),
                    Color(red: 0.03, green: 0.04, blue: 0.06),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.clear
                ],
                center: .top,
                startRadius: 0,
                endRadius: 180
            )
        }
    }
}

/// Content-layer card: solid fill and a hairline, no material, no shadow.
/// Cards sit over live level canvases and in Always-On, so they never blur
/// what is behind them (battery, legibility). Glass is reserved for the
/// floating control layer (`watchGlass`).
struct WatchGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .background(
                Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(WatchStylePalette.cardBorder, lineWidth: 1)
            )
    }
}

/// Liquid glass for floating watch controls (the record button).
///
/// - watchOS 26+: the system `.glassEffect`, optionally tinted, interactive
///   when tappable.
/// - watchOS 11-25: a solid tint fill (or `thinMaterial` untinted) with a
///   hairline rim — the previous look.
/// - Always-On (`isLuminanceReduced`) or Reduce Transparency: a solid dim
///   fill, no glass sampling.
struct WatchGlassSurface<S: InsettableShape>: ViewModifier {
    var shape: S
    var tint: Color? = nil
    var interactive: Bool = false

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if isLuminanceReduced || reduceTransparency {
            content
                .background((tint ?? Color.white).opacity(isLuminanceReduced ? 0.35 : 0.80), in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.30), lineWidth: 1))
        } else if #available(watchOS 26.0, *) {
            content
                .glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else if let tint {
            content
                .background(tint.opacity(0.80), in: shape)
        } else {
            content
                .background(.thinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.24), lineWidth: 1))
        }
    }
}

extension View {
    func watchGlassCard(cornerRadius: CGFloat = 10) -> some View {
        modifier(WatchGlassCard(cornerRadius: cornerRadius))
    }

    /// Glass for the floating control layer only; never over a live canvas.
    func watchGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(WatchGlassSurface(shape: shape, tint: tint, interactive: interactive))
    }

    /// The record / stop control: the one tinted glass control per screen.
    func watchRecordGlass(isRecording: Bool) -> some View {
        watchGlass(
            in: Circle(),
            tint: isRecording ? .red : WatchStylePalette.accentBlue,
            interactive: true
        )
    }
}
