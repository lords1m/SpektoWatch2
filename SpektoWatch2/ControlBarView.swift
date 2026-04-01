import SwiftUI
import Combine

// MARK: - Play/Pause Button Component
private struct PlayPauseButton: View {
    @ObservedObject var audioEngine: AudioEngine
    let diameter: CGFloat
    let iconSize: CGFloat
    let action: () -> Void

    private var state: ControlBarState {
        ControlBarState(engineStatus: audioEngine.engineStatus, isRecordingToFile: audioEngine.isRecordingToFile)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(state.isLiveMode ? Color.green.opacity(0.2) : Color.clear)
                    .frame(width: diameter, height: diameter)

                ZStack {
                    if state.isLiveMode {
                        Image(systemName: "pause.circle")
                            .font(.system(size: iconSize))
                            .foregroundColor(.green)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    } else {
                        Image(systemName: "play.circle")
                            .font(.system(size: iconSize))
                            .foregroundColor(.green.opacity(0.8))
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: state.isLiveMode)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: state.isLiveMode)
        .accessibilityIdentifier(state.playPauseAccessibilityIdentifier)
        .accessibilityLabel(state.playPauseAccessibilityLabel)
    }
}

// MARK: - Record/Stop Button Component
private struct RecordStopButton: View {
    @ObservedObject var audioEngine: AudioEngine
    let diameter: CGFloat
    let iconSize: CGFloat
    let isEnabled: Bool
    let action: () -> Void

    private var state: ControlBarState {
        ControlBarState(engineStatus: audioEngine.engineStatus, isRecordingToFile: audioEngine.isRecordingToFile)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(state.isRecording ? Color.red.opacity(0.2) : Color.clear)
                    .frame(width: diameter, height: diameter)

                ZStack {
                    if state.isRecording {
                        Image(systemName: "stop.circle")
                            .font(.system(size: iconSize))
                            .foregroundColor(.red)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    } else {
                        Image(systemName: "record.circle.fill")
                            .font(.system(size: iconSize))
                            .foregroundColor(.red.opacity(0.8))
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: state.isRecording)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.2), value: state.isRecording)
        .accessibilityIdentifier(state.recordStopAccessibilityIdentifier)
        .accessibilityLabel(state.recordStopAccessibilityLabel)
    }
}

struct ControlBarView: View {
    @ObservedObject var audioEngine: AudioEngine
    @EnvironmentObject private var recordingManager: RecordingManager

    @State private var showRecordingsList = false

    private let footerVerticalPadding: CGFloat = 10
    private let regularControlDiameter: CGFloat = 50
    private let regularControlIconSize: CGFloat = 40
    private let compactControlDiameter: CGFloat = 44
    private let compactControlIconSize: CGFloat = 34

    // Computed properties für reaktive Updates
    private var state: ControlBarState {
        ControlBarState(engineStatus: audioEngine.engineStatus, isRecordingToFile: audioEngine.isRecordingToFile)
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    statusInfo(alignment: .leading)
                        .fixedSize(horizontal: true, vertical: true)

                    Spacer(minLength: 8)

                    controlsGroup(
                        diameter: regularControlDiameter,
                        iconSize: regularControlIconSize,
                        spacing: 20
                    )

                    Spacer(minLength: 8)

                    recordingsButton(font: .title2, badgeOffsetX: 10, badgeOffsetY: -10)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, footerVerticalPadding)
                .frame(maxWidth: .infinity)

