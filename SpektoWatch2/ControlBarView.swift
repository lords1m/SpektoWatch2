import SwiftUI

struct ControlBarView: View {
    @ObservedObject var audioEngine: AudioEngine
    @State private var isRecording = false
    
    var body: some View {
        HStack {
            // Status Info
            VStack(alignment: .leading) {
                Text(isRecording ? "Aufnahme läuft" : "Bereit")
                    .font(.caption)
                    .foregroundColor(isRecording ? .red : .gray)
                if isRecording {
                    Text(timeString(from: audioEngine.recordingDuration))
                        .font(.caption2)
                        .monospacedDigit()
                }
            }
            
            Spacer()
            
            // Record Button
            Button(action: toggleRecording) {
                Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.system(size: 44))
                    .foregroundColor(isRecording ? .red : .red)
            }
            
            Spacer()
            
            // Settings / More
            Button(action: {
                // Show settings
            }) {
                Image(systemName: "gear")
                    .font(.title2)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .onReceive(NotificationCenter.default.publisher(for: .startRecordingCommand)) { _ in
            if !isRecording { toggleRecording() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopRecordingCommand)) { _ in
            if isRecording { toggleRecording() }
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
    
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}