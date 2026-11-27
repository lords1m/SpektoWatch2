import SwiftUI
import WatchKit

/// The record/stop control on every live watch screen. Tinted glass (the
/// one primary action on screen): accent blue while idle, red while recording.
struct WatchRecordToggle: View {
    @Environment(WatchAudioEngine.self) private var audioEngine
    @Environment(WatchConnectivityManager.self) private var connectivityManager

    var body: some View {
        Button(action: toggleRecording) {
            Image(systemName: audioEngine.isRecording ? "stop.fill" : "record.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .watchGlass(
                    in: Circle(),
                    tint: audioEngine.isRecording ? .red : WatchStylePalette.accentBlue,
                    interactive: true
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(audioEngine.isRecording ? "Aufnahme stoppen" : "Aufnahme starten")
        .accessibilityHint("Aufnahme steuern")
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
