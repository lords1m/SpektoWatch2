import SwiftUI

// MARK: - Play/Pause Button Component
private struct PlayPauseButton: View {
    var audioEngine: AudioEngine
    let diameter: CGFloat
    let iconSize: CGFloat
    var dock: Bool = false
    let action: () -> Void

    private var state: ControlBarState {
        ControlBarState(engineStatus: audioEngine.engineStatus, isRecordingToFile: audioEngine.recording.isRecordingToFile)
    }

    var body: some View {
        Group {
            if dock { dockBody } else { barBody }
        }
        .disabled(audioEngine.engineStatus == .starting)
    }

    /// Home Screen dock tile: ink squircle, white glyph; LIVE adds the
    /// green accent bar.
    private var dockBody: some View {
        Button(action: action) {
            DockTileBackground(size: diameter, accent: state.isLiveMode ? StatusColor.live : nil)
                .overlay {
                    Image(systemName: state.isLiveMode ? "pause.fill" : "play.fill")
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(FerriteColor.onAccent)
                        .offset(y: state.isLiveMode ? -diameter * 0.04 : 0)
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityIdentifier(state.playPauseAccessibilityIdentifier)
                        .accessibilityLabel(state.playPauseAccessibilityLabel)
                        .accessibilityAddTraits(.isButton)
                }
        }
        .buttonStyle(HomeIconPressStyle())
        .animation(.easeInOut(duration: 0.2), value: state.isLiveMode)
    }

    private var barBody: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(state.isLiveMode ? StatusColor.live.opacity(0.2) : Color.clear)
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
                            .foregroundStyle(StatusColor.live)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            .accessibilityIdentifier(state.playPauseAccessibilityIdentifier)
                            .accessibilityLabel(state.playPauseAccessibilityLabel)
                            .accessibilityAddTraits(.isButton)
                    } else {
                        Image(systemName: "play.circle")
                            .font(.system(size: iconSize))
                            .foregroundStyle(StatusColor.live.opacity(0.8))
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            .accessibilityIdentifier(state.playPauseAccessibilityIdentifier)
                            .accessibilityLabel(state.playPauseAccessibilityLabel)
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: state.isLiveMode)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: state.isLiveMode)
    }
}

// MARK: - Record/Stop Button Component
private struct RecordStopButton: View {
    var audioEngine: AudioEngine
    let diameter: CGFloat
    let iconSize: CGFloat
    let isEnabled: Bool
    // When non-nil, overrides the derived isRecording state (used for masking trigger capture).
    var activeOverride: Bool? = nil
    var dock: Bool = false
    let action: () -> Void

    private var baseState: ControlBarState {
        ControlBarState(engineStatus: audioEngine.engineStatus, isRecordingToFile: audioEngine.recording.isRecordingToFile)
    }

    private var isActive: Bool { activeOverride ?? baseState.isRecording }

    var body: some View {
        if dock { dockBody } else { barBody }
    }

