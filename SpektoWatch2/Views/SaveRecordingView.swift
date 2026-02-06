import SwiftUI

struct SaveRecordingView: View {
    let audioURL: URL
    let duration: TimeInterval
    @ObservedObject var audioEngine: AudioEngine
    @EnvironmentObject var recordingManager: RecordingManager
    @Environment(\.dismiss) var dismiss
    @State private var title = "Neue Aufnahme"
    @State private var description = ""
    // AudioEngine liefert bereits kalibrierte dB SPL Werte
    private let dbOffset: Float = 0.0
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Details")) {
                    TextField("Titel", text: $title)
                    TextField("Beschreibung", text: $description)
                    Text("Dauer: \(timeString(from: duration))")
                }
                
                Section(header: Text("Statistiken")) {
                    if let data = audioEngine.currentSpectrogramData {
                        HStack {
                            Text("LAeq")
                            Spacer()
                            Text(String(format: "%.1f dB", (data.levels["LAeq"] ?? -120.0) + dbOffset))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Peak")
                            Spacer()
                            Text(String(format: "%.1f dB", (data.levels["LCpeak"] ?? -120.0) + dbOffset))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Min")
                            Spacer()
                            Text(String(format: "%.1f dB", (data.levels["LAFmin"] ?? -120.0) + dbOffset))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Zeitbewertung")
                        Spacer()
                        Text(audioEngine.timeWeighting.displayName)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Frequenzbewertung")
                        Spacer()
                        Text(audioEngine.frequencyWeighting.displayName)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button("Speichern") {
                        var recording = AudioRecording(
                            url: audioURL,
                            date: Date(),
                            duration: duration,
                            title: title
                        )
                        
                        // Populate statistics from AudioEngine
                        if let data = audioEngine.currentSpectrogramData {
                            recording.laeqFast = (data.levels["LAeq"] ?? -120.0) + dbOffset
                            recording.peakLevel = (data.levels["LCpeak"] ?? -120.0) + dbOffset
                            recording.minLevel = (data.levels["LAFmin"] ?? -120.0) + dbOffset
                        }
                        
                        recording.timeWeighting = audioEngine.timeWeighting.rawValue
                        recording.frequencyWeighting = audioEngine.frequencyWeighting.rawValue
                        recording.description = description
                        
                        recordingManager.addRecording(recording)
                        dismiss()
                    }
                    .font(.headline)
                    
                    Button("Verwerfen", role: .destructive) {
                        // Optional: Delete the temporary audio file
                        try? FileManager.default.removeItem(at: audioURL)
                        dismiss()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlassBackground())
            .navigationTitle("Aufnahme speichern")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
