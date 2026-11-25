import SwiftUI

/// Groups neighbouring Ferrite glass so it renders as one material: shapes
/// closer than `spacing` blend into each other, and glass tagged with
/// `ferriteGlass(id:namespace:)` morphs between states when changed inside
/// an animation. One container per bar cluster (top bar, bottom stack) —
/// glass can't sample other glass, so siblings outside a container look
/// like separate stickers. On iOS 18–25 the content is laid out unchanged.
struct FerriteGlassGroup<Content: View>: View {
    var spacing: CGFloat?
    var content: Content

    init(spacing: CGFloat? = FerriteSpace.s, @ContentBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
