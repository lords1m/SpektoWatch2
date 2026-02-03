import SwiftUI

struct ControlBarView: View {
    @ObservedObject var audioEngine: AudioEngine
    @EnvironmentObject private var recordingManager: RecordingManager

    @State private var showSaveDialog = false
    @State private var showRecordingsList = false
    @State private var recordedAudioURL: URL?
    @State private var recordedDuration: TimeInterval = 0

    /// Safe Area Bottom Inset für iPhones mit Home Indicator
    private var safeAreaBottomInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        return windowScene?.windows.first?.safeAreaInsets.bottom ?? 0
    }

    // Computed properties für reaktive Updates
    private var engineRunning: Bool {
        audioEngine.engineStatus == .running || audioEngine.engineStatus == .starting
    }

    private var isLiveMode: Bool {
        engineRunning && !audioEngine.isRecordingToFile
    }

    private var isRecording: Bool {
        audioEngine.engineStatus == .running && audioEngine.isRecordingToFile
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Separator
            Divider()
                .background(Color.gray.opacity(0.3))

            HStack(spacing: 16) {
                // Status Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(statusColor)
                    if isRecording {
                        Text(timeString(from: recordingManager.currentRecordingDuration))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Button Group - Play & Record
                HStack(spacing: 20) {
                    // Play/Pause Button (Live-Modus)
                    Button(action: toggleLiveMode) {
                        ZStack {
                            Circle()
                                .fill(isLiveMode ? Color.green.opacity(0.2) : Color.clear)
                                .frame(width: 50, height: 50)

                            Image(systemName: isLiveMode ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(isLiveMode ? .green : .green.opacity(0.8))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isRecording)
                    .animation(.easeInOut(duration: 0.2), value: isLiveMode)
                    .accessibilityIdentifier(isLiveMode ? "pauseButton" : "playButton")
                    .accessibilityLabel(isLiveMode ? "Pause" : "Play")

                    // Record Button
                    Button(action: toggleRecording) {
                        ZStack {
                            Circle()
                                .fill(isRecording ? Color.red.opacity(0.2) : Color.clear)
                                .frame(width: 50, height: 50)

                            Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                                .font(.system(size: 40))
                                .foregroundColor(isRecording ? .red : .red.opacity(0.8))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isRecording && recordingManager.currentRecordingDuration < 5.0)
                    .animation(.easeInOut(duration: 0.2), value: isRecording)
                    .accessibilityIdentifier(isRecording ? "stopButton" : "recordButton")
                    .accessibilityLabel(isRecording ? "Stop" : "Aufnahme")
                }

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
                .accessibilityIdentifier("recordingsListButton")
                .accessibilityLabel("Aufnahmen")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, max(12, safeAreaBottomInset))
            .frame(maxWidth: .infinity)
        }
        .background(
            Color(UIColor.systemBackground)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
        )
        .ignoresSafeArea(.container, edges: .bottom)
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

    private var statusText: String {
        if isRecording {
            return "Aufnahme läuft"
        } else if isLiveMode {
            return "Live-Modus"
        } else {
            return "Bereit"
        }
    }

    private var statusColor: Color {
        if isRecording {
            return .red
        } else if isLiveMode {
            return .green
        } else {
            return .gray
        }
    }

    private func toggleLiveMode() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        print("[ControlBarView] toggleLiveMode - Current state:")
        print("  engineStatus: \(audioEngine.engineStatus)")
        print("  isRecordingToFile: \(audioEngine.isRecordingToFile)")
        print("  engineRunning: \(engineRunning)")
        print("  isLiveMode: \(isLiveMode)")

        if isLiveMode {
            print("[ControlBarView] Stopping live mode...")
            audioEngine.stopLiveMode()
        } else {
            print("[ControlBarView] Starting live mode...")
            audioEngine.startLiveMode()
        }
    }

    private func toggleRecording() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        print("[ControlBarView] toggleRecording - Current state:")
        print("  engineStatus: \(audioEngine.engineStatus)")
        print("  isRecordingToFile: \(audioEngine.isRecordingToFile)")
        print("  engineRunning: \(engineRunning)")
        print("  isRecording: \(isRecording)")

        if isRecording {
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
