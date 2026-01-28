import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var audioEngine: WatchAudioEngine

    var body: some View {
        VStack(spacing: 8) {
            WatchSpectrogramView()
                .frame(maxHeight: .infinity)
        }
    }
}
