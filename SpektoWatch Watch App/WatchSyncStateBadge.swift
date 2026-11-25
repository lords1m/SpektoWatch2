import SwiftUI

/// Small colored glyph that communicates how far a recording has reached the
/// phone. Drives off `WatchRecordingSyncState` ([[task-5-sync-back]]).
struct WatchSyncStateBadge: View {
    let state: WatchRecordingSyncState

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }

    private var symbol: String {
        switch state {
        case .local: return "arrow.up.circle"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .local: return .gray
        case .syncing: return WatchStylePalette.accentBlue
        case .synced: return .green
        }
    }

    private var label: String {
        switch state {
        case .local: return "Nicht synchronisiert"
        case .syncing: return "Synchronisiert gerade"
        case .synced: return "Synchronisiert"
        }
    }
}
