import SwiftUI

struct ControlBarView: View {
    @ObservedObject var audioEngine: AudioEngine
    @EnvironmentObject private var recordingManager: RecordingManager
    
    @State private var showSaveDialog = false
    @State private var showRecordingsList = false
    @State private var recordedAudioURL: URL?
    @State private var recordedDuration: TimeInterval = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Separator
            Divider()
                .background(Color.gray.opacity(0.3))
            
            HStack(spacing: 16) {
                // Status Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(recordingManager.isRecording ? "Aufnahme läuft" : "Bereit")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(recordingManager.isRecording ? .red : .gray)
                    if recordingManager.isRecording {
                        Text(timeString(from: recordingManager.currentRecordingDuration))
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
                            .fill(recordingManager.isRecording ? Color.red.opacity(0.2) : Color.clear)
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: recordingManager.isRecording ? "stop.circle.fill" : "record.circle")
                            .font(.system(size: 50))
                            .foregroundColor(recordingManager.isRecording ? .red : (recordingManager.currentRecordingDuration < 5.0 && recordingManager.isRecording ? .gray : .red))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(recordingManager.isRecording && recordingManager.currentRecordingDuration < 5.0) // Min 5 Sekunden
                
                Spacer()
                
                // Recordings List Button
                Button(action: {
                    showRecordingsList = true
                }) {
                    ZStack {
                        Image(systemName: "folder.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                        
                        // Badge mit Anzahl
                        if recordingManager.recordings.count > 0 {
                            Text("\(recordingManager.recordings.count)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.red)
                                .clipShape(Circle())
                                .offset(x: 10, y: -10)
                        }
                    }
                }
                .frame(width: 100, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
        }
        .background(
            Color(UIColor.systemBackground)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
        )
        .sheet(isPresented: $showSaveDialog) {
            if let audioURL = recordedAudioURL {
                SaveRecordingView(
                    audioURL: audioURL,
                    duration: recordedDuration,
                    audioEngine: audioEngine
                )
            }
        }
        .sheet(isPresented: $showRecordingsList) {
            RecordingsListView().environmentObject(recordingManager)
        }
    }
    
    private func toggleRecording() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        if recordingManager.isRecording {
            // Stoppen nur nach min 5 Sekunden
            guard recordingManager.currentRecordingDuration >= 5.0 else {
                let notificationGenerator = UINotificationFeedbackGenerator()
                notificationGenerator.notificationOccurred(.warning)
                print("[ControlBarView] Recording too short (min 5 seconds)")
                return
            }
            
            print("[ControlBarView] Stopping recording...")
            audioEngine.stopRecording()
            
            recordingManager.stopRecording(audioEngine: audioEngine) { audioURL in
                if let url = audioURL {
                    recordedAudioURL = url
                    recordedDuration = recordingManager.currentRecordingDuration
                    
                    // Zeige Save-Dialog
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showSaveDialog = true
                    }
                }
            }
        } else {
            print("[ControlBarView] Starting recording...")
            if recordingManager.startRecording(audioEngine: audioEngine) {
                audioEngine.startRecording()
            }
        }
    }
    
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
