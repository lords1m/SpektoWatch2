import SwiftUI

// ============================================================================
// MARK: - RecordingsListView
// ============================================================================

struct RecordingsListView: View {
    @EnvironmentObject private var recordingManager: RecordingManager
    @Environment(\.dismiss) private var dismiss

    // Browsing state
    @State private var searchText: String = ""
    @AppStorage("recordingsList.sortOption") private var sortRawValue: String = SortOption.dateDesc.rawValue
    @State private var editMode: EditMode = .inactive
    @State private var selection: Set<UUID> = []

    // Destructive flows
    @State private var deleteRequest: DeleteRequest?
    @State private var undoToast: UndoToast?
    @State private var undoTask: Task<Void, Never>?

    // Rename flow
    @State private var renameTarget: Recording?
    @State private var renameDraft: String = ""

    private static let undoWindow: Duration = .seconds(5)

    // MARK: - Body

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Aufnahmen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .environment(\.editMode, $editMode)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Suchen"
                )
                .refreshable {
                    recordingManager.reloadRecordings()
                }
                .alert(
                    deleteRequest?.title ?? "",
                    isPresented: Binding(
                        get: { deleteRequest != nil },
                        set: { if !$0 { deleteRequest = nil } }
                    )
                ) {
                    Button("Löschen", role: .destructive) {
                        if let request = deleteRequest {
                            performDelete(request.recordings)
                        }
                    }
                    Button("Abbrechen", role: .cancel) {}
                } message: {
                    Text("Du kannst die Aktion 5 Sekunden lang rückgängig machen.")
                }
                .alert(
                    "Umbenennen",
                    isPresented: Binding(
                        get: { renameTarget != nil },
                        set: { if !$0 { renameTarget = nil } }
                    )
                ) {
                    TextField("Name", text: $renameDraft)
                        .textInputAutocapitalization(.sentences)
                    Button("Abbrechen", role: .cancel) {
                        renameTarget = nil
                    }
                    Button("Speichern") {
                        if let target = renameTarget {
                            recordingManager.renameRecording(id: target.id, to: renameDraft)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        renameTarget = nil
                    }
                } message: {
                    Text("Neuer Name für diese Aufnahme")
                }
                .overlay(alignment: .bottom) {
                    if let toast = undoToast {
                        undoSnackbar(toast)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: undoToast?.id)
                .onDisappear {
                    // Sheet closed mid-window: commit pending deletes so the
                    // files don't linger orphaned in the recordings folder.
                    undoTask?.cancel()
                    undoTask = nil
                    recordingManager.commitPendingSoftDeletes()
                }
                .accessibilityIdentifier("recordingsListView")
        }
    }

    // MARK: - Content branches

    @ViewBuilder
    private var content: some View {
        let recordings = displayedRecordings
        if recordings.isEmpty {
            if searchText.isEmpty {
                ContentUnavailableView(
                    "Keine Aufnahmen",
                    systemImage: "waveform.path",
                    description: Text("Tippe auf den roten Aufnahme-Button im Hauptbildschirm, um eine Messung zu starten.")
                )
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        } else {
            recordingsList(recordings)
        }
    }

    @ViewBuilder
    private func recordingsList(_ recordings: [Recording]) -> some View {
        List(selection: $selection) {
            if usesDateGrouping {
                ForEach(dateGroups(for: recordings), id: \.label) { group in
                    Section(group.label) {
                        ForEach(group.recordings) { recording in
                            recordingRow(recording)
                        }
                    }
                }
            } else {
                ForEach(recordings) { recording in
                    recordingRow(recording)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(GlassBackground())
    }

    // MARK: - Row

    @ViewBuilder
    private func recordingRow(_ recording: Recording) -> some View {
        NavigationLink {
            RecordingDetailView(recording: recording)
        } label: {
            HStack(spacing: 12) {
                LevelChip(level: recording.laeqFast)
                VStack(alignment: .leading, spacing: 3) {
                    Text(recording.name)
                        .font(.body)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(recording.formattedDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("·").foregroundStyle(.tertiary).font(.caption)
                        Text(recording.formattedDuration)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if !recording.tags.isEmpty {
                            Image(systemName: "tag.fill")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if !recording.photoFileNames.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "camera.fill")
                                Text("\(recording.photoFileNames.count)")
                            }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                        if recording.location != nil {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(for: recording))
        }
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                requestDelete(of: [recording])
            } label: {
                Label("Löschen", systemImage: "trash")
            }
            ShareLink(item: recordingManager.url(for: recording)) {
                Label("Teilen", systemImage: "square.and.arrow.up")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading) {
            Button {
                beginRename(recording)
            } label: {
                Label("Umbenennen", systemImage: "pencil")
            }
            .tint(.gray)
        }
        .contextMenu {
            Button {
                beginRename(recording)
            } label: {
                Label("Umbenennen", systemImage: "pencil")
            }
            Button {
                recordingManager.duplicateRecording(recording)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label("Duplizieren", systemImage: "doc.on.doc")
            }
            ShareLink(item: recordingManager.url(for: recording)) {
                Label("Teilen", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(role: .destructive) {
                requestDelete(of: [recording])
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .accessibilityIdentifier("recordingRow-\(recording.id.uuidString)")
        .tag(recording.id)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel("Schließen")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("Sortieren") {
                    Picker("Sortieren", selection: sortBinding) {
                        ForEach(SortOption.allCases) { option in
                            Label(option.displayName, systemImage: option.systemImage)
                                .tag(option)
                        }
                    }
                }
                if !recordingManager.recordings.isEmpty {
                    Divider()
                    Button {
                        withAnimation {
                            editMode = (editMode == .active) ? .inactive : .active
                            if editMode == .inactive { selection.removeAll() }
                        }
                    } label: {
                        if editMode == .active {
                            Label("Fertig", systemImage: "checkmark.circle")
                        } else {
                            Label("Auswählen", systemImage: "checkmark.circle")
                        }
                    }
                }
            } label: {
                Image(systemName: editMode == .active ? "checkmark.circle.fill" : "ellipsis.circle")
                    .font(.title3)
            }
            .accessibilityLabel("Optionen")
        }

        if editMode == .active && !selection.isEmpty {
            ToolbarItem(placement: .bottomBar) {
                Button(role: .destructive) {
                    let toDelete = displayedRecordings.filter { selection.contains($0.id) }
                    requestDelete(of: toDelete)
                } label: {
                    Label("Löschen (\(selection.count))", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .accessibilityIdentifier("bulkDeleteButton")
            }
        }
    }

    // MARK: - Sort / search / grouping

    private var currentSort: SortOption {
        SortOption(rawValue: sortRawValue) ?? .dateDesc
    }

    private var sortBinding: Binding<SortOption> {
        Binding(
            get: { currentSort },
            set: { sortRawValue = $0.rawValue }
        )
    }

    private var usesDateGrouping: Bool {
        searchText.isEmpty && (currentSort == .dateDesc || currentSort == .dateAsc)
    }

    private var displayedRecordings: [Recording] {
        var result = recordingManager.recordings
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { recording in
                if recording.name.lowercased().contains(query) { return true }
                if recording.description.lowercased().contains(query) { return true }
                return recording.tags.contains { $0.lowercased().contains(query) }
            }
        }
        switch currentSort {
        case .dateDesc:
            result.sort { $0.startDate > $1.startDate }
        case .dateAsc:
            result.sort { $0.startDate < $1.startDate }
        case .name:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .levelDesc:
            result.sort { $0.laeqFast > $1.laeqFast }
        case .durationDesc:
            result.sort { $0.duration > $1.duration }
        }
        return result
    }

    private func dateGroups(for recordings: [Recording]) -> [(label: String, recordings: [Recording])] {
        let calendar = Calendar.current
        let now = Date()
        var groups: [(key: Int, label: String, recordings: [Recording])] = []

        for recording in recordings {
            let bucket = dateBucket(for: recording.startDate, now: now, calendar: calendar)
            if let idx = groups.firstIndex(where: { $0.key == bucket.key }) {
                groups[idx].recordings.append(recording)
            } else {
                groups.append((key: bucket.key, label: bucket.label, recordings: [recording]))
            }
        }
        // Stable order: keys ascending (Today=0, Yesterday=1, ThisWeek=2, ThisMonth=3, Older=4)
        // When sorted .dateAsc we still want Today at the bottom; flip ordering in that case.
        if currentSort == .dateAsc {
            groups.sort { $0.key > $1.key }
        } else {
            groups.sort { $0.key < $1.key }
        }
        return groups.map { (label: $0.label, recordings: $0.recordings) }
    }

    private func dateBucket(for date: Date, now: Date, calendar: Calendar) -> (key: Int, label: String) {
        if calendar.isDateInToday(date) { return (0, "Heute") }
        if calendar.isDateInYesterday(date) { return (1, "Gestern") }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date > weekAgo {
            return (2, "Letzte 7 Tage")
        }
        if let monthAgo = calendar.date(byAdding: .month, value: -1, to: now), date > monthAgo {
            return (3, "Letzter Monat")
        }
        return (4, "Älter")
    }

    // MARK: - Destructive flow (delete + undo)

    private func requestDelete(of recordings: [Recording]) {
        guard !recordings.isEmpty else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        deleteRequest = DeleteRequest(recordings: recordings)
    }

    private func performDelete(_ recordings: [Recording]) {
        let ids = Set(recordings.map { $0.id })
        recordingManager.softDeleteRecordings(ids: ids)
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        selection.removeAll()
        if recordingManager.recordings.isEmpty {
            withAnimation { editMode = .inactive }
        }

        // Show undo snackbar and schedule the permanent commit.
        let toast = UndoToast(recordings: recordings)
        undoToast = toast
        undoTask?.cancel()
        undoTask = Task { [weak recordingManager] in
            try? await Task.sleep(for: Self.undoWindow)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                if undoToast?.id == toast.id {
                    undoToast = nil
                }
                recordingManager?.commitPendingSoftDeletes()
            }
        }
    }

    private func undoDelete() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        undoTask?.cancel()
        undoTask = nil
        recordingManager.undoLastSoftDelete()
        undoToast = nil
    }

    // MARK: - Rename flow

    private func beginRename(_ recording: Recording) {
        renameTarget = recording
        renameDraft = recording.name
    }

    // MARK: - Snackbar

    @ViewBuilder
    private func undoSnackbar(_ toast: UndoToast) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(toast.message)
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("Rückgängig") {
                undoDelete()
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .accessibilityIdentifier("undoDeleteToast")
    }

    // MARK: - Accessibility

    private func accessibilityLabel(for recording: Recording) -> String {
        var parts: [String] = [recording.name]
        parts.append("aufgenommen am \(recording.formattedDate)")
        parts.append("Dauer \(recording.formattedDuration)")
        if recording.laeqFast > -119 {
            parts.append("Mittelungspegel \(Int(recording.laeqFast.rounded())) Dezibel A")
        }
        if !recording.tags.isEmpty {
            parts.append("\(recording.tags.count) Tags")
        }
        if !recording.photoFileNames.isEmpty {
            parts.append("\(recording.photoFileNames.count) Fotos")
        }
        if recording.location != nil {
            parts.append("Standort gespeichert")
        }
        return parts.joined(separator: ", ")
    }
}

// ============================================================================
// MARK: - Supporting types
// ============================================================================

private extension RecordingsListView {

    enum SortOption: String, CaseIterable, Identifiable {
        case dateDesc      // Neueste zuerst
        case dateAsc       // Älteste zuerst
        case name          // A → Z
        case levelDesc     // Lautester zuerst
        case durationDesc  // Längster zuerst

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .dateDesc:     return "Neueste zuerst"
            case .dateAsc:      return "Älteste zuerst"
            case .name:         return "Name (A–Z)"
            case .levelDesc:    return "Lautester zuerst"
            case .durationDesc: return "Längster zuerst"
            }
        }

        var systemImage: String {
            switch self {
            case .dateDesc:     return "calendar"
            case .dateAsc:      return "calendar"
            case .name:         return "textformat"
            case .levelDesc:    return "speaker.wave.3.fill"
            case .durationDesc: return "clock"
            }
        }
    }

    struct DeleteRequest: Identifiable {
        let id = UUID()
        let recordings: [Recording]

        var title: String {
            if recordings.count == 1 {
                return "„\(recordings[0].name)\" löschen?"
            }
            return "\(recordings.count) Aufnahmen löschen?"
        }
    }

    struct UndoToast: Identifiable, Equatable {
        let id = UUID()
        let recordings: [Recording]

        var message: String {
            if recordings.count == 1 {
                return "„\(recordings[0].name)\" gelöscht"
            }
            return "\(recordings.count) Aufnahmen gelöscht"
        }

        static func == (lhs: UndoToast, rhs: UndoToast) -> Bool {
            lhs.id == rhs.id
        }
    }
}

// ============================================================================
// MARK: - LevelChip
// ============================================================================

/// Compact color-coded chip showing the recording's mean A-weighted level.
/// Color follows a coarse traffic-light mapping (quiet / moderate / loud /
/// very loud) so the user can scan a list of measurements and spot the
/// hot ones without parsing numbers.
private struct LevelChip: View {
    let level: Float

    private var color: Color {
        switch level {
        case ..<35: return .blue
        case 35..<55: return .green
        case 55..<75: return .yellow
        case 75..<90: return .orange
        default: return .red
        }
    }

    private var displayText: String {
        guard level > -119 else { return "—" }
        return "\(Int(level.rounded()))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(displayText)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("dB(A)")
                .font(.system(size: 8, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(width: 50, height: 40)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.55), lineWidth: 1)
        )
        .foregroundStyle(color)
    }
}
