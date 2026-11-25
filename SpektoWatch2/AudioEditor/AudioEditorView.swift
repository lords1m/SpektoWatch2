import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

enum AudioEditorSource: Identifiable {
    case recording(Recording)
    case externalFile(URL)

    var id: String {
        switch self {
        case .recording(let rec):   return "rec-\(rec.id.uuidString)"
        case .externalFile(let url): return "file-\(url.standardizedFileURL.path)"
        }
    }

    var displayTitle: String {
        switch self {
        case .recording(let rec):    return rec.name
        case .externalFile(let url): return url.deletingPathExtension().lastPathComponent
        }
    }

    @MainActor
    func fileURL(using recordingManager: RecordingManager) -> URL {
        switch self {
        case .recording(let rec):    return recordingManager.url(for: rec)
        case .externalFile(let url): return url
        }
    }
}

struct AudioEditorView: View {
    let source: AudioEditorSource
    var onRecordingReplaced: (Recording) -> Void = { _ in }

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.designAccent) private var accent

    @State private var engine = AudioEditorEngine()
    @State private var history = AudioEditHistory(sourceDuration: 0)
    @State private var waveform: WaveformData?
    @State private var isLoadingWaveform = true
    @State private var loadError: String?

    @State private var activeTab: AudioEditorToolTab = .time
    @State private var selectionMode: WaveformSelectionMode = .trim
    @State private var zoomScale: CGFloat = 1.0
    @State private var scrollOffsetRatio: CGFloat = 0.0
    @State private var selectionStart: TimeInterval = 0
    @State private var selectionEnd: TimeInterval = 0

    @State private var showExportSheet = false
    @State private var showDiscardAlert = false
    @State private var waveformTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let loadError {
                        ContentUnavailableView(
                            "Audio nicht ladbar",
                            systemImage: "exclamationmark.triangle",
                            description: Text(loadError)
                        )
                    } else if let waveform {
                        waveformSection(waveform: waveform)

                        AudioEditorTransportBar(
                            engine: engine,
                            selectionDuration: max(0, selectionEnd - selectionStart)
                        )

                        Picker("Werkzeug", selection: $activeTab) {
                            ForEach(AudioEditorToolTab.allCases) { tab in
                                Label(tab.rawValue, systemImage: tab.symbol).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)

                        toolPanel
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Wellenform wird analysiert…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(GlassBackground().ignoresSafeArea())
            .navigationTitle(source.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        if history.current.hasChanges {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        history.undo()
                        syncEngineAndSelectionAfterRecipeChange()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!history.canUndo)
                    .accessibilityLabel("Rückgängig")

                    Button {
                        history.redo()
                        syncEngineAndSelectionAfterRecipeChange()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!history.canRedo)
                    .accessibilityLabel("Wiederholen")

                    Button("Export") {
                        engine.pause()
                        showExportSheet = true
                    }
                    .fontWeight(.semibold)
                    .disabled(waveform == nil)
                    .accessibilityIdentifier("audioEditorExportButton")
                }
            }
            .sheet(isPresented: $showExportSheet) {
                AudioExportSheet(
                    source: source,
                    recipe: history.current,
                    sourceSampleRate: waveform?.sampleRate ?? 44100,
                    sourceChannels: waveform?.channelCount ?? 1,
                    onFinishedReplacingOriginal: onRecordingReplaced
                )
                .environment(services)
                .polishedSheetChrome()
            }
            .alert("Änderungen verwerfen?", isPresented: $showDiscardAlert) {
                Button("Weiter bearbeiten", role: .cancel) {}
                Button("Verwerfen", role: .destructive) { dismiss() }
            } message: {
                Text("Ungespeicherte Bearbeitungen gehen verloren.")
            }
        }
        .accessibilityIdentifier("audioEditorView")
        .onAppear {
            engine.suspendLiveCaptureIfNeeded(audioEngine: services.audioEngine)
            startLoading()
        }
        .onDisappear {
            waveformTask?.cancel()
            waveformTask = nil
            engine.restoreLiveCaptureIfNeeded()
        }
        .onChange(of: selectionStart) { _, _ in
            engine.loopRange = AudioTimeRange(start: selectionStart, end: selectionEnd)
        }
        .onChange(of: selectionEnd) { _, _ in
            engine.loopRange = AudioTimeRange(start: selectionStart, end: selectionEnd)
        }
    }

    @ViewBuilder
    private func waveformSection(waveform: WaveformData) -> some View {
        let effectiveDur = max(0.05, history.current.effectiveDuration)
        let visWindow = visibleWindow(duration: effectiveDur)
        let displayedBins = activeWaveformBins(from: waveform)

        VStack(spacing: 8) {
            WaveformOverviewMinimap(
                bins: displayedBins,
                totalDuration: effectiveDur,
                currentTime: engine.currentTime,
                visibleStart: visWindow.start,
                visibleEnd: visWindow.end,
                selectionStart: selectionStart,
                selectionEnd: selectionEnd,
                selectionMode: selectionMode,
                onScrub: { time in
                    engine.seek(to: time)
                }
            )

            WaveformDetailCanvas(
                bins: displayedBins,
                totalDuration: effectiveDur,
                currentTime: engine.currentTime,
                zoomScale: $zoomScale,
                scrollOffsetRatio: $scrollOffsetRatio,
                selectionStart: $selectionStart,
                selectionEnd: $selectionEnd,
                selectionMode: selectionMode,
                onBeginScrub: { engine.beginScrubbing() },
                onScrub: { engine.seek(to: $0) },
                onEndScrub: { engine.endScrubbing() }
            )
        }
    }

    @ViewBuilder
    private var toolPanel: some View {
        switch activeTab {
        case .time:
            TimeEditPanel(
                selectionMode: $selectionMode,
                selectionStart: selectionStart,
                selectionEnd: selectionEnd,
                recipe: history.current,
                onTrim: {
                    let next = history.current.applyingTrim(editedStart: selectionStart, editedEnd: selectionEnd)
                    history.apply(next)
                    syncEngineAndSelectionAfterRecipeChange()
                },
                onCut: {
                    let next = history.current.applyingCut(editedStart: selectionStart, editedEnd: selectionEnd)
                    history.apply(next)
                    syncEngineAndSelectionAfterRecipeChange()
                },
                onUpdateRecipe: { updated in
                    history.apply(updated)
                    engine.updateRecipe(updated)
                }
            )
        case .eq:
            EQEditorPanel(recipe: history.current) { updated in
                history.apply(updated)
                engine.updateRecipe(updated)
            }
        case .filter:
            FilterEditorPanel(recipe: history.current) { updated in
                history.apply(updated)
                engine.updateRecipe(updated)
            }
        }
    }

    private func startLoading() {
        let url = source.fileURL(using: services.recordingManager)
        waveformTask?.cancel()
        waveformTask = Task {
            do {
                let data = try await WaveformAnalyzer.shared.extractWaveform(url: url, targetBins: 1200)
                try Task.checkCancellation()
                let initialRecipe = AudioEditRecipe(sourceDuration: data.duration)
                await MainActor.run {
                    self.waveform = data
                    self.history = AudioEditHistory(sourceDuration: data.duration)
                    self.selectionStart = 0
                    self.selectionEnd = data.duration
                    self.isLoadingWaveform = false
                    do {
                        try self.engine.load(url: url, recipe: initialRecipe)
                        self.engine.loopRange = AudioTimeRange(start: 0, end: data.duration)
                    } catch {
                        self.loadError = error.localizedDescription
                    }
                }
            } catch is CancellationError {
                // Ignore
            } catch {
                await MainActor.run {
                    self.isLoadingWaveform = false
                    self.loadError = error.localizedDescription
                }
            }
        }
    }

    private func syncEngineAndSelectionAfterRecipeChange() {
        let dur = max(0.05, history.current.effectiveDuration)
        selectionStart = 0
        selectionEnd = dur
        zoomScale = 1.0
        scrollOffsetRatio = 0.0
        engine.updateRecipe(history.current)
        engine.loopRange = AudioTimeRange(start: 0, end: dur)
    }

    private func visibleWindow(duration: TimeInterval) -> AudioTimeRange {
        let winDur = duration / Double(max(1, zoomScale))
        let maxStart = max(0, duration - winDur)
        let start = max(0, min(maxStart, Double(scrollOffsetRatio) * maxStart))
        return AudioTimeRange(start: start, end: min(duration, start + winDur))
    }

    /// Maps the source waveform bins onto the edited timeline `keptRanges` so
    /// trims/cuts immediately reflect in the waveform view without re-reading disk.
    private func activeWaveformBins(from data: WaveformData) -> [WaveformBin] {
        guard history.current.hasTimeEdits, data.duration > 0, !data.bins.isEmpty else {
            return data.bins
        }
        var sliced: [WaveformBin] = []
        let totalCount = data.bins.count
        for range in history.current.keptRanges {
            let startIdx = max(0, min(totalCount - 1, Int((range.start / data.duration) * Double(totalCount))))
            let endIdx = max(startIdx, min(totalCount - 1, Int((range.end / data.duration) * Double(totalCount))))
            sliced.append(contentsOf: data.bins[startIdx...endIdx])
        }
        return sliced.isEmpty ? data.bins : sliced
    }
}

