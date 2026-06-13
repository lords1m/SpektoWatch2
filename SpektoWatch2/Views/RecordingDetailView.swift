import SwiftUI
import AVFoundation
import Accelerate
import Combine
import PhotosUI

struct RecordingDetailView: View {
    enum DetailTab: String, Identifiable {
        case overview = "Details"
        case analysis = "Analyse"

        var id: String { rawValue }

        static let allCases: [DetailTab] = [.overview, .analysis]
    }

    private enum ExportKind: String {
        case csv = "CSV"
        case pdf = "PDF"
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var services: AppServices
    // Main shared AudioEngine — used for playback via PlaybackAnalyzer (M14/R1).
    // The second @StateObject vizAudioEngine was removed: constructing a new
    // AudioEngine per detail view allocated a full second DSP pipeline including
    // WatchConnectivityManager, BandstopFilterManager, and all @Published state.
    private var audioEngine: AudioEngine { services.audioEngine! }

    @State private var recording: Recording
    @State private var selectedTab: DetailTab = .overview
    /// User's global colormap preference (shared with the live spectrogram via
    /// the Design tweaks). Mapped to the Metal `ColormapType` raw value below so
    /// the playback spectrogram matches what the user sees live, instead of the
    /// previous hardcoded `0` (Turbo).
    @AppStorage("design.colormap") private var designColormap: String = Colormap.viridis.rawValue
    @AppStorage("recording.waterfallSpectrumMode") private var waterfallSpectrumModeRawValue: String = WaterfallSpectrumMode.continuous.rawValue
    @StateObject private var audioPlayer = AudioPlayerManager()
    @StateObject private var playbackAnalyzer = PlaybackAnalyzer()
    @StateObject private var playbackFFTConfig = FFTConfiguration()

    @State private var isDraggingSlider = false
    /// Owns the stored-measurement spectrogram pipeline (loading, weighting,
    /// resolution promotion, level-of-detail tiles). Extracted from this view so
    /// the heavy DSP/model work no longer re-renders with the playhead.
    @StateObject private var spectrogramModel = RecordingSpectrogramModel()
    @State private var spectrogramExportTask: Task<Void, Never>?
    @State private var selectedMetrics: Set<String> = []
    @State private var analysisStartTime: TimeInterval = 0
    @State private var analysisEndTime: TimeInterval = 0
    /// Cached result of `provider.rows(in:step:)` for the current analysis
    /// range. `rows(in:)` iterates the entire stored frame array, and the
    /// metrics table sits inside the same body that re-renders ~30×/s during
    /// playback (the playhead binding). Recomputing it per render pegged the
    /// CPU on long recordings, so we recompute only when the range actually
    /// changes (see `refreshMetricTableRows`).
    @State private var cachedMetricRows: [StoredMetricRow] = []
    @State private var playbackWidgets: [WidgetConfiguration] = []
    @State private var playbackWeighting: FrequencyWeighting = .z
    @StateObject private var waterfallController = WaterfallPlaybackController()

    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var exportTask: Task<Void, Never>?
    @State private var activeExportKind: ExportKind?
    @State private var exportAlertTitle = "Export fehlgeschlagen"
    @State private var isExportingSpectrogram = false
    @State private var isExportingWaterfall = false
    @State private var spectrogramExportError: String?
    @State private var showSpectrogramExportError = false
    @State private var autoFitToastText: String?
    @State private var autoFitToastTask: Task<Void, Never>?

    init(recording: Recording) {
        _recording = State(initialValue: recording)
    }

