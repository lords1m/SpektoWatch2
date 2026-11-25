import SwiftUI

/// Status dot + record/stop control for watch faces that show live levels.
struct WatchRecordButton: View {
    @Environment(WatchAudioEngine.self) private var audioEngine
    @Environment(WatchConnectivityManager.self) private var connectivityManager

    var body: some View {
        HStack {
            Circle()
                .fill(audioEngine.isRecording ? Color.red : (connectivityManager.isReachable ? Color.green : Color.gray))
                .frame(width: 4, height: 4)
                .animation(.easeInOut(duration: 0.3), value: audioEngine.isRecording)
            Spacer()
            WatchRecordToggle()
        }
        .padding(.horizontal, 2)
    }
}