// MARK: - Launcher & Home Screen Widget

struct AudioEditorLauncherView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var activeSource: AudioEditorSource?
    @State private var showFileImporter = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Externe Audiodatei") {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Audiodatei importieren (WAV, MP3, M4A, FLAC…)", systemImage: "folder.badge.plus")
                    }
                    .accessibilityIdentifier("audioEditorLauncherImportButton")
                }

                Section("Aufnahmen bearbeiten & konvertieren") {
                    if services.recordingManager.recordings.isEmpty {
                        Text("Noch keine Aufnahmen vorhanden.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(services.recordingManager.recordings) { rec in
                            Button {
                                activeSource = .recording(rec)
                            } label: {
                                HStack(spacing: 12) {
                                    LevelChip(level: rec.laeqFast)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(rec.name).lineLimit(1)
                                        Text("\(rec.formattedDate) · \(rec.formattedDuration)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "slider.horizontal.3")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .polishedFormChrome()
            .navigationTitle("Audio-Editor & Konverter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.audio]) { result in
                handleImport(result)
            }
            .fullScreenCover(item: $activeSource) { source in
                AudioEditorView(source: source)
                    .environment(services)
            }
            .alert("Import fehlgeschlagen", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let ext = url.pathExtension.isEmpty ? "wav" : url.pathExtension
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("sw2_import_\(UUID().uuidString).\(ext)")
            do {
                try FileManager.default.copyItem(at: url, to: tempURL)
                activeSource = .externalFile(tempURL)
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}

struct AudioEditorHomeWidget: View {
    @Environment(AppServices.self) private var services
    @Environment(\.designAccent) private var accent

    @State private var activeSource: AudioEditorSource?
    @State private var showLauncher = false
    @State private var showFileImporter = false
    @State private var importError: String?

    private var latestRecording: Recording? {
        services.recordingManager.recordings.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let latest = latestRecording {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.title3)
                        .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(latest.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text("\(latest.formattedDuration) · \((latest.audioFileName as NSString).pathExtension.uppercased())")
                            .font(.readout(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } else {
                Text("WAV → MP3, Schnitt, EQ & Filter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    if let latest = latestRecording {
                        activeSource = .recording(latest)
                    } else {
                        showLauncher = true
                    }
                } label: {
                    Label("Bearbeiten", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: Radius.control).fill(accent.opacity(0.2)))
                }
                .buttonStyle(.plain)

                Button {
                    showFileImporter = true
                } label: {
                    Label("Importieren", systemImage: "folder.badge.plus")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: Radius.control).fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fullScreenCover(item: $activeSource) { source in
            AudioEditorView(source: source)
                .environment(services)
        }
        .sheet(isPresented: $showLauncher) {
            AudioEditorLauncherView()
                .environment(services)
                .polishedSheetChrome()
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url):
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let ext = url.pathExtension.isEmpty ? "wav" : url.pathExtension
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("sw2_import_\(UUID().uuidString).\(ext)")
                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    activeSource = .externalFile(tempURL)
                } catch {
                    importError = error.localizedDescription
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("Import fehlgeschlagen", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }
}
