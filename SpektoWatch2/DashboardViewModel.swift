import AsyncAlgorithms
import SwiftUI
import Observation

struct WidgetUndoToast: Equatable, Identifiable {
    let id = UUID()
    let widget: WidgetConfiguration
    let index: Int
}

@Observable
@MainActor
class DashboardViewModel {
    // UI State
    let dashboardManager: DashboardManager
    var showWidgetPicker = false
    var draggedWidget: WidgetConfiguration?
    var showSettings = false
    var widgetUndoToast: WidgetUndoToast?
    @ObservationIgnored private var widgetUndoTask: Task<Void, Never>?
    private static let widgetUndoWindow: Duration = .seconds(4)

    // Settings State
    var selectedMicrophoneSource: MicrophoneSource = .iPhone
    var watchGain: Float = {
        let stored = UserDefaults.standard.object(forKey: PersistenceKeys.Watch.gain) as? Float
        return stored ?? 1.0
    }()
    var showWatchNotReachableAlert = false

    // Dependencies
    let audioEngine: AudioEngine
    let connectivityManager: WatchConnectivityManager

    @ObservationIgnored private var observationTasks: [Task<Void, Never>] = []
    @ObservationIgnored private let watchGainContinuation: AsyncStream<Float>.Continuation
    private static let watchGainSyncDebounce: Duration = .milliseconds(150)

    private enum WatchRecordingCommand: Sendable {
        case start(MicrophoneSource?)
        case stop(MicrophoneSource?)
    }

