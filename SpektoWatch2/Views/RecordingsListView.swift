import SwiftUI

struct RecordingsListView: View {
    @EnvironmentObject private var recordingManager: RecordingManager
    @Environment(\.dismiss) var dismiss
    
    @State private var showDeleteConfirmation = false
    @State private var indexSetToDelete: IndexSet?
    
    var body: some View {
        NavigationView {
            List {
                if recordingManager.recordings.isEmpty {
                    Text("Keine Aufnahmen")
                        .foregroundColor(.gray)
                        .listRowBackground(Rectangle().fill(.ultraThinMaterial))
                } else {
                    ForEach(recordingManager.recordings) { recording in
                        NavigationLink(destination: RecordingDetailView(recording: recording)) {
                            VStack(alignment: .leading) {
                                Text(recording.title)
                                    .font(.headline)
                                Text(timeString(from: recording.duration))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .listRowBackground(Rectangle().fill(.ultraThinMaterial))
                    }
                    .onDelete { indexSet in
                        indexSetToDelete = indexSet
                        showDeleteConfirmation = true
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlassBackground())
            .navigationTitle("Aufnahmen")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
            .alert("Aufnahme löschen?", isPresented: $showDeleteConfirmation) {
                Button("Löschen", role: .destructive) {
                    if let indexSet = indexSetToDelete {
                        recordingManager.deleteRecording(at: indexSet)
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Diese Aktion kann nicht rückgängig gemacht werden.")
            }
        }
    }
    
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
