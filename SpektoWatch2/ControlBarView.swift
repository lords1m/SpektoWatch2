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
        .animation(.easeInOut(duration: 0.2), value: state.isRecording)
        .accessibilityIdentifier(state.recordStopAccessibilityIdentifier)
        .accessibilityLabel(state.recordStopAccessibilityLabel)
    }
}

struct ControlBarView: View {
    @ObservedObject var audioEngine: AudioEngine
    @EnvironmentObject private var recordingManager: RecordingManager

    @State private var showSaveDialog = false
    @State private var showRecordingsList = false
    @State private var recordedAudioURL: URL?
    @State private var recordedDuration: TimeInterval = 0

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

                    HStack(spacing: 12) {
                        measurementToggleButton(font: .title3)
                        recordingsButton(font: .title2, badgeOffsetX: 10, badgeOffsetY: -10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, footerVerticalPadding)
                .frame(maxWidth: .infinity)

                VStack(spacing: 8) {
                    HStack {
                        statusInfo(alignment: .leading)
                        Spacer()
                        HStack(spacing: 10) {
                            measurementToggleButton(font: .callout)
                            recordingsButton(font: .headline, badgeOffsetX: 8, badgeOffsetY: -8)
                        }
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

            RecordStopButton(
                audioEngine: audioEngine,
                diameter: diameter,
                iconSize: iconSize,
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

    private func measurementToggleButton(font: Font) -> some View {
        Button(action: {
            audioEngine.isMeasurementRecording.toggle()
        }) {
            Image(systemName: audioEngine.isMeasurementRecording ? "waveform.badge.checkmark" : "waveform.badge.plus")
                .font(font)
                .foregroundColor(audioEngine.isMeasurementRecording ? .orange : .secondary)
        }
        .accessibilityIdentifier("measurementRecordingToggle")
        .accessibilityLabel(audioEngine.isMeasurementRecording ? "Messdatenaufzeichnung aktiv" : "Messdatenaufzeichnung inaktiv")
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
            print("[ControlBarView] Ignoring toggleRecording while starting")
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
