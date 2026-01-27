import SwiftUI
import AVFoundation

struct RecordingDetailView: View {
    @Environment(\.dismiss) var dismiss
    let recording: Recording
    
    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var showEditSheet = false
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Card
                    headerCard
                    
                    // Audio Player
                    audioPlayerCard
                    
                    // Statistics
                    statisticsCard
                    
                    // Metadata
                    metadataCard
                    
                    // Description
                    if !recording.description.isEmpty {
                        descriptionCard
                    }
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle(recording.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showShareSheet = true }) {
                            Label("Teilen", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(action: { showEditSheet = true }) {
                            Label("Bearbeiten", systemImage: "pencil")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            let url = RecordingManager.shared.getAudioURL(for: recording)
            audioPlayer.loadAudio(url: url)
        }
        .onDisappear {
            audioPlayer.stop()
        }
    }
    
    // MARK: - Header Card
    
    private var headerCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text(recording.name)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(recording.formattedDate)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Audio Player Card
    
    private var audioPlayerCard: some View {
        VStack(spacing: 16) {
            // Waveform-Symbol (Platzhalter für spätere Waveform-Darstellung)
            Rectangle()
                .fill(Color.blue.opacity(0.1))
                .frame(height: 60)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.largeTitle)
                        .foregroundColor(.blue.opacity(0.3))
                )
                .cornerRadius(8)
            
            // Playback Controls
            HStack(spacing: 20) {
                // Backward Button
                Button(action: { audioPlayer.seek(by: -5) }) {
                    Image(systemName: "gobackward.5")
                        .font(.title2)
                }
                .disabled(!audioPlayer.isLoaded)
                
                // Play/Pause Button
                Button(action: {
                    if audioPlayer.isPlaying {
                        audioPlayer.pause()
                    } else {
                        audioPlayer.play()
                    }
                }) {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                }
                .disabled(!audioPlayer.isLoaded)
                
                // Forward Button
                Button(action: { audioPlayer.seek(by: 5) }) {
                    Image(systemName: "goforward.5")
                        .font(.title2)
                }
                .disabled(!audioPlayer.isLoaded)
            }
            .foregroundColor(.blue)
            
            // Progress Bar
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { audioPlayer.currentTime },
                        set: { audioPlayer.seek(to: $0) }
                    ),
                    in: 0...max(audioPlayer.duration, 0.1)
                )
                .disabled(!audioPlayer.isLoaded)
                
                HStack {
                    Text(formatTime(audioPlayer.currentTime))
                        .font(.caption)
                        .monospacedDigit()
                    Spacer()
                    Text(formatTime(audioPlayer.duration))
                        .font(.caption)
                        .monospacedDigit()
                }
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Statistics Card
    
    private var statisticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistik")
                .font(.headline)
            
            Divider()
            
            StatRow(icon: "waveform.path", title: "LA eq,Fast", value: String(format: "%.1f dB", recording.laeqFast))
            StatRow(icon: "arrow.up.circle", title: "Maximum", value: String(format: "%.1f dB", recording.peakLevel))
            StatRow(icon: "arrow.down.circle", title: "Minimum", value: String(format: "%.1f dB", recording.minLevel))
            StatRow(icon: "clock", title: "Dauer", value: recording.formattedDuration)
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Metadata Card
    
    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Konfiguration")
                .font(.headline)
            
            Divider()
            
            StatRow(icon: "gauge", title: "Zeitbewertung", value: recording.timeWeighting)
            StatRow(icon: "slider.horizontal.3", title: "Frequenzbewertung", value: recording.frequencyWeighting)
            StatRow(icon: "music.note", title: "Samplerate", value: "\(Int(recording.sampleRate)) Hz")
            StatRow(icon: "speaker.wave.2", title: "Kanäle", value: "\(recording.channelCount)")
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Description Card
    
    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Beschreibung")
                .font(.headline)
            
            Divider()
            
            Text(recording.description)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Functions
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Stat Row

struct StatRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - Audio Player Manager

class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var isLoaded = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    
    private var audioPlayer: AVAudioPlayer?
    private var updateTimer: Timer?
    
    func loadAudio(url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            isLoaded = true
            print("[AudioPlayerManager] Audio loaded: \(url.lastPathComponent)")
        } catch {
            print("[AudioPlayerManager] ERROR loading audio: \(error.localizedDescription)")
        }
    }
    
    func play() {
        audioPlayer?.play()
        isPlaying = true
        startTimer()
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentTime = 0
        stopTimer()
    }
    
    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }
    
    func seek(by offset: TimeInterval) {
        let newTime = (audioPlayer?.currentTime ?? 0) + offset
        seek(to: max(0, min(newTime, duration)))
    }
    
    private func startTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.currentTime = self?.audioPlayer?.currentTime ?? 0
        }
    }
    
    private func stopTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    // AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = 0
        stopTimer()
    }
}
