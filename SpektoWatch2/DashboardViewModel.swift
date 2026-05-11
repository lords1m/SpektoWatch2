import SwiftUI
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    // UI State
    @Published var dashboardManager = DashboardManager()
    @Published var showWidgetPicker = false
    @Published var draggedWidget: WidgetConfiguration?
    @Published var showSettings = false

    // Settings State
    @Published var selectedMicrophoneSource: MicrophoneSource = .iPhone
    @Published var watchGain: Float = 1.0
    @Published var showWatchNotReachableAlert = false

    // Dependencies
    let audioEngine: AudioEngine
    let connectivityManager: WatchConnectivityManager

    private var cancellables = Set<AnyCancellable>()

    init(audioEngine: AudioEngine, connectivityManager: WatchConnectivityManager) {
        self.audioEngine = audioEngine
        self.connectivityManager = connectivityManager

        // Forward DashboardManager changes to trigger view updates
        dashboardManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        dashboardManager.$widgets
            .sink { [weak self] widgets in
                self?.updateWidgetSpectralWeightingRequirements(for: widgets)
            }
            .store(in: &cancellables)
        updateWidgetSpectralWeightingRequirements(for: dashboardManager.widgets)

        // Auto-Fallback: Watch bricht Verbindung während Aufnahme ab
        connectivityManager.$isReachable
            .dropFirst()
            .filter { !$0 }
            .sink { [weak self] _ in
                guard let self else { return }
                if self.selectedMicrophoneSource == .appleWatch && self.audioEngine.engineStatus == .running {
                    _ = self.applyMicrophoneSourceSelection(.iPhone, notifyWatch: true)
                    self.restartActiveMeasurementForSelectedSource(.iPhone)
                }
            }
            .store(in: &cancellables)

        connectivityManager.$selectedMicrophoneSource
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in
                guard let self, self.selectedMicrophoneSource != source else { return }
                _ = self.applyMicrophoneSourceSelection(source, notifyWatch: false)
            }
            .store(in: &cancellables)

        connectivityManager.$spectrogramData
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                guard let self, self.selectedMicrophoneSource == .appleWatch else { return }
                if self.audioEngine.engineStatus != .running {
                    self.audioEngine.startWearableLiveMode()
                }
                self.audioEngine.ingestWearableSpectrogramData(data)
            }
            .store(in: &cancellables)

        // Start/Stop-Befehle von der Apple Watch empfangen
        NotificationCenter.default.publisher(for: .startRecordingCommand)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleWatchRecordingStart(source: notification.object as? MicrophoneSource)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .stopRecordingCommand)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleWatchRecordingStop(source: notification.object as? MicrophoneSource)
            }
            .store(in: &cancellables)

    }
    
    func handleMicrophoneSourceChange(_ newSource: MicrophoneSource) {
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
        let wasRecordingToFile = audioEngine.isRecordingToFile

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
        guard !audioEngine.isRecordingToFile else { return }

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
        guard !audioEngine.isRecordingToFile else { return }

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
        connectivityManager.sendGainValue(newValue)
    }
    
    func addWidget() {
        print("[DashboardViewModel] Add widget button tapped")
        showWidgetPicker = true
    }
    
    func deleteWidget(_ widget: WidgetConfiguration) {
        print("[DashboardViewModel] Delete requested for widget: \(widget.id)")
        dashboardManager.removeWidget(id: widget.id)
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
        for widget in widgets where widgetUsesSpectralWeighting(widget) {
            guard WidgetSettings.usesWidgetOverrides(widget.settings) else { continue }
            let rawWeighting = (widget.settings["freqWeighting"] ?? "Z").uppercased()
            if let weighting = FrequencyWeighting(rawValue: rawWeighting) {
                required.insert(weighting)
            }
        }
        audioEngine.setWidgetSpectralWeightingRequirements(required)
    }

    private func widgetUsesSpectralWeighting(_ widget: WidgetConfiguration) -> Bool {
        switch widget.type {
        case .spectrogram, .waterfall, .frequencyDisplay, .octaveBands:
            return true
        default:
            return false
        }
    }
}
