import SwiftUI
import Combine

// MARK: - Play/Pause Button Component
private struct PlayPauseButton: View {
    @ObservedObject var audioEngine: AudioEngine
    let diameter: CGFloat
    let iconSize: CGFloat
    let action: () -> Void

    private var state: ControlBarState {
        ControlBarState(engineStatus: audioEngine.engineStatus, isRecordingToFile: audioEngine.recording.isRecordingToFile)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(state.isLiveMode ? Color.green.opacity(0.2) : Color.clear)
                    .frame(width: diameter, height: diameter)

                // In iOS 26 with PlainButtonStyle the Button wrapper is accessibility-
                // transparent. The Image leaf is what XCUITest sees. Identifier and label
                // are placed directly on each Image — no intermediate ZStack, no
                // .accessibilityElement(children: .ignore) which triggers parent-identifier
                // inheritance in iOS 26. Image is already a leaf so no children: .ignore
                // is needed.
                ZStack {
                    if state.isLiveMode {
                        Image(systemName: "pause.circle")
                            .font(.system(size: iconSize))
                            .foregroundColor(.green)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            .accessibilityIdentifier(state.playPauseAccessibilityIdentifier)
                            .accessibilityLabel(state.playPauseAccessibilityLabel)
                            .accessibilityAddTraits(.isButton)
                    } else {
                        Image(systemName: "play.circle")
                            .font(.system(size: iconSize))
                            .foregroundColor(.green.opacity(0.8))
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            .accessibilityIdentifier(state.playPauseAccessibilityIdentifier)
                            .accessibilityLabel(state.playPauseAccessibilityLabel)
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: state.isLiveMode)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: state.isLiveMode)
    }
}

// MARK: - Record/Stop Button Component
private struct RecordStopButton: View {
    @ObservedObject var audioEngine: AudioEngine
    let diameter: CGFloat
    let iconSize: CGFloat
    let isEnabled: Bool
    // When non-nil, overrides the derived isRecording state (used for masking trigger capture).
    var activeOverride: Bool? = nil
    let action: () -> Void

    private var baseState: ControlBarState {
        ControlBarState(engineStatus: audioEngine.engineStatus, isRecordingToFile: audioEngine.recording.isRecordingToFile)
    }

