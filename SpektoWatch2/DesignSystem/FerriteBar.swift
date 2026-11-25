import SwiftUI

/// Pins a floating glass bar to the top or bottom edge and reserves its
/// space. iOS 26 uses `safeAreaBar`, which also gives content scrolling
/// underneath a soft scroll-edge effect so the bar stays legible over the
/// tile wall; earlier versions use `safeAreaInset`.
///
/// Only for bars that stay on screen. A bar inserted and removed
/// conditionally (e.g. the jiggle-mode edit bar) came back horizontally
/// offset after an exit/re-enter cycle under `safeAreaBar` on iOS 26.5;
/// keep `safeAreaInset` for those.
private struct FerriteBarModifier<Bar: View>: ViewModifier {
    var edge: VerticalEdge
    var spacing: CGFloat?
    var bar: Bar

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: edge, spacing: spacing) { bar }
        } else {
            content.safeAreaInset(edge: edge, spacing: spacing) { bar }
        }
    }
}

extension View {
    /// Attach a floating bar (header, edit bar, dock) to a screen edge.
    func ferriteBar<Bar: View>(
        edge: VerticalEdge,
        spacing: CGFloat? = 0,
        @ContentBuilder _ bar: () -> Bar
    ) -> some View {
        modifier(FerriteBarModifier(edge: edge, spacing: spacing, bar: bar()))
    }
}
