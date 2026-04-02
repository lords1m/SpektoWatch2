import SwiftUI

private let isDebugBuild: Bool = {
#if DEBUG
    return true
#else
    return false
#endif
}()

struct ContentView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var connectivityManager: WatchConnectivityManager
    
    var body: some View {
        ZStack {
            GlassBackground()
                .ignoresSafeArea()
            ModularDashboardView(audioEngine: audioEngine, connectivityManager: connectivityManager)

            if isDebugBuild {
                VStack {
                    HStack {
                        Text("DEBUG UI VISIBLE")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.yellow.opacity(0.9))
                            .foregroundColor(.black)
                            .cornerRadius(8)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
    }
}