                VStack(spacing: 8) {
                    HStack {
                        statusInfo(alignment: .leading)
                        Spacer()
                        recordingsButton(font: .headline, badgeOffsetX: 8, badgeOffsetY: -8)
                    }
                    controlsGroup(
                        diameter: compactControlDiameter,
                        iconSize: compactControlIconSize,
                        spacing: 16
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
            }
        }
        .backgroundExtensionEffect(cornerRadius: 24)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .sheet(isPresented: $showRecordingsList) {
            RecordingsListView().environmentObject(recordingManager)
        }
        .onAppear {
            audioEngine.prewarmAudioSession()
        }
    }

    @ViewBuilder
    private func statusInfo(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(statusColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if state.isRecording {
                Text(timeString(from: recordingManager.currentRecordingDuration))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
        }
    }

    private func controlsGroup(diameter: CGFloat, iconSize: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            PlayPauseButton(
                audioEngine: audioEngine,
                diameter: diameter,
                iconSize: iconSize,
                action: toggleLiveMode
            )

            let canStopRecording = !(state.isRecording && recordingManager.currentRecordingDuration < 1.0)
            RecordStopButton(
                audioEngine: audioEngine,
                diameter: diameter,
                iconSize: iconSize,
                isEnabled: canStopRecording,
                action: toggleRecording
            )
        }
    }

    private func recordingsButton(font: Font, badgeOffsetX: CGFloat, badgeOffsetY: CGFloat) -> some View {
        Button(action: {
            showRecordingsList = true
        }) {
            ZStack {
                Image(systemName: "folder.fill")
                    .font(font)
                    .foregroundColor(.blue)

                if recordingManager.recordings.count > 0 {
                    Text("\(recordingManager.recordings.count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.red)
                        .clipShape(Circle())
                        .offset(x: badgeOffsetX, y: badgeOffsetY)
                }
            }
        }
        .accessibilityIdentifier("recordingsListButton")
        .accessibilityLabel("Aufnahmen")
    }

    private var statusText: String {
        if state.isRecording {
            return "Aufnahme läuft"
        } else if state.isLiveMode {
            return "Live-Modus"
        } else {
            return "Bereit"
        }
    }

    private var statusColor: Color {
        if state.isRecording {
            return .red
        } else if state.isLiveMode {
            return .green
        } else {
            return .gray
        }
    }

    private func toggleLiveMode() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        if audioEngine.engineStatus == .starting {
            print("[ControlBarView] Ignoring toggleLiveMode while starting")
            return
        }

        print("[ControlBarView] toggleLiveMode - Current state:")
        print("  engineStatus: \(audioEngine.engineStatus)")
        print("  isRecordingToFile: \(audioEngine.isRecordingToFile)")
        print("  engineRunning: \(state.engineRunning)")
        print("  isLiveMode: \(state.isLiveMode)")

        if state.isLiveMode {
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

        if audioEngine.engineStatus == .starting {
            // Allow canceling a pending recording startup; ignore only when startup
            // belongs to live mode.
            if audioEngine.isRecordingToFile {
                print("[ControlBarView] Cancelling pending recording while starting")
                audioEngine.stopRecording()
                recordingManager.stopRecording(audioEngine: audioEngine) { _ in }
            } else {
                print("[ControlBarView] Ignoring toggleRecording while starting live mode")
            }
            return
        }

        print("[ControlBarView] toggleRecording - Current state:")
        print("  engineStatus: \(audioEngine.engineStatus)")
        print("  isRecordingToFile: \(audioEngine.isRecordingToFile)")
        print("  engineRunning: \(state.engineRunning)")
        print("  isRecording: \(state.isRecording)")

        if state.isRecording {
            guard recordingManager.currentRecordingDuration >= 1.0 else {
                let notificationGenerator = UINotificationFeedbackGenerator()
                notificationGenerator.notificationOccurred(.warning)
                print("[ControlBarView] Recording too short (min 1 second)")
                return
            }

            print("[ControlBarView] Stopping recording...")
            
            // Dauer vor dem Stoppen speichern
            let recordedDuration = recordingManager.currentRecordingDuration
            
            audioEngine.stopRecording()

            recordingManager.stopRecording(audioEngine: audioEngine) { audioURL in
                if let url = audioURL {
                    // Automatisch speichern mit Zeitstempel als Name
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
                    let timestamp = dateFormatter.string(from: Date())
                    
                    var recording = Recording(
                        name: "Messung \(timestamp)",
                        description: "",
                        startDate: Date().addingTimeInterval(-recordedDuration),
                        duration: recordedDuration,
                        audioFileName: url.path,
                        measurementDataFileName: audioEngine.lastMeasurementDataURL?.path,
                        sampleRate: audioEngine.currentSpectrogramData?.sampleRate ?? 44100.0,
                        channelCount: 1,
                        timeWeighting: audioEngine.timeWeighting.rawValue,
                        frequencyWeighting: audioEngine.frequencyWeighting.rawValue,
                        widgetConfigurations: UserDefaults.standard.data(forKey: "DashboardConfiguration_v5"),
                        markers: [],
                        calibrationOffset: audioEngine.calibrationOffset,
                        fftBlockSize: audioEngine.currentBlockSize.rawValue
                    )
                    
                    // Statistiken aus AudioEngine übernehmen
                    if let data = audioEngine.currentSpectrogramData {
                        recording.laeqFast = data.levels["LAeq"] ?? -120.0
                        recording.peakLevel = data.levels["LCpeak"] ?? -120.0
                        recording.minLevel = data.levels["LAFmin"] ?? -120.0
                    }
                    
                    recordingManager.addRecording(recording)
                    
                    // Success feedback
                    let notificationGenerator = UINotificationFeedbackGenerator()
                    notificationGenerator.notificationOccurred(.success)
                    
                    print("[ControlBarView] Recording automatically saved: \(recording.name)")
                }
            }
        } else {
            print("[ControlBarView] Starting recording...")
            audioEngine.isMeasurementRecording = true
            let recordingStarted = recordingManager.startRecording(audioEngine: audioEngine)
            print("[ControlBarView] RecordingManager.startRecording() returned: \(recordingStarted)")
            if recordingStarted {
                print("[ControlBarView] Calling audioEngine.startRecording()...")
                audioEngine.startRecording()
                print("[ControlBarView] audioEngine.startRecording() called")
            } else {
                print("[ControlBarView] ERROR: RecordingManager failed to start recording!")
            }
        }
    }

    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
