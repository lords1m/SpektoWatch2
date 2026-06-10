import SwiftUI

/// Shared record/stop control for watch faces that show live levels.
struct WatchRecordButton: View {
    @EnvironmentObject private var audioEngine: WatchAudioEngine
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager

    var body: some View {
        HStack {
            Circle()
                .fill(audioEngine.isRecording ? Color.red : (connectivityManager.isReachable ? Color.green : Color.gray))
                .frame(width: 4, height: 4)
                .animation(.easeInOut(duration: 0.3), value: audioEngine.isRecording)
            Spacer()
            Button(action: toggleRecording) {
                Image(systemName: audioEngine.isRecording ? "stop.fill" : "record.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(
                            audioEngine.isRecording
                                ? Color.red.opacity(0.80)
                                : WatchStylePalette.accentBlue.opacity(0.80)
                        )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(audioEngine.isRecording ? "Aufnahme stoppen" : "Aufnahme starten")
        }
        .padding(.horizontal, 2)
    }

    private func toggleRecording() {
        if audioEngine.isRecording {
            audioEngine.stopRecording()
            if audioEngine.coordinatesRecordingWithPhone {
                connectivityManager.requestWearableRecordingStop()
            }
        } else {
            if audioEngine.coordinatesRecordingWithPhone {
                connectivityManager.requestWearableRecordingStart()
            }
            audioEngine.startRecording()
        }
        WKInterfaceDevice.current().play(.success)
    }
}
