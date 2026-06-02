import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var audioEngine: WatchAudioEngine
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager

    var body: some View {
        TabView {
            WatchPegelmesserFace()
            WatchModularFace()
            WatchTonegeneratorFace()
            WatchMoreFacesView()
        }
        .tabViewStyle(.page)
    }
}
