import SwiftUI

enum SpectrogramTimeSpan: Int, CaseIterable, Identifiable {
    case seconds1 = 1
    case seconds5 = 5
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .seconds1: return "1 Sekunde"
        case .seconds5: return "5 Sekunden"
        }
    }
}

struct SpectrogramView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @State private var isRecording = false
    @State private var selectedMicrophoneSource: MicrophoneSource = .iPhone
    @State private var lastUpdateTime: Date = .distantPast
    @State private var sensitivity: Double = 10.0 // Standard-Sensitivität (dB)
    @State private var selectedColormap: Int = 0  // 0=Turbo, 1=Jet, 2=Viridis
    @State private var showSettings = false
    @State private var timeWeighting: TimeWeighting = .fast
        @State private var frequencyWeighting: FrequencyWeighting = .a
        @State private var timeSpan: SpectrogramTimeSpan = .seconds5
        @State private var watchGain: Float = 1.0
        
        @State private var isPaused = false
        @State private var scrollOffset: Double = 0.0
        @State private var pausedDuration: TimeInterval = 0.0
        
        let maxFrames = 1200  // Genug Frames für >10s bei 86 FPS
        let updateThrottleInterval: TimeInterval = 1.0 / 120.0 // Max 120 FPS (ProMotion)
        
        var body: some View {
            VStack(spacing: 0) {
                headerView
                
                spectrogramContainer
                
                connectivityStatusView
                
                if isPaused {
                    pausedControlsView
                }
                
                mainControlsView
            }
            .sheet(isPresented: $showSettings) {
                SpectrogramSettingsView(
                    selectedMicrophoneSource: $selectedMicrophoneSource,
                    selectedColormap: $selectedColormap,
                    sensitivity: $sensitivity,
                    timeWeighting: $timeWeighting,
                    frequencyWeighting: $frequencyWeighting,
                    timeSpan: $timeSpan,
                    scrollSpeed: $audioEngine.scrollSpeed,
                    watchGain: $watchGain
                )
            }
            .onChange(of: selectedMicrophoneSource) { _, newSource in
                handleMicrophoneSourceChange(newSource)
            }
            .onChange(of: sensitivity) { _, newVal in
                audioEngine.setGainBoost(Float(newVal))
            }
            .onChange(of: timeWeighting) { _, newVal in
                audioEngine.setTimeWeighting(newVal)
            }
            .onChange(of: frequencyWeighting) { _, newVal in
                audioEngine.setFrequencyWeighting(newVal)
            }
            .onChange(of: watchGain) { _, newValue in
                WatchConnectivityManager.shared.sendGainValue(newValue)
            }
            .onReceive(connectivityManager.$spectrogramData) { data in
                // Fallback: Falls die Watch doch mal fertige Spektrogramm-Daten sendet
                if let data = data, selectedMicrophoneSource == .appleWatch {
                    audioEngine.currentSpectrogramData = data
                }
            }        .onReceive(connectivityManager.$audioData) { data in
            // Hauptweg: Watch sendet Audio, iPhone berechnet FFT
            if let data = data, selectedMicrophoneSource == .appleWatch {
                audioEngine.processExternalAudio(data.samples)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startRecordingCommand)) { _ in
            if !isRecording {
                toggleRecording()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopRecordingCommand)) { _ in
            if isRecording {
                toggleRecording()
            }
        }
        .onAppear {
            // Set initial gain boost
            audioEngine.setGainBoost(Float(sensitivity))
            audioEngine.setTimeWeighting(timeWeighting)
            audioEngine.setFrequencyWeighting(frequencyWeighting)
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("Live Spektrogramm")
                .font(.title)
                .bold()
            Spacer()
            Button(action: { showSettings = true }) {
                Image(systemName: "gear")
                    .font(.title2)
            }
        }
        .padding()
    }
    
    private var spectrogramContainer: some View {
        GeometryReader { geo in
            NavigationView {
                ModularDashboardView(audioEngine: audioEngine)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if isPaused {
                                    // Dragging right (positive) moves view back in history
                                    let delta = Double(value.translation.width / geo.size.width)
                                    scrollOffset -= delta * 0.05 // Sensitivity factor
                                    
                                    // Clamp scroll offset
                                    let span = Double(timeSpan.rawValue)
                                    let duration = isPaused ? pausedDuration : audioEngine.recordingDuration
                                    let minOffset = -min(1.0, duration / span)
                                    scrollOffset = max(minOffset, min(0.0, scrollOffset))
                                }
                            }
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
        .padding(.top, 8)
    }
    
    private var connectivityStatusView: some View {
        HStack {
            Image(systemName: connectivityManager.isReachable ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(connectivityManager.isReachable ? .green : .red)
            Text(connectivityManager.isReachable ? "Watch verbunden" : "Watch nicht verbunden")
                .foregroundColor(connectivityManager.isReachable ? .green : .red)
                .font(.caption)
        }
        .padding(.vertical, 8)
    }
    
    private var pausedControlsView: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(
                get: {
                    let duration = pausedDuration
                    let span = Double(timeSpan.rawValue)
                    // Time = duration + scrollOffset * span (scrollOffset is negative)
                    return duration + scrollOffset * span
                },
                set: { newTime in
                    let duration = pausedDuration
                    let span = Double(timeSpan.rawValue)
                    // Offset = (Time - duration) / span
                    scrollOffset = (newTime - duration) / span
                }
            ), in: max(0, pausedDuration - Double(timeSpan.rawValue))...pausedDuration)
            
            Text("Zeit: \(String(format: "%.1f", pausedDuration + scrollOffset * Double(timeSpan.rawValue)))s / \(String(format: "%.1f", pausedDuration))s")
                .font(.caption)
                .monospacedDigit()
        }
        .padding(.horizontal, 40)
    }
    
    private var mainControlsView: some View {
        HStack(spacing: 20) {
            Button(action: toggleRecording) {
                HStack {
                    Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.title2)
                    Text(isRecording ? "Stop" : "Start")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(width: 140, height: 50)
                .background(isRecording ? Color.red : Color.green)
                .cornerRadius(25)
            }
            
            Button(action: {
                isPaused.toggle()
                if isPaused {
                    pausedDuration = audioEngine.recordingDuration
                }
                scrollOffset = 0.0 // Reset scroll on toggle
            }) {
                HStack {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.title2)
                }
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(Color.gray)
                .cornerRadius(25)
            }
        }
        .padding(.bottom)
    }
    
    private func handleMicrophoneSourceChange(_ newSource: MicrophoneSource) {
        connectivityManager.selectedMicrophoneSource = newSource
        connectivityManager.sendMicrophoneSourceSelection(newSource)
        
        if isRecording {
            audioEngine.stopRecording()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if newSource == .iPhone {
                    audioEngine.startRecording()
                } else {
                    connectivityManager.requestRecordingStart()
                }
            }
        }
    }
    
    private func toggleRecording() {
        isRecording.toggle()
        
        if isRecording {
            if selectedMicrophoneSource == .iPhone {
                audioEngine.startRecording()
            } else {
                connectivityManager.requestRecordingStart()
            }
        } else {
            if selectedMicrophoneSource == .iPhone {
                audioEngine.stopRecording()
            } else {
                connectivityManager.requestRecordingStop()
            }
        }
    }
}
