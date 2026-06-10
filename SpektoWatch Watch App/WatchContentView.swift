import SwiftUI

private enum WatchMainTab: Int, Hashable {
    case meter
    case spectrogram
    case levelGraph
    case more
}

struct WatchContentView: View {
    @EnvironmentObject private var audioEngine: WatchAudioEngine
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager
    @State private var selectedTab: WatchMainTab = .meter

    var body: some View {
        TabView(selection: $selectedTab) {
            WatchCustomMeterView()
                .tag(WatchMainTab.meter)
                .environment(\.watchTabLiveUpdatesActive, selectedTab == .meter)
            WatchSpectrogramTabView()
                .tag(WatchMainTab.spectrogram)
                .environment(\.watchTabLiveUpdatesActive, selectedTab == .spectrogram)
            WatchLevelGraphTabView()
                .tag(WatchMainTab.levelGraph)
                .environment(\.watchTabLiveUpdatesActive, selectedTab == .levelGraph)
            WatchMoreFacesView()
                .tag(WatchMainTab.more)
                .environment(\.watchTabLiveUpdatesActive, selectedTab == .more)
        }
        .tabViewStyle(.page)
    }
}