    init(dashboardManager: DashboardManager, audioEngine: AudioEngine, connectivityManager: WatchConnectivityManager) {
        self.dashboardManager = dashboardManager
        self.audioEngine = audioEngine
        self.connectivityManager = connectivityManager

        let (watchGainStream, watchGainContinuation) = AsyncStream<Float>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.watchGainContinuation = watchGainContinuation

        updateWidgetSpectralWeightingRequirements(for: dashboardManager.widgets)

        // Debounce Watch gain slider updates so dragging does not flood WCSession / UserDefaults.
        observationTasks.append(Task { @MainActor [weak self] in
            for await gain in watchGainStream
                .debounce(for: Self.watchGainSyncDebounce, clock: .continuous)
                .removeDuplicates() {
                guard let self, !Task.isCancelled else { break }
                UserDefaults.standard.set(gain, forKey: PersistenceKeys.Watch.gain)
                self.connectivityManager.sendGainValue(gain)
            }
        })

        observationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            await ObservationTrackingLoop.observe(emitInitial: false, { self.dashboardManager.widgets }) { [weak self] widgets in
                self?.updateWidgetSpectralWeightingRequirements(for: widgets)
            }
        })

        // Auto-Fallback: Watch bricht Verbindung während Aufnahme ab
        observationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            await ObservationTrackingLoop.observe(emitInitial: false, { self.connectivityManager.isReachable }) { [weak self] isReachable in
                guard let self, !isReachable else { return }
                if self.selectedMicrophoneSource == .appleWatch && self.audioEngine.engineStatus == .running {
                    _ = self.applyMicrophoneSourceSelection(.iPhone, notifyWatch: true)
                    self.restartActiveMeasurementForSelectedSource(.iPhone)
                }
            }
        })

        observationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            await ObservationTrackingLoop.observe({ self.connectivityManager.selectedMicrophoneSource }) { [weak self] source in
                guard let self, self.selectedMicrophoneSource != source else { return }
                _ = self.applyMicrophoneSourceSelection(source, notifyWatch: false)
            }
        })

        let incomingStream = connectivityManager.incomingSpectrogramBroadcaster.stream()
        observationTasks.append(Task { @MainActor [weak self] in
            for await data in incomingStream {
                guard let self, !Task.isCancelled else { break }
                guard self.selectedMicrophoneSource == .appleWatch else { continue }
                if self.audioEngine.engineStatus != .running {
                    self.audioEngine.startWearableLiveMode()
                }
                self.audioEngine.ingestWearableSpectrogramData(data)
            }
        })

        // Start/Stop-Befehle von der Apple Watch über einen zusammengeführten AsyncStream empfangen
        let startCommands = Self.watchCommandStream(for: .startRecordingCommand) { .start($0) }
        let stopCommands = Self.watchCommandStream(for: .stopRecordingCommand) { .stop($0) }
        observationTasks.append(Task { @MainActor [weak self] in
            for await command in merge(startCommands, stopCommands) {
                guard let self, !Task.isCancelled else { break }
                switch command {
                case .start(let source):
                    self.handleWatchRecordingStart(source: source)
                case .stop(let source):
                    self.handleWatchRecordingStop(source: source)
                }
            }
        })
    }

    private static func watchCommandStream(
        for name: Notification.Name,
        transform: @escaping @Sendable (MicrophoneSource?) -> WatchRecordingCommand
    ) -> AsyncStream<WatchRecordingCommand> {
        AsyncStream { continuation in
            let token = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: nil
            ) { notification in
                continuation.yield(transform(notification.object as? MicrophoneSource))
            }
            nonisolated(unsafe) let removableToken = token
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(removableToken)
            }
        }
    }

    deinit {
        watchGainContinuation.finish()
        for task in observationTasks {
            task.cancel()
        }
    }
    
    func handleMicrophoneSourceChange(_ newSource: MicrophoneSource) {
        // Re-entrancy guard for the watch-unreachable fallback path:
        //
        // 1. User picks `.appleWatch` → `selectedMicrophoneSource = .appleWatch`
        //    → `onChange` fires.
        // 2. `applyMicrophoneSourceSelection(.appleWatch)` detects the watch is
        //    unreachable, rolls back: `selectedMicrophoneSource = .iPhone`.
        // 3. That rollback re-triggers `onChange` with `newSource = .iPhone`.
        // 4. `apply(.iPhone)` succeeds; without this guard,
        //    `restartActiveMeasurementForSelectedSource(.iPhone)` would tear
        //    down and restart the (already-running-on-iPhone) engine.
        //
        // The audit's suggested guard `newSource != selectedMicrophoneSource`
        // is unusable here: SwiftUI `onChange` fires AFTER the property has
        // been updated, so the two are always equal inside this closure.
        // Instead, skip when the audio engine is already serving the
        // requested source — that's the actual condition we want to avoid
        // re-applying.
        guard audioEngine.activeMicrophoneSource != newSource else { return }
        guard applyMicrophoneSourceSelection(newSource, notifyWatch: true) else { return }
        restartActiveMeasurementForSelectedSource(newSource)
    }

    @discardableResult
    private func applyMicrophoneSourceSelection(_ newSource: MicrophoneSource, notifyWatch: Bool) -> Bool {
        if newSource == .appleWatch && !connectivityManager.isReachable {
            selectedMicrophoneSource = .iPhone
            showWatchNotReachableAlert = true
            return false
        }

        selectedMicrophoneSource = newSource
        connectivityManager.selectedMicrophoneSource = newSource
        if notifyWatch {
            connectivityManager.sendMicrophoneSourceSelection(newSource)
        }
        return true
    }

    private func restartActiveMeasurementForSelectedSource(_ newSource: MicrophoneSource) {
        guard audioEngine.engineStatus == .running else { return }
        let wasRecordingToFile = audioEngine.recording.isRecordingToFile

        if audioEngine.activeMicrophoneSource == .appleWatch {
            audioEngine.stopWearableLiveMode()
        } else {
            audioEngine.stopRecording()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            switch newSource {
            case .iPhone:
                if wasRecordingToFile {
                    self.audioEngine.startRecording()
                } else {
                    self.audioEngine.startLiveMode()
                }
            case .appleWatch:
                self.connectivityManager.requestWearableRecordingStart()
                self.audioEngine.startWearableLiveMode()
            }
        }
    }

    private func handleWatchRecordingStart(source: MicrophoneSource?) {
        let requestedSource = source ?? connectivityManager.selectedMicrophoneSource
        guard applyMicrophoneSourceSelection(requestedSource, notifyWatch: false) else { return }
        guard !audioEngine.recording.isRecordingToFile else { return }

        if audioEngine.engineStatus == .running {
            guard audioEngine.activeMicrophoneSource != requestedSource else { return }
            if audioEngine.activeMicrophoneSource == .appleWatch {
                audioEngine.stopWearableLiveMode()
            } else {
                audioEngine.stopLiveMode()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.startWatchControlledLiveMode(source: requestedSource)
            }
        } else {
            startWatchControlledLiveMode(source: requestedSource)
        }
    }

    private func handleWatchRecordingStop(source: MicrophoneSource?) {
        guard !audioEngine.recording.isRecordingToFile else { return }

        let requestedSource = source ?? selectedMicrophoneSource
        if requestedSource == .appleWatch || audioEngine.activeMicrophoneSource == .appleWatch {
            if audioEngine.activeMicrophoneSource == .appleWatch {
                audioEngine.stopWearableLiveMode()
            }
        } else if audioEngine.engineStatus == .running {
            audioEngine.stopLiveMode()
        }
    }

    private func startWatchControlledLiveMode(source: MicrophoneSource) {
        switch source {
        case .iPhone:
            audioEngine.startLiveMode()
        case .appleWatch:
            audioEngine.startWearableLiveMode()
        }
    }
    
    func updateWatchGain(_ newValue: Float) {
        watchGain = newValue
        watchGainContinuation.yield(newValue)
    }
    
    func addWidget() {
        print("[DashboardViewModel] Add widget button tapped")
        showWidgetPicker = true
    }
    
    func deleteWidget(_ widget: WidgetConfiguration) {
        guard let index = dashboardManager.widgets.firstIndex(where: { $0.id == widget.id }) else { return }
        commitPendingWidgetDelete()
        dashboardManager.removeWidget(id: widget.id)
        let toast = WidgetUndoToast(widget: widget, index: index)
        widgetUndoToast = toast
        widgetUndoTask?.cancel()
        widgetUndoTask = Task { [weak self] in
            try? await Task.sleep(for: Self.widgetUndoWindow)
            await MainActor.run {
                guard let self, self.widgetUndoToast?.id == toast.id else { return }
                self.widgetUndoToast = nil
            }
        }
    }

    func undoWidgetDelete() {
        guard let toast = widgetUndoToast else { return }
        widgetUndoTask?.cancel()
        widgetUndoTask = nil
        dashboardManager.restoreWidget(toast.widget, at: toast.index)
        widgetUndoToast = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func commitPendingWidgetDelete() {
        widgetUndoTask?.cancel()
        widgetUndoTask = nil
        widgetUndoToast = nil
    }
    
    // MARK: - Layout Logic (Testable)
    
    func computeRows(widgets: [WidgetConfiguration], columns: Int) -> [[WidgetConfiguration]] {
        var rows: [[WidgetConfiguration]] = []
        var currentRow: [WidgetConfiguration] = []
        var availableSpace = columns
        
        for widget in widgets {
            let span = getSpan(for: widget, colCount: columns)
            
            if span > availableSpace {
                if !currentRow.isEmpty {
                    rows.append(currentRow)
                    currentRow = []
                    availableSpace = columns
                }
            }
            
            currentRow.append(widget)
            availableSpace -= span
        }
        
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
        
        return rows
    }
    
    func getSpan(for widget: WidgetConfiguration, colCount: Int) -> Int {
        return min(widget.size.columns, colCount)
    }

    private func updateWidgetSpectralWeightingRequirements(for widgets: [WidgetConfiguration]) {
        var required = Set<FrequencyWeighting>()
        var needsBark = false
        for widget in widgets where widgetUsesSpectralWeighting(widget) {
            let useOverrides = WidgetSettings.usesWidgetOverrides(widget.settings)
            if useOverrides {
                let rawWeighting = (widget.settings["freqWeighting"] ?? "Z").uppercased()
                if let weighting = FrequencyWeighting(rawValue: rawWeighting) {
                    required.insert(weighting)
                }
                let bandsRaw = widget.settings["frequencyBands"] ?? WidgetSettings.defaultSpectrumBandMode
                if SpectrumBandMode(settingValue: bandsRaw) == .bark {
                    needsBark = true
                }
            } else {
                // No widget override — uses engine default weighting and default band mode.
                // Default band mode is "terz" (third-octave), never Bark.
            }
        }
        audioEngine.setWidgetSpectralWeightingRequirements(required)
        audioEngine.setWidgetBarkBandsRequired(needsBark)
    }

    private func widgetUsesSpectralWeighting(_ widget: WidgetConfiguration) -> Bool {
        guard widget.displayStyle == .liveWidget else { return false }
        switch widget.type {
        case .spectrogram, .waterfall, .frequencyDisplay, .octaveBands:
            return true
        default:
            return false
        }
    }
}
