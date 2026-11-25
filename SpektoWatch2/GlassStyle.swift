import SwiftUI

/// App shell background — Ferrite `bg-base` (pure white / pure black).
struct GlassBackground: View {
    var body: some View {
        FerriteColor.background
            .ignoresSafeArea()
    }
}

/// Content card — despite the legacy name this is NOT glass: Ferrite cards
/// are `surface`, square, with a 1pt `label` outline and no shadow. The
/// `cornerRadius` argument is kept for source compatibility and ignored.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = FerriteRadius.card

    func body(content: Content) -> some View {
        content
            .background(FerriteColor.surface)
            .overlay(Rectangle().strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
    }
}

/// Quieter nested card: `surface-sunken` fill with a hairline, for cards
/// inside cards or dense lists.
struct GlassCardLite: ViewModifier {
    var cornerRadius: CGFloat = FerriteRadius.card

    func body(content: Content) -> some View {
        content
            .background(FerriteColor.surfaceSunken)
            .overlay(Rectangle().strokeBorder(FerriteColor.hairline, lineWidth: FerriteStroke.hairline))
    }
}

/// Floating bar — real liquid glass (navigation layer only).
struct GlassBar: ViewModifier {
    var cornerRadius: CGFloat = FerriteRadius.glass

    func body(content: Content) -> some View {
        content.ferriteGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = FerriteRadius.card) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }

    func glassCardLite(cornerRadius: CGFloat = FerriteRadius.card) -> some View {
        modifier(GlassCardLite(cornerRadius: cornerRadius))
    }

    func glassBar(cornerRadius: CGFloat = FerriteRadius.glass) -> some View {
        modifier(GlassBar(cornerRadius: cornerRadius))
    }

    func backgroundExtensionEffect(cornerRadius: CGFloat = FerriteRadius.glass) -> some View {
        glassBar(cornerRadius: cornerRadius)
    }
}
