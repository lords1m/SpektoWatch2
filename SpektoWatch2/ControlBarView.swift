import SwiftUI

struct ControlBarView: View {
    @ObservedObject var audioEngine: AudioEngine
    @State private var isRecording = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Separator
            Divider()
                .background(Color.gray.opacity(0.3))
            
            HStack(spacing: 16) {
                // Status Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(isRecording ? "Aufnahme läuft" : "Bereit")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(isRecording ? .red : .gray)
                    if isRecording {
                        Text(timeString(from: audioEngine.recordingDuration))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 100, alignment: .leading)
                
                Spacer()
                
                // Record Button - CENTERED
                Button(action: toggleRecording) {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.red.opacity(0.2) : Color.clear)
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                // Settings Button
                Button(action: {
                    // Show settings
                    print("[ControlBarView] Settings tapped")
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .frame(width: 100, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .background(
            Color(UIColor.systemBackground)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
        )
    }
    
    private func toggleRecording() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        isRecording.toggle()
        if isRecording {
            print("[ControlBarView] Starting recording...")
            audioEngine.startRecording()
        } else {
            print("[ControlBarView] Stopping recording...")
            audioEngine.stopRecording()
        }
    }
    
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
