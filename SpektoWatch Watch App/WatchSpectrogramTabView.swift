import SwiftUI

/// Full-screen spectrogram tab (dedicated view, not buried in Mehr).
struct WatchSpectrogramTabView: View {
    var body: some View {
        ZStack {
            WatchSpectrogramView()
        }
        .accessibilityIdentifier("watchSpectrogramTab")
    }
}
