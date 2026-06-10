import SwiftUI

/// Full-screen level history graph tab.
struct WatchLevelGraphTabView: View {
    var body: some View {
        ZStack {
            WatchLevelMeterView()
        }
        .accessibilityIdentifier("watchLevelGraphTab")
    }
}
