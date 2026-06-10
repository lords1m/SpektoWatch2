import SwiftUI

/// Shared status row: link dot, measurement-source pill, record button.
struct WatchLiveCaptureFooter: View {
    @EnvironmentObject private var audioEngine: WatchAudioEngine
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager

    var body: some View {
        HStack {
            Circle()
                .fill(audioEngine.isRecording ? Color.red : (connectivityManager.isReachable ? Color.green : Color.gray))
                .frame(width: 4, height: 4)
                .animation(.easeInOut(duration: 0.3), value: audioEngine.isRecording)
            WatchMeasurementSourceIndicator()
            Spacer()
            WatchRecordButton()
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
    }
}