    /// Dock tile: the red dot is the REC accent; recording swaps it for a
    /// stop square and adds the red accent bar.
    private var dockBody: some View {
        Button(action: action) {
            DockTileBackground(size: diameter, accent: isActive ? StatusColor.recording : nil)
                .overlay {
                    Image(systemName: isActive ? "stop.fill" : "circle.fill")
                        .font(.system(size: isActive ? iconSize * 0.85 : iconSize, weight: .semibold))
                        .foregroundStyle(StatusColor.recording)
                        .offset(y: isActive ? -diameter * 0.04 : 0)
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityIdentifier(baseState.recordStopAccessibilityIdentifier)
                        .accessibilityLabel(baseState.recordStopAccessibilityLabel)
                        .accessibilityAddTraits(.isButton)
                }
        }
        .buttonStyle(HomeIconPressStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    private var barBody: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isActive ? StatusColor.recording.opacity(0.2) : Color.clear)
                    .frame(width: diameter, height: diameter)

                // Identifier directly on each Image leaf — same iOS 26 fix as
                // PlayPauseButton: no intermediate .accessibilityElement(children: .ignore).
                ZStack {
                    if isActive {
                        Image(systemName: "stop.circle")
                            .font(.system(size: iconSize))
                            .foregroundStyle(StatusColor.recording)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            .accessibilityIdentifier(baseState.recordStopAccessibilityIdentifier)
                            .accessibilityLabel(baseState.recordStopAccessibilityLabel)
                            .accessibilityAddTraits(.isButton)
                    } else {
                        Image(systemName: "record.circle.fill")
                            .font(.system(size: iconSize))
                            .foregroundStyle(StatusColor.recording.opacity(0.8))
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            .accessibilityIdentifier(baseState.recordStopAccessibilityIdentifier)
                            .accessibilityLabel(baseState.recordStopAccessibilityLabel)
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isActive)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

struct ControlBarView: View {
    enum Style { case bar, dock }

    var audioEngine: AudioEngine
    /// `.dock` renders the iOS Home Screen dock (transport, recordings and
    /// settings as squircle tiles on glass); `.bar` the classic pill.
    var style: Style = .bar
    /// Settings tile in the dock.
    var onShowSettings: (() -> Void)? = nil
    var onRecordingFeedbackChange: ((String?) -> Void)? = nil
    @Environment(AppServices.self) private var services

    private var maskingEngine: MaskingEngine { services.maskingEngine! }
    @Environment(\.designNumerals) private var numerals

    @State private var showRecordingsList = false
    @State private var liveActivityAlert = false
    @State private var showPersistenceError = false
    @State private var persistenceErrorMessage = ""
    @State private var showRecordingAlert = false
    @State private var recordingAlertTitle = ""
    @State private var recordingAlertMessage = ""
    @State private var recordingFeedbackMessage: String?
    @State private var recordingFeedbackTask: Task<Void, Never>?

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
        switch style {
        case .bar: lifecycle(barBody)
        case .dock: lifecycle(dockBody)
        }
    }

    // MARK: Dock

    private let dockTileSize: CGFloat = 60

    private var dockBody: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            controlsGroup(diameter: dockTileSize, iconSize: 24, spacing: 0, dock: true)
            Spacer(minLength: 0)
            recordingsDockTile
            Spacer(minLength: 0)
            settingsDockTile
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        // Corners follow the display (iOS 26), never tighter than the dock radius.
        .ferriteEdgeGlass(minimumRadius: FerriteRadius.dock)
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }

    private var recordingsDockTile: some View {
        let count = services.recordingManager.recordings.count
        return Button {
            showRecordingsList = true
        } label: {
            HomeIconGlyph(symbol: "folder.fill", line: AudioWidgetType.recordings.homeIconLine, size: dockTileSize)
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text(count > 99 ? "99+" : "\(count)")
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(FerriteLine.u2.onColor)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Capsule().fill(StatusColor.badge))
                            .overlay(Capsule().strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
                            .offset(x: 8, y: -8)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("recordingsListButton")
                .accessibilityLabel("Aufnahmen")
                .accessibilityValue("\(count) gespeichert")
                .accessibilityAddTraits(.isButton)
        }
        .buttonStyle(HomeIconPressStyle())
    }

    private var settingsDockTile: some View {
        Button {
            onShowSettings?()
        } label: {
            HomeIconGlyph(symbol: "gearshape.fill", size: dockTileSize)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("settingsButton")
                .accessibilityLabel("Einstellungen")
                .accessibilityAddTraits(.isButton)
        }
        .buttonStyle(HomeIconPressStyle())
    }

    // MARK: Bar

    private var barBody: some View {
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

                    recordingsButton(regular: true, badgeOffsetX: 10, badgeOffsetY: -10)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, footerVerticalPadding)
                .frame(maxWidth: .infinity)

                VStack(spacing: 8) {
                    HStack {
                        statusInfo(alignment: .leading)
                        Spacer()
                        recordingsButton(regular: false, badgeOffsetX: 8, badgeOffsetY: -8)
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
    }

    /// Sheets, alerts and engine hooks shared by both styles.
    private func lifecycle<V: View>(_ content: V) -> some View {
        content
        .sheet(isPresented: $showRecordingsList) {
            RecordingsListView()
                .environment(services)
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
        .onChange(of: audioEngine.engineStatus) { _, status in
            guard case .error = status, services.recordingManager.isRecording else { return }
            services.recordingManager.cancelRecordingStartup()
            recordingAlertTitle = String(localized: "recording.start_failed.title")
            recordingAlertMessage = String(localized: "recording.start_failed.message")
            showRecordingAlert = true
        }
        .onDisappear {
            clearRecordingStatusMessage()
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
        .alert(recordingAlertTitle, isPresented: $showRecordingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recordingAlertMessage)
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
                    .font(FerriteFont.caption.weight(.medium))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("controlBarStatusLabel")
                    .accessibilityLabel(statusText)
                if state.isRecording {
                    Text(timeString(from: services.recordingManager.currentRecordingDuration))
                        .font(.numerals(numerals, size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func controlsGroup(diameter: CGFloat, iconSize: CGFloat, spacing: CGFloat, dock: Bool = false) -> some View {
        let group = Group {
            PlayPauseButton(
                audioEngine: audioEngine,
                diameter: diameter,
                iconSize: iconSize,
                dock: dock,
                action: toggleLiveMode
            )
            if dock { Spacer(minLength: 0) }

            if maskingEngine.isCapturingTrigger {
                // During trigger capture the record button becomes the tap-to-mark button.
                RecordStopButton(
                    audioEngine: audioEngine,
                    diameter: diameter,
                    iconSize: iconSize,
                    isEnabled: true,
                    activeOverride: maskingEngine.state == .marking,
                    dock: dock,
                    action: toggleMaskingCapture
                )
            } else {
                RecordStopButton(
                    audioEngine: audioEngine,
                    diameter: diameter,
                    iconSize: iconSize,
                    isEnabled: true,
                    dock: dock,
                    action: toggleRecording
                )
            }
        }
        if dock {
            group
        } else {
            HStack(spacing: spacing) { group }
        }
    }

    private func recordingsButton(regular isRegular: Bool, badgeOffsetX: CGFloat, badgeOffsetY: CGFloat) -> some View {
        GlassIconButton(
            symbol: "folder.fill",
            iconSize: isRegular ? 18 : 16,
            diameter: isRegular ? 38 : 36,
            identifier: "recordingsListButton",
            label: "Aufnahmen",
            value: "\(services.recordingManager.recordings.count) gespeichert",
            badgeCount: services.recordingManager.recordings.count,
            badgeOffset: CGPoint(x: badgeOffsetX, y: badgeOffsetY)
        ) {
            showRecordingsList = true
        }
    }

    private var statusText: String {
        if let recordingFeedbackMessage {
            return recordingFeedbackMessage
        }
        return ControlBarStatus.text(masking: maskingEngine, state: state)
    }

    private func showRecordingStatusMessage(_ message: String) {
        recordingFeedbackTask?.cancel()
        recordingFeedbackMessage = message
        onRecordingFeedbackChange?(message)
        recordingFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            recordingFeedbackMessage = nil
            recordingFeedbackTask = nil
            onRecordingFeedbackChange?(nil)
        }
    }

    private func clearRecordingStatusMessage() {
        recordingFeedbackTask?.cancel()
        recordingFeedbackTask = nil
        recordingFeedbackMessage = nil
        onRecordingFeedbackChange?(nil)
    }

    private var statusColor: Color {
        ControlBarStatus.color(masking: maskingEngine, state: state)
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
        clearRecordingStatusMessage()
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        if audioEngine.engineStatus == .starting {
            return
        }

        if state.isLiveMode {
            audioEngine.stopLiveMode()
        } else {
            audioEngine.startLiveMode()
        }
    }

    private func toggleRecording() {
        clearRecordingStatusMessage()
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        if audioEngine.engineStatus == .starting {
            // Allow canceling a pending recording startup; ignore only when startup
            // belongs to live mode.
            if audioEngine.recording.isRecordingToFile {
                audioEngine.stopRecording()
                services.recordingManager.cancelRecordingStartup()
            }
            return
        }

        if state.isRecording {
            guard services.recordingManager.currentRecordingDuration >= 1.0 else {
                let notificationGenerator = UINotificationFeedbackGenerator()
                notificationGenerator.notificationOccurred(.warning)
                recordingAlertTitle = String(localized: "recording.too_short.title")
                recordingAlertMessage = String(localized: "recording.too_short.message")
                showRecordingAlert = true
                return
            }

            // Dauer vor dem Stoppen speichern
            let recordedDuration = services.recordingManager.currentRecordingDuration
            
            audioEngine.stopRecording()

            services.recordingManager.stopRecording(
                audioEngine: audioEngine,
                requireWrittenAudio: true
            ) { audioURL in
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
                    if services.recordingManager.persistenceError == nil {
                        let notificationGenerator = UINotificationFeedbackGenerator()
                        notificationGenerator.notificationOccurred(.success)
                        showRecordingStatusMessage(String(localized: "recording.saved"))
                    }
                    
                } else {
                    recordingAlertTitle = String(localized: "recording.save_failed.title")
                    recordingAlertMessage = String(localized: "recording.save_failed.message")
                    showRecordingAlert = true
                }
            }
        } else {
            audioEngine.recording.isMeasurementRecording = true
            let recordingStarted = services.recordingManager.startRecording(audioEngine: audioEngine)
            if recordingStarted {
                let engineStarted = audioEngine.startRecording()
                if !engineStarted {
                    services.recordingManager.cancelRecordingStartup()
                    recordingAlertTitle = String(localized: "recording.start_failed.title")
                    recordingAlertMessage = String(localized: "recording.start_failed.message")
                    showRecordingAlert = true
                }
            } else {
                recordingAlertTitle = String(localized: "recording.start_failed.title")
                recordingAlertMessage = String(localized: "recording.start_failed.message")
                showRecordingAlert = true
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
        // Native display rate (no minimumInterval cap) — at 20 Hz the glow
        // pulse stepped visibly; the view is a 6pt circle, redraw is trivial.
        TimelineView(.animation(paused: !pulsing)) { context in
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

/// Status wording and LED colour, shared by the bar and the Home Screen
/// status label.
enum ControlBarStatus {
    @MainActor
    static func text(masking maskingEngine: MaskingEngine, state: ControlBarState) -> String {
        switch maskingEngine.state {
        case .marking:
            return "Trigger · Aufzeichnung"
        case .waitingForTrigger:
            let n = maskingEngine.captureCount
            let m = maskingEngine.minimumCaptures
            return n > 0 ? "\(n)/\(m) Captures · Aufnahme drücken" : "Trigger · Aufnahme drücken"
        default:
            if state.engineStatus == .starting {
                return state.isRecordingToFile
                    ? String(localized: "recording.status.starting")
                    : String(localized: "live_mode.status.starting")
            }
            if state.isRecording { return "Aufnahme läuft" }
            if state.isLiveMode  { return "Live-Modus" }
            return "Bereit"
        }
    }

    @MainActor
    static func color(masking maskingEngine: MaskingEngine, state: ControlBarState) -> Color {
        switch maskingEngine.state {
        case .marking:        return StatusColor.recording
        case .waitingForTrigger: return StatusColor.trigger
        default:
            if state.isRecording { return StatusColor.recording }
            if state.isLiveMode  { return StatusColor.live }
            return .gray
        }
    }
}

/// Ink squircle behind a dock transport glyph; an optional status accent
/// runs along the bottom edge (green LIVE, red REC).
private struct DockTileBackground: View {
    let size: CGFloat
    var accent: Color?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FerriteRadius.homeIcon(size), style: .continuous)
        shape
            .fill(FerriteColor.label)
            .overlay(alignment: .bottom) {
                if let accent {
                    Rectangle().fill(accent).frame(height: max(5, (size * 0.11).rounded()))
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(FerriteColor.hairline, lineWidth: FerriteStroke.hairline))
            .frame(width: size, height: size)
    }
}

/// Compact instrument status for the Home Screen page pill: LED in the
/// status accent, word in ink, recording time while recording.
struct HomeStatusLabel: View {
    var audioEngine: AudioEngine
    var feedbackMessage: String? = nil
    @Environment(\.designNumerals) private var numerals
    @Environment(AppServices.self) private var services

    private var state: ControlBarState {
        ControlBarState(engineStatus: audioEngine.engineStatus, isRecordingToFile: audioEngine.recording.isRecordingToFile)
    }

    var body: some View {
        let masking = services.maskingEngine!
        HStack(spacing: 6) {
            StatusLED(color: ControlBarStatus.color(masking: masking, state: state),
                      pulsing: state.isLiveMode || state.isRecording)
            Text(feedbackMessage ?? ControlBarStatus.text(masking: masking, state: state))
                .font(FerriteFont.caption.weight(.semibold))
                .foregroundStyle(FerriteColor.label)
                .lineLimit(1)
                .accessibilityIdentifier("controlBarStatusLabel")
            if state.isRecording {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(Self.format(services.recordingManager.currentRecordingDuration))
                        .font(.numerals(numerals, size: 12, weight: .medium))
                        .foregroundStyle(FerriteColor.labelSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static func format(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
