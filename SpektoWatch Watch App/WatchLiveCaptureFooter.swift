import SwiftUI

/// Shared status row: link dot, measurement-source pill, record button.
struct WatchLiveCaptureFooter: View {
    @Environment(WatchAudioEngine.self) private var audioEngine
    @Environment(WatchConnectivityManager.self) private var connectivityManager

    var body: some View {
        HStack {
            Circle()
                .fill(audioEngine.isRecording ? Color.red : (connectivityManager.isReachable ? Color.green : Color.gray))
                .frame(width: 4, height: 4)
                .animation(.easeInOut(duration: 0.3), value: audioEngine.isRecording)
            WatchMeasurementSourceIndicator()
            Spacer()
            WatchRecordToggle()
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
    }
}
