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

extension View {
    func glassCard(cornerRadius: CGFloat = FerriteRadius.card) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}
