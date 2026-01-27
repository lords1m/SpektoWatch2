import SwiftUI

struct WatchContentView: View {
    @StateObject private var audioEngine = WatchAudioEngine()
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @State private var isRecording = false

    var body: some View {
        VStack(spacing: 8) {
            WatchSpectrogramView()
                .environmentObject(audioEngine)
                .frame(maxHeight: .infinity)
        }
    }

    private func toggleRecording() {
        isRecording.toggle()

        if isRecording {
            audioEngine.startRecording()
        } else {
            audioEngine.stopRecording()
        }
    }
}