    var body: some View {
        // No NavigationView/NavigationStack here: this view is always pushed
        // onto the recordings list's stack, so the title and toolbar attach to
        // the parent bar. Wrapping it again nested two navigation containers.
        VStack(spacing: 12) {
                Picker("Tab", selection: $selectedTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch selectedTab {
                case .overview:
                    overviewTab
                case .analysis:
                    analysisTab
                }
            }
            .background(GlassBackground())
            .navigationTitle(recording.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            shareItems = [services.recordingManager.url(for: recording)]
                            showShareSheet = true
                        } label: {
                            Label("Audio teilen", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            createPDFReport()
                        } label: {
                            Label("PDF erstellen", systemImage: "doc.richtext")
                        }
                        .disabled(activeExportKind != nil)

                        Button {
                            exportSpectrogramImage()
                        } label: {
                            if isExportingSpectrogram {
                                Label("Spektrogramm wird exportiert…", systemImage: "hourglass")
                            } else {
                                Label("Spektrogramm exportieren", systemImage: "photo")
                            }
                        }
                        .disabled(isExportingSpectrogram)

                        if spectrogramModel.hasMeasurementData {
                            Button {
                                shareRawMeasurementData()
                            } label: {
                                Label("Messdaten teilen", systemImage: "doc.badge.arrow.up")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }

            }
        .sheet(isPresented: $showShareSheet) {
            ActivityView(activityItems: shareItems)
        }
        .alert(exportAlertTitle, isPresented: $showSpectrogramExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(spectrogramExportError ?? "Unbekannter Fehler")
        }
        .overlay {
            if let activeExportKind {
                ExportProgressOverlay(
                    title: "\(activeExportKind.rawValue) wird erstellt",
                    cancel: cancelActiveExport
                )
            }
        }
        .onAppear {
            reloadRecordingState()
            let audioURL = services.recordingManager.url(for: recording)
            if !audioPlayer.loadAudio(url: audioURL) {
                showExportError(
                    title: "Wiedergabe nicht möglich",
                    message: "Die Audiodatei dieser Aufnahme konnte nicht geladen werden. Sie ist möglicherweise beschädigt oder wurde verschoben."
                )
            }

            // PlaybackAnalyzer suspends the live mic engine and routes
            // playback samples through the shared pipeline (M14/R1).
            playbackAnalyzer.start(engine: audioEngine, recording: recording)
            audioPlayer.onAudioSamples = { [weak playbackAnalyzer] samples, sampleRate in
                playbackAnalyzer?.processSamples(samples, sampleRate: sampleRate)
            }
            if let weighting = FrequencyWeighting(rawValue: recording.frequencyWeighting) {
                playbackWeighting = weighting
            }
            if let blockSize = FFTBlockSize(rawValue: recording.fftBlockSize) {
                playbackFFTConfig.blockSize = blockSize
            }
            analysisEndTime = max(audioPlayer.duration, recording.duration)
            if let savedMode = WaterfallSpectrumMode(rawValue: waterfallSpectrumModeRawValue) {
                waterfallController.display.spectrumMode = savedMode
            }
            loadPlaybackWidgets()
            configureSpectrogramModel()
            spectrogramModel.load(
                measurementURL: services.recordingManager.measurementURL(for: recording),
                audioURL: audioURL,
                calibrationOffset: recording.calibrationOffset,
                fftBlockSize: recording.fftBlockSize,
                fallbackSampleRate: recording.sampleRate,
                weighting: playbackWeighting
            )
        }
        .onDisappear {
            audioPlayer.stop()
            // Restore main engine settings and resume live mic capture.
            playbackAnalyzer.stop()
            spectrogramModel.cancel()
            autoFitToastTask?.cancel()
            autoFitToastTask = nil
            waterfallController.cancel()
            spectrogramExportTask?.cancel()
            spectrogramExportTask = nil
            isExportingWaterfall = false
            exportTask?.cancel()
            exportTask = nil
            activeExportKind = nil
        }
        .onChange(of: playbackWeighting) { _, newValue in
            spectrogramModel.applyWeighting(newValue)
        }
        .onChange(of: spectrogramModel.version) { _, _ in
            refreshWaterfallPlayback()
        }
        .onChange(of: spectrogramModel.axis) { _, _ in
            refreshWaterfallPlayback()
        }
        .onChange(of: audioPlayer.duration) { _, _ in
            refreshWaterfallPlayback()
        }
        .onChange(of: audioPlayer.currentTime) { _, time in
            spectrogramModel.scrub(to: time)
        }
        .onChange(of: waterfallController.display.spectrumMode) { _, newMode in
            waterfallSpectrumModeRawValue = newMode.rawValue
        }
    }

    private var overviewTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                RecordingHeaderCard(name: recording.name, formattedDate: recording.formattedDate)
                audioPlayerCard
                playbackWidgetsCard
                RecordingStatisticsCard(
                    laeqFast: recording.laeqFast,
                    peakLevel: recording.peakLevel,
                    minLevel: recording.minLevel,
                    formattedDuration: recording.formattedDuration
                )
                RecordingConfigurationCard(
                    timeWeighting: recording.timeWeighting,
                    frequencyWeighting: recording.frequencyWeighting,
                    sampleRate: recording.sampleRate,
                    fftBlockSize: recording.fftBlockSize,
                    calibrationOffset: recording.calibrationOffset
                )
                RecordingNotesCard(text: $recording.description) {
                    services.recordingManager.updateRecording(recording)
                }
                RecordingPhotosCard(
                    photoFileNames: recording.photoFileNames,
                    photoURL: { services.recordingManager.getPhotoURL(fileName: $0) },
                    onDelete: { fileName in
                        services.recordingManager.deletePhoto(fileName: fileName)
                        recording.photoFileNames.removeAll { $0 == fileName }
                        services.recordingManager.updateRecording(recording)
                    },
                    onAdd: { imageData in
                        guard let data = imageData else { return }
                        if let fileName = try? services.recordingManager.savePhoto(data, recordingID: recording.id) {
                            recording.photoFileNames.append(fileName)
                            services.recordingManager.updateRecording(recording)
                        }
                    }
                )
                overviewExportCard
            }
            .padding()
        }
    }

