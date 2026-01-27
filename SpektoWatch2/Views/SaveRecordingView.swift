import SwiftUI

struct SaveRecordingView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var recordingManager = RecordingManager.shared
    
    let audioURL: URL
    let duration: TimeInterval
    let audioEngine: AudioEngine
    
    @State private var recordingName: String = ""
    @State private var recordingDescription: String = ""
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        NavigationView {
            Form {
                // Statistik-Übersicht
                Section(header: Text("Messung")) {
                    HStack {
                        Image(systemName: "clock")
                        Text("Dauer")
                        Spacer()
                        Text(formatDuration(duration))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    
                    let stats = audioEngine.getRecordingStatistics()
                    
                    HStack {
                        Image(systemName: "waveform")
                        Text("LA eq,Fast")
                        Spacer()
                        Text(String(format: "%.1f dB", stats.laeqFast))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    
                    HStack {
                        Image(systemName: "arrow.up.circle")
                        Text("Maximum")
                        Spacer()
                        Text(String(format: "%.1f dB", stats.peak))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    
                    HStack {
                        Image(systemName: "arrow.down.circle")
                        Text("Minimum")
                        Spacer()
                        Text(String(format: "%.1f dB", stats.min))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                
                // Metadaten
                Section(header: Text("Dokumentation")) {
                    TextField("Name der Messung", text: $recordingName)
                        .autocapitalization(.words)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Beschreibung")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $recordingDescription)
                            .frame(height: 100)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .padding(.vertical, 4)
                }
                
                // Mess-Konfiguration
                Section(header: Text("Konfiguration")) {
                    HStack {
                        Image(systemName: "gauge")
                        Text("Zeitbewertung")
                        Spacer()
                        Text(audioEngine.timeWeighting.displayName)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text("Frequenzbewertung")
                        Spacer()
                        Text(audioEngine.frequencyWeighting.rawValue)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Messung speichern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Verwerfen") {
                        showDeleteConfirmation = true
                    }
                    .foregroundColor(.red)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        saveRecording()
                    }
                    .fontWeight(.bold)
                }
            }
            .alert("Messung verwerfen?", isPresented: $showDeleteConfirmation) {
                Button("Verwerfen", role: .destructive) {
                    deleteRecording()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Die Aufnahme wird unwiderruflich gelöscht.")
            }
        }
        .onAppear {
            // Default-Name mit Datum
            let formatter = DateFormatter()
            formatter.dateFormat = "dd.MM.yyyy HH:mm"
            recordingName = "Messung \(formatter.string(from: Date()))"
        }
    }
    
    private func saveRecording() {
        recordingManager.saveRecording(
            audioURL: audioURL,
            name: recordingName,
            description: recordingDescription,
            audioEngine: audioEngine
        )
        dismiss()
    }
    
    private func deleteRecording() {
        // Lösche temporäre Audio-Datei
        try? FileManager.default.removeItem(at: audioURL)
        dismiss()
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
