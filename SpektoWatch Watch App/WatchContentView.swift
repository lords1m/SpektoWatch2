import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var audioEngine: WatchAudioEngine
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager

    var body: some View {
        NavigationView {
            List {
                // Dashboard als Hauptansicht
                NavigationLink(destination: WatchDashboardView()) {
                    Label("Dashboard", systemImage: "waveform")
                }
                
                // Lautheit-Rechner
                NavigationLink(destination: LoudnessCalculatorView()) {
                    Label("Lautheit-Rechner", systemImage: "speaker.wave.3")
                }
            }
            .navigationTitle("SpektoWatch")
        }
    }
}