    private var overviewExportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ExportActionButton(
                    title: "PDF",
                    systemImage: activeExportKind == .pdf ? "hourglass" : "doc.richtext",
                    isLoading: activeExportKind == .pdf,
                    isDisabled: activeExportKind == .csv
                ) { createPDFReport() }

                ExportActionButton(
                    title: "Audio",
                    systemImage: "square.and.arrow.up"
                ) {
                    shareItems = [services.recordingManager.url(for: recording)]
                    showShareSheet = true
                }

                ExportActionButton(
                    title: "Spektrogramm",
                    systemImage: isExportingSpectrogram ? "hourglass" : "photo",
                    isLoading: isExportingSpectrogram
                ) { exportSpectrogramImage() }

                ExportActionButton(
                    title: "CSV",
                    systemImage: activeExportKind == .csv ? "hourglass" : "tablecells",
                    isLoading: activeExportKind == .csv,
                    isDisabled: !spectrogramModel.hasMeasurementData || activeExportKind == .pdf,
                    disabledHint: spectrogramModel.hasMeasurementData ? nil : "Keine Messdaten"
                ) { createCSVExport() }

                ExportActionButton(
                    title: "Messdaten",
                    systemImage: "doc.badge.arrow.up",
                    isDisabled: !spectrogramModel.hasMeasurementData,
                    disabledHint: "Keine Messdaten"
                ) { shareRawMeasurementData() }
            }
        }
        .padding()
        .glassCard(cornerRadius: 14)
    }

    private var spectralFallbackBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform.badge.exclamationmark")
                .foregroundStyle(.orange)
            Text("In der Messdatei sind keine Terzband-Spektren gespeichert (z. B. ältere Watch-Aufnahme). Wasserfall und Frequenzansicht nutzen eine Neuberechnung aus der Audiodatei.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .glassCard(cornerRadius: 14)
    }

    private var analysisTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if spectrogramModel.usesAudioSpectralFallback {
                    spectralFallbackBanner
                }
                if let provider = spectrogramModel.provider {
                    analysisRangeCard(duration: provider.duration)
                    metricSelectionCard(metricKeys: provider.metricKeys)
                    lineHistoryCard(values: provider.levelHistory)
                    metricsTableCard(provider: provider)
                    exportCard
                } else {
                    Text("Keine .spekto-Messdaten vorhanden. Für tiefe Analyse bitte Messdatenaufzeichnung aktivieren.")
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(cornerRadius: 14)
                }
            }
            .padding()
        }
    }

    private var waterfallTab: some View {
        ScrollView {
            RecordingWaterfallSection(
                controller: waterfallController,
                playbackWeighting: $playbackWeighting,
                isLoadingSpectrogram: spectrogramModel.isLoading,
                isPromotingResolution: spectrogramModel.isPromotingResolution,
                spectrogramHistoryEmpty: spectrogramModel.history.isEmpty,
                usesAudioSpectralFallback: spectrogramModel.usesAudioSpectralFallback,
                highlightedTime: isDraggingSlider ? audioPlayer.scrubTime : audioPlayer.currentTime,
                autoFitToastText: autoFitToastText,
                onDisplaySettingsChanged: refreshWaterfallPlayback,
                onAutoFitDBRange: autoFitWaterfallDBRange
            )
            .padding()
        }
    }

    // MARK: - Cards

    /// Maps the design-token `Colormap` (viridis/inferno/magma) to the Metal
    /// `ColormapType` raw value the spectrogram views expect. Falls back to
    /// viridis (2) for any unknown stored value.
    private var playbackColormapType: Int {
        DesignColormap.metalRawValue(from: designColormap)
    }

    private var audioPlayerCard: some View {
        VStack(spacing: 16) {
            playbackWeightingPicker
            if !spectrogramModel.history.isEmpty {
                NavigableSpectrogramView(
                    magnitudeHistory: spectrogramModel.history,
                    dataVersion: spectrogramModel.version,
                    duration: max(audioPlayer.duration, recording.duration),
                    currentTime: isDraggingSlider ? audioPlayer.scrubTime : audioPlayer.currentTime,
                    colormapType: playbackColormapType,
                    sampleRate: Float(recording.sampleRate),
                    calibrationOffset: recording.calibrationOffset,
                    axisKind: spectrogramModel.axis,
                    markers: recording.markers ?? [],
                    onSeek: { time in
                        audioPlayer.scrubTime = time
                        audioPlayer.seek(to: time)
                    },
                    detailTileLoader: spectrogramModel.makeDetailTileLoader()
                )
            } else if spectrogramModel.isLoading {
                ZStack {
                    Color.black
                    ProgressView("Spektrogramm wird berechnet...")
                        .tint(.white)
                        .foregroundColor(.white)
                }
                .frame(height: 280)
                .cornerRadius(12)
            } else {
                ZStack {
                    Color.black
                    Text("Spektrogramm nicht verfügbar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 280)
                .cornerRadius(12)
            }

            if let provider = spectrogramModel.provider,
               let level = provider.currentSpectrogramData?.broadbandLevel,
               spectrogramModel.hasMeasurementData {
                Text(String(format: "Pegel bei %.1f s: %.1f dB", audioPlayer.currentTime, level))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 20) {
                Button(action: { audioPlayer.seek(by: -5) }) {
                    Image(systemName: "gobackward.5").font(.title2)
                }
                .disabled(!audioPlayer.isLoaded)
                .accessibilityLabel("5 Sekunden zurück")

                Button(action: togglePlayback) {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 58))
                }
                .disabled(!audioPlayer.isLoaded)
                .accessibilityLabel(audioPlayer.isPlaying ? "Wiedergabe pausieren" : "Wiedergabe starten")

                Button(action: { audioPlayer.seek(by: 5) }) {
                    Image(systemName: "goforward.5").font(.title2)
                }
                .disabled(!audioPlayer.isLoaded)
                .accessibilityLabel("5 Sekunden vor")
            }
            .foregroundColor(.blue)

            Button {
                addMarkerAtCurrentTime()
            } label: {
                Label("Marker setzen", systemImage: "bookmark.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!audioPlayer.isLoaded)

            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { isDraggingSlider ? audioPlayer.scrubTime : audioPlayer.currentTime },
                        set: {
                            audioPlayer.scrubTime = $0
                            audioPlayer.seek(to: $0)
                        }
                    ),
                    in: 0...max(audioPlayer.duration, 0.1),
                    onEditingChanged: { editing in
                        isDraggingSlider = editing
                        if editing { audioPlayer.beginScrubbing() } else { audioPlayer.endScrubbing() }
                    }
                )
                .disabled(!audioPlayer.isLoaded)

                HStack {
                    Text(formatTime(isDraggingSlider ? audioPlayer.scrubTime : audioPlayer.currentTime))
                        .font(.caption)
                        .monospacedDigit()
                    Spacer()
                    Text(formatTime(audioPlayer.duration))
                        .font(.caption)
                        .monospacedDigit()
                }
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .glassCard(cornerRadius: 14)
    }

    private var playbackWeightingPicker: some View {
        HStack(spacing: 8) {
            Text("Frequenzbewertung")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Picker("Frequenzbewertung", selection: $playbackWeighting) {
                ForEach(FrequencyWeighting.allCases, id: \.self) { weighting in
                    Text(weighting.rawValue).tag(weighting)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            if spectrogramModel.isPromotingResolution {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var playbackWidgetsCard: some View {
        let widgets = playbackWidgets.filter { $0.type != .spectrogram }
        if !widgets.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Widgets")
                    .font(.headline)
                ForEach(widgets) { widget in
                    WidgetCardView(
                        widget: widget,
                        audioEngine: audioEngine,
                        fftConfig: playbackFFTConfig,
                        isEditMode: false,
                        columnWidth: 160,
                        onDelete: {},
                        onResize: { _ in },
                        onUpdateSettings: { _ in }
                    )
                }
            }
            .padding()
            .glassCard(cornerRadius: 14)
        }
    }

    private func analysisRangeCard(duration: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zeitraum")
                .font(.headline)

            Text("Start: \(formatTime(analysisStartTime))")
                .font(.caption)
            Slider(value: $analysisStartTime, in: 0...max(duration, 0.1))
                .onChange(of: analysisStartTime) { _, newValue in
                    if newValue > analysisEndTime {
                        analysisEndTime = newValue
                    }
                    refreshMetricTableRows()
                }

            Text("Ende: \(formatTime(analysisEndTime))")
                .font(.caption)
            Slider(value: $analysisEndTime, in: 0...max(duration, 0.1))
                .onChange(of: analysisEndTime) { _, newValue in
                    if newValue < analysisStartTime {
                        analysisStartTime = newValue
                    }
                    refreshMetricTableRows()
                }
        }
        .padding()
        .glassCard(cornerRadius: 14)
    }

    private func metricSelectionCard(metricKeys: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Metrik-Spalten")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                ForEach(metricKeys, id: \.self) { key in
                    Button {
                        if selectedMetrics.contains(key) {
                            selectedMetrics.remove(key)
                        } else {
                            selectedMetrics.insert(key)
                        }
                    } label: {
                        Text(key)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(selectedMetrics.contains(key) ? Color.blue.opacity(0.25) : Color.secondary.opacity(0.15))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .glassCard(cornerRadius: 14)
    }

    private func lineHistoryCard(values: [Float]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pegelverlauf")
                .font(.headline)
            MiniLineChart(values: values)
                .frame(height: 130)
        }
        .padding()
        .glassCard(cornerRadius: 14)
    }

    /// Recomputes `cachedMetricRows` for the current analysis range. Called when
    /// the range changes or a provider becomes available — never from `body`.
    private func refreshMetricTableRows() {
        guard let provider = spectrogramModel.provider else {
            cachedMetricRows = []
            return
        }
        cachedMetricRows = provider.rows(in: analysisStartTime...analysisEndTime, step: 4)
    }

    private func metricsTableCard(provider: StoredDataProvider) -> some View {
        let effectiveMetrics = selectedMetrics.isEmpty ? Set(provider.metricKeys.prefix(6)) : selectedMetrics
        let orderedMetrics = Array(effectiveMetrics).sorted()
        let rows = cachedMetricRows
        let timeColumnWidth: CGFloat = 72
        let metricColumnWidth: CGFloat = 84
        let spacing: CGFloat = 12
        let tableMinWidth = timeColumnWidth + CGFloat(orderedMetrics.count) * metricColumnWidth + CGFloat(orderedMetrics.count + 1) * spacing

        return VStack(alignment: .leading, spacing: 10) {
            Text("Messwerttabelle")
                .font(.headline)

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: spacing) {
                        Text("t [s]").bold().frame(width: timeColumnWidth, alignment: .leading)
                        ForEach(orderedMetrics, id: \.self) { metric in
                            Text(metric).bold().frame(width: metricColumnWidth, alignment: .leading)
                        }
                    }
                    .font(.caption)

                    Divider()

                    ForEach(rows.prefix(250)) { row in
                        HStack(spacing: spacing) {
                            Text(String(format: "%.2f", row.time))
                                .frame(width: timeColumnWidth, alignment: .leading)
                            ForEach(orderedMetrics, id: \.self) { metric in
                                Text(String(format: "%.1f", row.values[metric] ?? -120))
                                    .frame(width: metricColumnWidth, alignment: .leading)
                            }
                        }
                        .font(.caption2.monospacedDigit())
                    }
                }
                .frame(minWidth: tableMinWidth, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 260, alignment: .topLeading)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.45), lineWidth: 0.8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding()
        .glassCard(cornerRadius: 14)
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                Button {
                    createCSVExport()
                } label: {
                    if activeExportKind == .csv {
                        Label("CSV...", systemImage: "hourglass").frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Label("CSV", systemImage: "tablecells").frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(activeExportKind != nil)

                Button {
                    createPDFReport()
                } label: {
                    if activeExportKind == .pdf {
                        Label("PDF...", systemImage: "hourglass").frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Label("PDF", systemImage: "doc.richtext").frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(activeExportKind != nil)

                Button {
                    exportSpectrogramImage()
                } label: {
                    Group {
                        if isExportingSpectrogram {
                            Label("Spektrogramm…", systemImage: "hourglass").frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Label("Spektrogramm", systemImage: "photo").frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isExportingSpectrogram)

                Button {
                    shareRawMeasurementData()
                } label: {
                    Label("Messdaten", systemImage: "doc.badge.arrow.up").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .glassCard(cornerRadius: 14)
    }

    // MARK: - Actions

    private func togglePlayback() {
        if audioPlayer.isPlaying {
            audioPlayer.pause()
            spectrogramModel.providerPause()
        } else {
            audioPlayer.play()
            spectrogramModel.providerPlay()
        }
    }

    private func addMarkerAtCurrentTime() {
        var markers = recording.markers ?? []
        let marker = MeasurementMarker(
            time: audioPlayer.currentTime,
            title: "Marker \(markers.count + 1)"
        )
        markers.append(marker)
        markers.sort { $0.time < $1.time }
        recording.markers = markers
        services.recordingManager.updateRecording(recording)
    }

    private func loadPlaybackWidgets() {
        guard let data = recording.widgetConfigurations else {
            playbackWidgets = []
            return
        }
        do {
            let decoded = try JSONDecoder().decode([WidgetConfiguration].self, from: data)
            playbackWidgets = decoded.map { widget in
                var normalized = widget
                if normalized.type == .octaveBands {
                    normalized.type = .frequencyDisplay
                    if normalized.settings["frequencyBands"] == nil {
                        normalized.settings["frequencyBands"] = "terz"
                    }
                }
                return normalized
            }
        } catch {
            print("[RecordingDetailView] Failed to decode widget configurations: \(error)")
            playbackWidgets = []
        }
    }

    /// Wires the spectrogram model's callbacks back into view-owned state
    /// (spectral-availability flag persistence and analysis defaults).
    private func configureSpectrogramModel() {
        spectrogramModel.onSpectralFlagResolved = { spectralOK in
            persistSpectralFlagIfNeeded(spectralOK)
        }
        spectrogramModel.onMeasurementDataReady = { provider in
            if selectedMetrics.isEmpty {
                selectedMetrics = Set(provider.metricKeys.prefix(6))
            }
            analysisEndTime = max(analysisEndTime, provider.duration)
            refreshMetricTableRows()
        }
    }

    private func persistSpectralFlagIfNeeded(_ spectralOK: Bool) {
        guard recording.spectralDataAvailable != spectralOK else { return }
        var updated = recording
        updated.spectralDataAvailable = spectralOK
        recording = updated
        services.recordingManager.updateRecording(updated)
    }

    private func createCSVExport() {
        guard activeExportKind == nil else { return }
        guard let measurementURL = services.recordingManager.measurementURL(for: recording) else {
            showExportError(title: "Export fehlgeschlagen", message: "Keine Messdaten vorhanden.")
            return
        }

        let recordingID = recording.id.uuidString
        let selectedMetricsSnapshot = selectedMetrics
        activeExportKind = .csv
        exportTask = Task.detached(priority: .userInitiated) {
            do {
                let reader = try MeasurementDataReader(fileURL: measurementURL)
                let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(recordingID)_analyse.csv")
                let metrics = selectedMetricsSnapshot.isEmpty
                    ? reader.header.metricKeys
                    : reader.header.metricKeys.filter { selectedMetricsSnapshot.contains($0) }
                try CSVExporter().export(reader: reader, to: outputURL, selectedMetrics: metrics, includeThirdOctaves: true)
                try Task.checkCancellation()
                await MainActor.run {
                    finishSuccessfulExport(outputURL)
                }
            } catch is CancellationError {
                await MainActor.run {
                    finishCancelledExport()
                }
            } catch {
                await MainActor.run {
                    showExportError(title: "Export fehlgeschlagen", message: error.localizedDescription)
                    finishExport()
                }
            }
        }
    }

    private func createPDFReport() {
        guard activeExportKind == nil else { return }

        let recordingSnapshot = recording
        let audioURL = services.recordingManager.url(for: recording)
        let measurementURL = services.recordingManager.measurementURL(for: recording)
        let photoURLs = recording.photoFileNames.map { services.recordingManager.getPhotoURL(fileName: $0) }

        activeExportKind = .pdf
        exportTask = Task.detached(priority: .userInitiated) {
            do {
                let pdfURL = try PDFReportGenerator().generateReport(
                    for: recordingSnapshot,
                    audioURL: audioURL,
                    measurementURL: measurementURL,
                    photoURLs: photoURLs
                )
                try Task.checkCancellation()
                await MainActor.run {
                    finishSuccessfulExport(pdfURL)
                }
            } catch is CancellationError {
                await MainActor.run {
                    finishCancelledExport()
                }
            } catch {
                await MainActor.run {
                    showExportError(title: "Export fehlgeschlagen", message: error.localizedDescription)
                    finishExport()
                }
            }
        }
    }

    private func cancelActiveExport() {
        exportTask?.cancel()
        activeExportKind = nil
    }

    private func finishSuccessfulExport(_ url: URL) {
        guard activeExportKind != nil else { return }
        shareItems = [url]
        showShareSheet = true
        finishExport()
    }

    private func finishCancelledExport() {
        let shouldShowAlert = activeExportKind != nil
        finishExport()
        if shouldShowAlert {
            showExportError(title: "Export abgebrochen", message: "Der laufende Export wurde abgebrochen.")
        }
    }

    private func finishExport() {
        activeExportKind = nil
        exportTask = nil
    }

    private func showExportError(title: String, message: String) {
        exportAlertTitle = title
        spectrogramExportError = message
        showSpectrogramExportError = true
    }

    private func exportSpectrogramImage() {
        spectrogramExportTask?.cancel()
        let audioURL = services.recordingManager.url(for: recording)
        let recordingID = recording.id.uuidString
        let historySnapshot = spectrogramModel.history
        let axisSnapshot = spectrogramModel.axis
        let sampleRate = spectrogramModel.sampleRate
        let calibrationOffset = recording.calibrationOffset
        let fftBlockSize = recording.fftBlockSize
        isExportingSpectrogram = true
        spectrogramExportTask = Task.detached(priority: .userInitiated) {
            let result: Result<URL, Error> = Result {
                let exporter = SpectrogramImageExporter()
                if !historySnapshot.isEmpty {
                    return try exporter.export(
                        history: historySnapshot,
                        axis: axisSnapshot,
                        sampleRate: sampleRate,
                        calibrationOffset: calibrationOffset,
                        recordingID: recordingID
                    )
                }
                return try exporter.export(
                    audioURL: audioURL,
                    recordingID: recordingID,
                    fftSize: fftBlockSize,
                    calibrationOffset: calibrationOffset
                )
            }
            if Task.isCancelled { return }
            await MainActor.run {
                guard !Task.isCancelled else {
                    isExportingSpectrogram = false
                    return
                }
                isExportingSpectrogram = false
                switch result {
                case .success(let url):
                    shareItems = [url]
                    showShareSheet = true
                case .failure(let error):
                    showExportError(title: "Export fehlgeschlagen", message: error.localizedDescription)
                }
            }
        }
    }

    private func exportWaterfallImage() {
        let dataSet = waterfallController.dataSet
        guard !dataSet.isEmpty else {
            showExportError(title: "Export fehlgeschlagen", message: "Keine Wasserfall-Daten zum Exportieren vorhanden.")
            return
        }
        let recordingID = recording.id.uuidString
        isExportingWaterfall = true
        Task.detached(priority: .userInitiated) {
            let result: Result<URL, Error> = Result {
                try WaterfallImageExporter().export(dataSet: dataSet, recordingID: recordingID)
            }
            if Task.isCancelled { return }
            await MainActor.run {
                isExportingWaterfall = false
                switch result {
                case .success(let url):
                    shareItems = [url]
                    showShareSheet = true
                case .failure(let error):
                    showExportError(title: "Export fehlgeschlagen", message: error.localizedDescription)
                }
            }
        }
    }

    private func shareRawMeasurementData() {
        guard let measurementURL = services.recordingManager.measurementURL(for: recording),
              FileManager.default.fileExists(atPath: measurementURL.path) else { return }
        shareItems = [measurementURL]
        showShareSheet = true
    }

    private func reloadRecordingState() {
        if let updated = services.recordingManager.recordings.first(where: { $0.id == recording.id }) {
            recording = updated
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func refreshWaterfallPlayback() {
        let duration = max(audioPlayer.duration, recording.duration, spectrogramModel.provider?.duration ?? 0)
        waterfallController.rebuild(
            history: spectrogramModel.history,
            axis: spectrogramModel.axis,
            sampleRate: spectrogramModel.sampleRate,
            duration: duration,
            storedProviderHasFullFFT: spectrogramModel.provider?.hasFullFFT == true,
            fftBinCount: spectrogramModel.provider?.fftBinCount ?? 0
        )
    }

    private func autoFitWaterfallDBRange() {
        let flattened = waterfallController.dataSet.slices.flatMap(\.magnitudes).filter(\.isFinite)
        guard !flattened.isEmpty else { return }
        let sorted = flattened.sorted()
        func percentile(_ p: Float) -> Float {
            let idx = Int((Float(sorted.count - 1) * p).rounded())
            return sorted[min(max(0, idx), sorted.count - 1)]
        }
        let lower = percentile(0.05)
        let upper = percentile(0.98)
        var minDB = floor(lower / 5) * 5
        var maxDB = ceil(upper / 5) * 5
        if maxDB - minDB < 20 {
            let mid = (maxDB + minDB) / 2
            minDB = floor((mid - 10) / 5) * 5
            maxDB = ceil((mid + 10) / 5) * 5
        }
        waterfallController.display.minDB = max(0, minDB)
        waterfallController.display.maxDB = min(140, maxDB)
        refreshWaterfallPlayback()
        autoFitToastTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) {
            autoFitToastText = "Automatisch angepasst: \(Int(waterfallController.display.minDB))…\(Int(waterfallController.display.maxDB)) dB SPL"
        }
        autoFitToastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                autoFitToastText = nil
            }
        }
    }

}

// MARK: - Extracted as part of M13 task-2
//
//   MiniLineChart, StatRow → Views/RecordingDetailComponents.swift
//   AudioPlayerManager     → Views/AudioPlayerManager.swift
//   PhotoPickerView        → Views/PhotoPickerView.swift
//
// The private ExportActionButton stays in this file because it's only
// used by RecordingDetailView.

// MARK: - ExportProgressOverlay

private struct ExportProgressOverlay: View {
    let title: String
    let cancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)

                Text(title)
                    .font(.headline)

                Button(role: .cancel, action: cancel) {
                    Label("Abbrechen", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
            .padding(22)
            .frame(maxWidth: 280)
            .glassCard(cornerRadius: 14)
        }
    }
}

// MARK: - ExportActionButton

private struct ExportActionButton: View {
    let title: String
    let systemImage: String
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var disabledHint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().scaleEffect(0.75)
                } else {
                    Image(systemName: systemImage)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline)
                    if isDisabled, let hint = disabledHint {
                        Text(hint)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .disabled(isDisabled || isLoading)
        .buttonStyle(.bordered)
        .opacity(isDisabled ? 0.45 : 1)
    }
}
