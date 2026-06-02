import SwiftUI

/// Themed app shell background (OKLCH-inspired dark / light gradients).
struct GlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.11, blue: 0.14),
                        Color(red: 0.06, green: 0.07, blue: 0.10),
                        Color(red: 0.04, green: 0.05, blue: 0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [
                        Color(red: 0.18, green: 0.22, blue: 0.32).opacity(0.35),
                        Color.clear
                    ],
                    center: .top,
                    startRadius: 0,
                    endRadius: 480
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.97, green: 0.97, blue: 0.98),
                        Color(red: 0.93, green: 0.94, blue: 0.96),
                        Color(red: 0.90, green: 0.91, blue: 0.94)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [
                        Color(red: 0.88, green: 0.92, blue: 0.98).opacity(0.55),
                        Color.clear
                    ],
                    center: .top,
                    startRadius: 0,
                    endRadius: 420
                )
            }
        }
        .ignoresSafeArea()
    }
}

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 12, y: 6)
    }
}

struct GlassCardLite: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 8, y: 4)
    }
}

struct GlassBar: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 14, y: 7)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }

    func glassCardLite(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassCardLite(cornerRadius: cornerRadius))
    }

    func glassBar(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassBar(cornerRadius: cornerRadius))
    }

    func backgroundExtensionEffect(cornerRadius: CGFloat = 24) -> some View {
        glassBar(cornerRadius: cornerRadius)
    }
}
