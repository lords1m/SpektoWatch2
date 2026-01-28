import SwiftUI
import Combine

class DashboardViewModel: ObservableObject {
    // UI State
    @Published var dashboardManager = DashboardManager()
    @Published var showWidgetPicker = false
    @Published var draggedWidget: WidgetConfiguration?
    @Published var showSettings = false
    
    // Settings State
    @Published var selectedMicrophoneSource: MicrophoneSource = .iPhone
    @Published var sensitivity: Double = 10.0
    @Published var watchGain: Float = 1.0
    @Published var dummyColormap: Int = 0
    @Published var dummyTimeSpan: SpectrogramTimeSpan = .seconds5
    
    // Dependencies
    let audioEngine: AudioEngine
    let connectivityManager: WatchConnectivityManager
    
    init(audioEngine: AudioEngine, connectivityManager: WatchConnectivityManager) {
        self.audioEngine = audioEngine
        self.connectivityManager = connectivityManager
    }
    
    func handleMicrophoneSourceChange(_ newSource: MicrophoneSource) {
        selectedMicrophoneSource = newSource
        connectivityManager.selectedMicrophoneSource = newSource
        connectivityManager.sendMicrophoneSourceSelection(newSource)
        
        if audioEngine.engineStatus == .running {
            audioEngine.stopRecording()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if newSource == .iPhone {
                    self.audioEngine.startRecording()
                } else {
                    self.connectivityManager.requestRecordingStart()
                }
            }
        }
    }
    
    func updateSensitivity(_ newVal: Double) {
        sensitivity = newVal
        audioEngine.setGainBoost(Float(newVal))
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