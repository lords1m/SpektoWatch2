import SwiftUI

/// Browse and manage standalone watch recordings. Backed by the durable catalog
/// in `WatchRecordingStore` ([[task-3-local-store]]). List → detail → delete.
struct WatchRecordingsView: View {
    @ObservedObject private var store = WatchRecordingStore.shared

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
        VStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(WatchStylePalette.accentBlue)
            Text("Keine Aufnahmen")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Text("Standalone-Aufnahmen erscheinen hier.")
                .font(.system(size: 10))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityIdentifier("watchRecordingsEmpty")
    }
}

/// Small colored glyph that communicates how far a recording has reached the
/// phone. Drives off `WatchRecordingSyncState` ([[task-5-sync-back]]).
struct WatchSyncStateBadge: View {
    let state: WatchRecordingSyncState

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .accessibilityLabel(label)
    }

    private var symbol: String {
        switch state {
        case .local: return "arrow.up.circle"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .local: return .gray
        case .syncing: return WatchStylePalette.accentBlue
        case .synced: return .green
        }
    }

    private var label: String {
        switch state {
        case .local: return "Nicht synchronisiert"
        case .syncing: return "Synchronisiert gerade"
        case .synced: return "Synchronisiert"
        }
    }
}

private struct WatchRecordingRow: View {
    let recording: WatchRecordingMetadata

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(WatchRecordingFormat.subtitle(for: recording))
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            Spacer()
            WatchSyncStateBadge(state: recording.syncState)
        }
        .padding(.vertical, 2)
    }
}

struct WatchRecordingDetailView: View {
    let recording: WatchRecordingMetadata
    @ObservedObject private var store = WatchRecordingStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            WatchAppBackground().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    metric("LAeq", value: recording.laeq, unit: "dB")
                    metric("LCpeak", value: recording.lcPeak, unit: "dB")
                    row("Dauer", WatchRecordingFormat.duration(recording.duration))
                    row("Bewertung", recording.weighting)
                    HStack {
                        Text("Sync")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        Spacer()
                        WatchSyncStateBadge(state: recording.syncState)
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Löschen", systemImage: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 4)
                    .accessibilityIdentifier("watchRecordingDelete")
                }
                .padding(10)
                .watchGlassCard(cornerRadius: 12)
                .padding(6)
            }
        }
        .navigationTitle(recording.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Aufnahme löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                store.delete(recording)
                WKInterfaceDevice.current().play(.success)
                dismiss()
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func metric(_ name: String, value: Float?, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
                .font(.system(size: 11))
                .foregroundColor(.gray)
            Spacer()
            Text(value.map { String(format: "%.1f", $0) } ?? "–")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(unit)
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 11))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
        }
    }
}

enum WatchRecordingFormat {
    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func subtitle(for recording: WatchRecordingMetadata) -> String {
        "\(duration(recording.duration)) · \(timestamp(recording.createdAt))"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM. HH:mm"
        return f
    }()

    static func timestamp(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}
