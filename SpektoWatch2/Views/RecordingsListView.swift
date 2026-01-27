import SwiftUI

struct RecordingsListView: View {
    @StateObject private var recordingManager = RecordingManager.shared
    @State private var selectedRecording: Recording?
    @State private var showingDetail = false
    
    var body: some View {
        NavigationView {
            Group {
                if recordingManager.recordings.isEmpty {
                    emptyStateView
                } else {
                    recordingsList
                }
            }
            .navigationTitle("Messungen")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    storageInfoButton
                }
            }
        }
        .sheet(item: $selectedRecording) { recording in
            RecordingDetailView(recording: recording)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 80))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("Keine Messungen")
                .font(.title2)
                .foregroundColor(.gray)
            
            Text("Starten Sie eine Aufnahme im Dashboard")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    // MARK: - Recordings List
    
    private var recordingsList: some View {
        List {
            ForEach(recordingManager.recordings) { recording in
                RecordingRowView(recording: recording)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedRecording = recording
                    }
            }
            .onDelete(perform: deleteRecordings)
        }
        .listStyle(.insetGrouped)
    }
    
    // MARK: - Storage Info Button
    
    private var storageInfoButton: some View {
        Menu {
            Section {
                Text("\(recordingManager.recordings.count) Messungen")
                Text("Speicher: \(recordingManager.getTotalStorageSize())")
            }
        } label: {
            Image(systemName: "info.circle")
        }
    }
    
    // MARK: - Actions
    
    private func deleteRecordings(at offsets: IndexSet) {
        for index in offsets {
            let recording = recordingManager.recordings[index]
            recordingManager.deleteRecording(recording)
        }
    }
}

// MARK: - Recording Row View

struct RecordingRowView: View {
    let recording: Recording
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.blue)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.name)
                        .font(.headline)
                    
                    Text(recording.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            // Stats
            HStack(spacing: 16) {
                StatBadge(
                    icon: "clock",
                    value: recording.formattedDuration,
                    color: .blue
                )
                
                StatBadge(
                    icon: "waveform.path",
                    value: String(format: "%.1f dB", recording.laeqFast),
                    color: .green
                )
                
                StatBadge(
                    icon: "arrow.up",
                    value: String(format: "%.1f dB", recording.peakLevel),
                    color: .orange
                )
            }
            
            // Description (if available)
            if !recording.description.isEmpty {
                Text(recording.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            // Tags
            if !recording.tags.isEmpty {
                HStack {
                    ForEach(recording.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(value)
                .font(.caption)
                .monospacedDigit()
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Preview

struct RecordingsListView_Previews: PreviewProvider {
    static var previews: some View {
        RecordingsListView()
    }
}
