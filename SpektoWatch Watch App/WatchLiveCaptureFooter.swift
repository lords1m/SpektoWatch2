import SwiftUI

/// Shared status row: link dot, measurement-source pill, record button.
struct WatchLiveCaptureFooter: View {
    @EnvironmentObject private var audioEngine: WatchAudioEngine
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager

    var body: some View {
        VStack(spacing: 2) {
            if audioEngine.isRecording, let warning = audioEngine.backgroundRuntimeWarning {
                // WL-1: runtime session failed to start — be honest that
                // lowering the wrist may end the recording.
                Text(warning)
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            footerRow
        }
    }

    private var footerRow: some View {
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
