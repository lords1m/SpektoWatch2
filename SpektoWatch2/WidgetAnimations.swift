import SwiftUI

struct WidgetAnimations {
    /// Transition für Widget Cards (Add/Remove)
    static var cardTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.94).combined(with: .opacity),
            removal: .scale(scale: 0.94).combined(with: .opacity)
        )
    }
    
    /// Animation für Resize
    static var resizeAnimation: Animation {
        .spring(response: 0.32, dampingFraction: 0.84)
    }
    
    /// Animation für Reorder
    static var reorderAnimation: Animation {
        .spring(response: 0.28, dampingFraction: 0.86)
    }
}
