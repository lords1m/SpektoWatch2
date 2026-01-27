import SwiftUI

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    
    var body: some View {
        ModularDashboardView(audioEngine: audioEngine)
    }
}
