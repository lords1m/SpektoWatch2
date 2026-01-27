import SwiftUI

struct WidgetAnimations {
    /// Transition für Widget Cards (Add/Remove)
    static var cardTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .scale(scale: 0.8).combined(with: .opacity)
        )
    }
    
    /// Animation für Resize
    static var resizeAnimation: Animation {
        .spring(response: 0.4, dampingFraction: 0.7)
    }
    
    /// Animation für Reorder
    static var reorderAnimation: Animation {
        .spring(response: 0.3, dampingFraction: 0.8)
    }
}
