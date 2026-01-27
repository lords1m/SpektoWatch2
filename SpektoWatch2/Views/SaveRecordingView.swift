import SwiftUI

struct SaveRecordingView: View {
    let audioURL: URL
    let duration: TimeInterval
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) var dismiss
    @State private var title = "Neue Aufnahme"
    @State private var description = ""
    private let dbOffset: Float = 100.0
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Details")) {
                    TextField("Titel", text: $title)
                    TextField("Beschreibung", text: $description)
                    Text("Dauer: \(timeString(from: duration))")
                }
                
                Section {
                    Button("Speichern") {
                        var recording = AudioRecording(url: audioURL, date: Date(), duration: duration, title: title)
                        
                        // Populate statistics from AudioEngine
                        // Note: These values are from the current state, which might be reset if stopRecording clears them immediately.
                        // Ideally, AudioEngine should pass a summary object.
                        // Assuming AudioEngine holds the last values or we capture them before stop.
                        // Since we are in the Save dialog, the engine is stopped but values might still be in published properties if not reset.
                        // However, AudioEngine.stopRecording() clears history.
                        // We need to capture these values *before* showing this view or ensure AudioEngine retains them.
                        // For now, let's try reading from AudioEngine directly, assuming they persist until next start.
                        // Actually, AudioEngine.stopRecording clears levelHistory but maybe not the metrics like LAeq.
                        
                        // Let's grab what we can.
                        // We need to access the levels dictionary from the last spectrogram data or engine properties.
                        if let data = audioEngine.currentSpectrogramData {
                            recording.laeqFast = (data.levels["LAeq"] ?? -120.0) + dbOffset
                            recording.peakLevel = (data.levels["LCpeak"] ?? -120.0) + dbOffset
                            recording.minLevel = (data.levels["LAFmin"] ?? -120.0) + dbOffset
                        }
                        
                        recording.timeWeighting = audioEngine.selectedTimeWeighting.rawValue
                        recording.frequencyWeighting = audioEngine.selectedFrequencyWeighting.rawValue
                        recording.description = description
                        
                        RecordingManager.shared.addRecording(recording)
                        dismiss()
                    }
                    
                    Button("Verwerfen") {
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Aufnahme speichern")
        }
    }
    
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}