    private var isActive: Bool { activeOverride ?? baseState.isRecording }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.red.opacity(0.2) : Color.clear)
                    .frame(width: diameter, height: diameter)

                // Identifier directly on each Image leaf — same iOS 26 fix as
                // PlayPauseButton: no intermediate .accessibilityElement(children: .ignore).
                ZStack {
                    if isActive {
                        Image(systemName: "stop.circle")
                            .font(.system(size: iconSize))
                            .foregroundColor(.red)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            .accessibilityIdentifier(baseState.recordStopAccessibilityIdentifier)
                            .accessibilityLabel(baseState.recordStopAccessibilityLabel)
                            .accessibilityAddTraits(.isButton)
                    } else {
                        Image(systemName: "record.circle.fill")
                            .font(.system(size: iconSize))
                            .foregroundColor(.red.opacity(0.8))
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            .accessibilityIdentifier(baseState.recordStopAccessibilityIdentifier)
                            .accessibilityLabel(baseState.recordStopAccessibilityLabel)
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isActive)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

struct ControlBarView: View {
    @ObservedObject var audioEngine: AudioEngine
    @EnvironmentObject private var services: AppServices

    private var maskingEngine: MaskingEngine { services.maskingEngine! }
    @Environment(\.designNumerals) private var numerals

    @State private var showRecordingsList = false
    @State private var liveActivityAlert = false
    @State private var showPersistenceError = false
    @State private var persistenceErrorMessage = ""

    private let footerVerticalPadding: CGFloat = 10
    private let regularControlDiameter: CGFloat = 38
    private let regularControlIconSize: CGFloat = 22
    private let compactControlDiameter: CGFloat = 36
    private let compactControlIconSize: CGFloat = 20

    // Computed properties für reaktive Updates
    private var state: ControlBarState {
        ControlBarState(engineStatus: audioEngine.engineStatus, isRecordingToFile: audioEngine.recording.isRecordingToFile)
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
        .floatingPill(cornerRadius: 24)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .sheet(isPresented: $showRecordingsList) {
            RecordingsListView()
                .environmentObject(services)
                .polishedSheetChrome()
        }
        .onAppear {
            audioEngine.prewarmAudioSession()
        }
        .onChange(of: services.recordingManager.persistenceError) { _, error in
            guard let error else { return }
            showPersistenceError = true
            persistenceErrorMessage = error
        }
        .onChange(of: services.recordingManager.liveActivityError) { _, error in
            if error != nil { liveActivityAlert = true }
        }
        .alert("Speichern fehlgeschlagen", isPresented: $showPersistenceError) {
            Button("OK") {
                services.recordingManager.persistenceError = nil
                showPersistenceError = false
            }
        } message: {
            Text(persistenceErrorMessage)
        }
        .alert("Live Activity", isPresented: $liveActivityAlert) {
            Button("OK") { services.recordingManager.liveActivityError = nil }
        } message: {
            Text(services.recordingManager.liveActivityError ?? "")
        }
        // NOTE: No .accessibilityIdentifier("controlBarView") here — in iOS 26,
        // named container identifiers are inherited by all PlainButtonStyle descendant
        // elements, overriding the custom identifiers we set on leaf Images.
    }

    @ViewBuilder
    private func statusInfo(alignment: HorizontalAlignment) -> some View {
        HStack(spacing: 8) {
            StatusLED(color: statusColor, pulsing: state.isLiveMode || state.isRecording)
            VStack(alignment: alignment, spacing: 1) {
                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("controlBarStatusLabel")
                    .accessibilityLabel(statusText)
                if state.isRecording {
                    Text(timeString(from: services.recordingManager.currentRecordingDuration))
                        .font(.numerals(numerals, size: 11))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
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

            if maskingEngine.isCapturingTrigger {
                // During trigger capture the record button becomes the tap-to-mark button.
                RecordStopButton(
                    audioEngine: audioEngine,
                    diameter: diameter,
                    iconSize: iconSize,
                    isEnabled: true,
                    activeOverride: maskingEngine.state == .marking,
                    action: toggleMaskingCapture
                )
            } else {
                let canStopRecording = !(state.isRecording && services.recordingManager.currentRecordingDuration < 1.0)
                RecordStopButton(
                    audioEngine: audioEngine,
                    diameter: diameter,
                    iconSize: iconSize,
                    isEnabled: canStopRecording,
                    action: toggleRecording
                )
            }
        }
    }

    private func recordingsButton(font: Font, badgeOffsetX: CGFloat, badgeOffsetY: CGFloat) -> some View {
        let diameter: CGFloat = font == .title2 ? 38 : 36
        return Button(action: {
            showRecordingsList = true
        }) {
            ZStack {
                Image(systemName: "folder.fill")
                    .font(.system(size: font == .title2 ? 18 : 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: diameter, height: diameter)
                    .background(Circle().fill(.thinMaterial))
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
                    .accessibilityIdentifier("recordingsListButton")
                    .accessibilityLabel("Aufnahmen")
                    .accessibilityAddTraits(.isButton)

                if services.recordingManager.recordings.count > 0 {
                    Text("\(services.recordingManager.recordings.count)")
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
        .buttonStyle(.plain)
    }

    private var statusText: String {
        switch maskingEngine.state {
        case .marking:
            return "Trigger · Aufzeichnung"
        case .waitingForTrigger:
            let n = maskingEngine.captureCount
            let m = maskingEngine.minimumCaptures
            return n > 0 ? "\(n)/\(m) Captures · Aufnahme drücken" : "Trigger · Aufnahme drücken"
        default:
            if state.isRecording { return "Aufnahme läuft" }
            if state.isLiveMode  { return "Live-Modus" }
            return "Bereit"
        }
    }

    private var statusColor: Color {
        switch maskingEngine.state {
        case .marking:        return .red
        case .waitingForTrigger: return Color(red: 0.0, green: 0.85, blue: 1.0)
        default:
            if state.isRecording { return .red }
            if state.isLiveMode  { return .green }
            return .gray
        }
    }

    private func toggleMaskingCapture() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if maskingEngine.state == .marking {
            maskingEngine.endMark()
        } else if case .waitingForTrigger = maskingEngine.state {
            maskingEngine.beginMark()
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
        print("  isRecordingToFile: \(audioEngine.recording.isRecordingToFile)")
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
            if audioEngine.recording.isRecordingToFile {
                print("[ControlBarView] Cancelling pending recording while starting")
                audioEngine.stopRecording()
                services.recordingManager.stopRecording(audioEngine: audioEngine) { _ in }
            } else {
                print("[ControlBarView] Ignoring toggleRecording while starting live mode")
            }
            return
        }

        print("[ControlBarView] toggleRecording - Current state:")
        print("  engineStatus: \(audioEngine.engineStatus)")
        print("  isRecordingToFile: \(audioEngine.recording.isRecordingToFile)")
        print("  engineRunning: \(state.engineRunning)")
        print("  isRecording: \(state.isRecording)")

        if state.isRecording {
            guard services.recordingManager.currentRecordingDuration >= 1.0 else {
                let notificationGenerator = UINotificationFeedbackGenerator()
                notificationGenerator.notificationOccurred(.warning)
                print("[ControlBarView] Recording too short (min 1 second)")
                return
            }

            print("[ControlBarView] Stopping recording...")
            
            // Dauer vor dem Stoppen speichern
            let recordedDuration = services.recordingManager.currentRecordingDuration
            
            audioEngine.stopRecording()

            services.recordingManager.stopRecording(audioEngine: audioEngine) { audioURL in
                if let url = audioURL {
                    // Automatisch speichern mit Zeitstempel als Name
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
                    let saveDate = Date()
                    let timestamp = dateFormatter.string(from: saveDate)
                    let startDate = services.recordingManager.recordingStartDate
                        ?? saveDate.addingTimeInterval(-recordedDuration)
                    let measurementURL = audioEngine.lastMeasurementDataURL
                    let duration = RecordingManager.resolvedRecordingDuration(
                        audioURL: url,
                        measurementURL: measurementURL,
                        fallback: recordedDuration
                    )

                    var recording = Recording(
                        name: "Messung \(timestamp)",
                        description: "",
                        startDate: startDate,
                        duration: duration,
                        audioFileName: url.path,
                        measurementDataFileName: audioEngine.lastMeasurementDataURL?.path,
                        sampleRate: audioEngine.live.currentSpectrogramData?.sampleRate ?? 44100.0,
                        channelCount: 1,
                        timeWeighting: audioEngine.timeWeighting.rawValue,
                        frequencyWeighting: audioEngine.frequencyWeighting.rawValue,
                        widgetConfigurations: UserDefaults.standard.data(forKey: PersistenceKeys.dashboardLegacySnapshot),
                        markers: [],
                        calibrationOffset: audioEngine.calibrationOffset,
                        fftBlockSize: audioEngine.currentBlockSize.rawValue
                    )
                    
                    // Statistiken aus AudioEngine übernehmen
                    if let data = audioEngine.live.currentSpectrogramData {
                        recording.laeqFast = data.levels["LAeq"] ?? -120.0
                        recording.peakLevel = data.levels["LCpeak"] ?? -120.0
                        recording.minLevel = data.levels["LAFmin"] ?? -120.0
                    }
                    
                    services.recordingManager.addRecording(recording)
                    
                    // Success feedback
                    let notificationGenerator = UINotificationFeedbackGenerator()
                    notificationGenerator.notificationOccurred(.success)
                    
                    print("[ControlBarView] Recording automatically saved: \(recording.name)")
                }
            }
        } else {
            print("[ControlBarView] Starting recording...")
            audioEngine.recording.isMeasurementRecording = true
            let recordingStarted = services.recordingManager.startRecording(audioEngine: audioEngine)
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

/// Small status indicator dot — 6pt circle that pulses when `pulsing` is true.
/// Uses TimelineView so the animation belongs to the system clock, not a
/// repeatForever transaction that can't be cleanly cancelled.
private struct StatusLED: View {
    let color: Color
    let pulsing: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: !pulsing)) { context in
            let phase = pulsing
                ? 0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * .pi * 1.1)
                : 1.0
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .opacity(pulsing ? (0.45 + 0.55 * phase) : 1.0)
                .shadow(color: color.opacity(0.7), radius: pulsing ? (2 + 4 * phase) : 0)
        }
    }
}
