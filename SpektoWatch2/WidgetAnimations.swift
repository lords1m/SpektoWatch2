import SwiftUI

struct WidgetAnimations {
    // Kombinierte Transition für das Hinzufügen/Entfernen von Widgets
    static let cardTransition = AnyTransition.asymmetric(
        // Einfügen: Leichtes Einzoomen + Fade In mit Federung
        insertion: .scale(scale: 0.9).combined(with: .opacity).animation(.spring(response: 0.4, dampingFraction: 0.7)),
        // Entfernen: Schrumpfen + Fade Out
        removal: .scale(scale: 0.8).combined(with: .opacity).animation(.easeOut(duration: 0.2))
    )
}