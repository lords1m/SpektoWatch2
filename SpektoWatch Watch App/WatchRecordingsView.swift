import SwiftUI

/// Browse and manage standalone watch recordings. Backed by the durable catalog
/// in `WatchRecordingStore` ([[task-3-local-store]]). List → detail → delete.
struct WatchRecordingsView: View {
    private var store = WatchRecordingStore.shared

    var body: some View {
        ZStack {
            WatchAppBackground().ignoresSafeArea()

            if store.recordings.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(store.recordings) { recording in
                        NavigationLink {
                            WatchRecordingDetailView(recording: recording)
                        } label: {
                            WatchRecordingRow(recording: recording)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.carousel)
            }
        }
        .navigationTitle("Aufnahmen")
        .accessibilityIdentifier("watchRecordingsView")
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Keine Aufnahmen",
            systemImage: "waveform",
            description: Text("Standalone-Aufnahmen erscheinen hier.")
        )
        .accessibilityIdentifier("watchRecordingsEmpty")
    }
}

