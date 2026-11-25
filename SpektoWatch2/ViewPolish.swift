import SwiftUI

// MARK: - Shared UI polish (forms, sheets, instrument chrome)

extension View {
    /// Hides the default Form/List background and paints the themed app gradient.
    func polishedFormChrome() -> some View {
        scrollContentBackground(.hidden)
            .background(GlassBackground())
    }

    /// Standard sheet chrome for settings / pickers.
    func polishedSheetChrome() -> some View {
        presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }
}
