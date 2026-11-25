import SwiftUI

struct WatchRecordingDetailView: View {
    let recording: WatchRecordingMetadata
    private var store = WatchRecordingStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    // Read the entry live from the store so mutations (e.g. sync-state transitions)
    // reflect while the detail view is open, instead of showing the snapshot that
    // was captured when the NavigationLink was built. Falls back to that snapshot
    // if the entry has since been removed.
    private var current: WatchRecordingMetadata {
        store.recordings.first { $0.id == recording.id } ?? recording
    }

    var body: some View {
        ZStack {
            WatchAppBackground().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    let live = current
                    metric("LAeq", value: live.laeq, unit: "dB")
                    metric("LCpeak", value: live.lcPeak, unit: "dB")
                    row("Dauer", WatchRecordingFormat.duration(live.duration))
                    row("Bewertung", live.weighting)
                    HStack {
                        Text("Synchronisierung")
                            .font(.system(size: 11))
                            .foregroundStyle(.gray)
                        Spacer()
                        WatchSyncStateBadge(state: live.syncState)
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
                .foregroundStyle(.gray)
            Spacer()
            if let v = value {
                Text(v, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Text("–")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Text(unit)
                .font(.system(size: 10))
                .foregroundStyle(.gray)
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}
