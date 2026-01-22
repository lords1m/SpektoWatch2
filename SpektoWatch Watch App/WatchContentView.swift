import SwiftUI

struct WatchContentView: View {
    @StateObject private var audioEngine = WatchAudioEngine()
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @State private var isRecording = false

    var body: some View {
        VStack(spacing: 8) {
            WatchSpectrogramView()
                .frame(maxHeight: .infinity)

            if connectivityManager.selectedMicrophoneSource == .appleWatch {
                Button(action: toggleRecording) {
                    HStack {
                        Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                        Text(isRecording ? "Stop" : "Start")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(isRecording ? Color.red : Color.green)
                    .cornerRadius(20)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
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
