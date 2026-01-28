import SwiftUI

struct ContentView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var connectivityManager: WatchConnectivityManager
    
    var body: some View {
        ModularDashboardView(audioEngine: audioEngine, connectivityManager: connectivityManager)
    }
}
