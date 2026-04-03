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

        // Auto-Fallback: Watch bricht Verbindung während Aufnahme ab
        connectivityManager.$isReachable
            .dropFirst()
            .filter { !$0 }
            .sink { [weak self] _ in
                guard let self else { return }
                if self.selectedMicrophoneSource == .appleWatch && self.audioEngine.engineStatus == .running {
                    self.selectedMicrophoneSource = .iPhone
                    // onChange in ModularDashboardView triggert handleMicrophoneSourceChange(.iPhone)
                }
            }
            .store(in: &cancellables)

        // Start/Stop-Befehle von der Apple Watch empfangen
        NotificationCenter.default.publisher(for: .startRecordingCommand)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.audioEngine.engineStatus != .running else { return }
                if self.selectedMicrophoneSource == .iPhone {
                    self.audioEngine.startRecording()
                }
                // .appleWatch: Audio kommt via connectivityManager.$audioData unten
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .stopRecordingCommand)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.audioEngine.engineStatus == .running else { return }
                self.audioEngine.stopRecording()
            }
            .store(in: &cancellables)

        // Watch-Audiodaten verarbeiten wenn Watch als Quelle ausgewählt ist
        connectivityManager.$audioData
            .compactMap { $0 }
            .sink { [weak self] data in
                guard let self, self.selectedMicrophoneSource == .appleWatch else { return }
                self.audioEngine.processExternalAudio(data.samples, sampleRate: data.sampleRate)
            }
            .store(in: &cancellables)
    }
    
    func handleMicrophoneSourceChange(_ newSource: MicrophoneSource) {
        if newSource == .appleWatch && !connectivityManager.isReachable {
            selectedMicrophoneSource = .iPhone
            showWatchNotReachableAlert = true
            return
        }

        selectedMicrophoneSource = newSource
        connectivityManager.selectedMicrophoneSource = newSource
        connectivityManager.sendMicrophoneSourceSelection(newSource)

        if audioEngine.engineStatus == .running {
            audioEngine.stopRecording()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                if newSource == .iPhone {
                    self.audioEngine.startRecording()
                } else {
                    self.connectivityManager.requestRecordingStart()
                }
            }
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
}