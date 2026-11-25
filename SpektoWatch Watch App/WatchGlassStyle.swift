import SwiftUI

enum WatchStylePalette {
    static let accentBlue = Color(red: 0.23, green: 0.64, blue: 1.0)
    static let cardBorder = Color.white.opacity(0.22)
    static let cardFill = Color(white: 0.12)
    static let controlFill = Color(white: 0.18)
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

/// Content card — solid, not glass: content never sits on material.
/// A flat dark fill with a hairline rim (shadows are invisible on black).
struct WatchCard: ViewModifier {
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(WatchStylePalette.cardFill, in: shape)
            .overlay(shape.stroke(WatchStylePalette.cardBorder, lineWidth: 1))
    }
}

/// Liquid glass for watch controls only (record, play/pause) — never over
/// live canvases. watchOS 26 uses the system glass; earlier versions,
/// Reduce Transparency and Always-On (reduced luminance) fall back to a
/// solid fill: the tint at 80 % (dimmed in Always-On) or a dark grey rim.
struct WatchGlassSurface<S: Shape>: ViewModifier {
    var shape: S
    var tint: Color? = nil
    var interactive: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.watchGlassOverLiveCanvas) private var overLiveCanvas

    func body(content: Content) -> some View {
        if #available(watchOS 26.0, *), !reduceTransparency, !isLuminanceReduced, !overLiveCanvas {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content
                .background(fallbackFill, in: shape)
                .overlay(shape.stroke(tint == nil ? WatchStylePalette.cardBorder : .clear, lineWidth: 1))
        }
    }

    private var fallbackFill: Color {
        if let tint {
            return tint.opacity(isLuminanceReduced ? 0.35 : 0.80)
        }
        return WatchStylePalette.controlFill
    }
}

extension EnvironmentValues {
    /// Set on controls floating over a live canvas (spectrogram, level graph):
    /// glass there would re-sample the canvas every frame, costing GPU and
    /// battery, so `watchGlass` uses its solid fallback instead.
    @Entry var watchGlassOverLiveCanvas: Bool = false
}

extension View {
    func watchCard(cornerRadius: CGFloat = 10) -> some View {
        modifier(WatchCard(cornerRadius: cornerRadius))
    }

    /// Glass for a floating watch control. `tint` only for the one primary
    /// action on screen; `interactive` only for tappable glass.
    func watchGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(WatchGlassSurface(shape: shape, tint: tint, interactive: interactive))
    }
}
