import SwiftUI
import AVFoundation
import Accelerate
import Combine
import PhotosUI

struct RecordingDetailView: View {
    enum DetailTab: String, CaseIterable, Identifiable {
        case overview = "Details"
        case analysis = "Analyse"
        case waterfall = "Wasserfall"
        var id: String { rawValue }
    }

    private enum ExportKind: String {
        case csv = "CSV"
        case pdf = "PDF"
    }

    private static let maxStoredSpectrogramOverviewFrames = 1_800

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var recordingManager: RecordingManager

    @State private var recording: Recording
    @State private var selectedTab: DetailTab = .overview
    @StateObject private var audioPlayer = AudioPlayerManager()
    @StateObject private var vizAudioEngine = AudioEngine(
        filterManager: BandstopFilterManager(),
        connectivityManager: WatchConnectivityManager()
    )
    @StateObject private var playbackFFTConfig = FFTConfiguration()

    @State private var isDraggingSlider = false
    @State private var spectrogramHistory: [[Float]] = []
    @State private var rawSpectrogramHistory: [[Float]] = []
    @State private var isLoadingSpectrogram = false
    @State private var storedDataProvider: StoredDataProvider?
    /// Tracks the background load (StoredDataProvider bootstrap or FFT fallback)
    /// so it can be cancelled when the view disappears. Without this, a long
    /// recording would keep CPU pegged after the user navigates away, and the
    /// completion handler would mutate state on a view that's no longer visible.
    @State private var spectrogramLoadTask: Task<Void, Never>?
    @State private var weightingTask: Task<Void, Never>?
    @State private var spectrogramExportTask: Task<Void, Never>?
    @State private var selectedMetrics: Set<String> = []
    @State private var analysisStartTime: TimeInterval = 0
    @State private var analysisEndTime: TimeInterval = 0
    @State private var playbackWidgets: [WidgetConfiguration] = []
    @State private var playbackWeighting: FrequencyWeighting = .z
    @State private var weightedSpectrogramCache: [FrequencyWeighting: [[Float]]] = [:]
    @State private var isPromotingSpectrogramResolution = false
    @State private var waterfallSliceCount: Double = 96
    @State private var waterfallMinDB: Double = -110
    @State private var waterfallMaxDB: Double = 20
    @State private var waterfallDataSet = WaterfallDataSet(slices: [], frequencies: [], duration: 0, minDB: -110, maxDB: 20)

    @State private var showShareSheet = false
    @State private var showPhotoPicker = false
    @State private var shareItems: [Any] = []
    @State private var exportTask: Task<Void, Never>?
    @State private var activeExportKind: ExportKind?
    @State private var exportAlertTitle = "Export fehlgeschlagen"
    @State private var isExportingSpectrogram = false
    @State private var spectrogramExportError: String?
    @State private var showSpectrogramExportError = false
    @State private var hasMeasurementData = false

    init(recording: Recording) {
        _recording = State(initialValue: recording)
    }

    var body: some View {
        NavigationView {
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
                case .waterfall:
                    waterfallTab
                }
            }
            .background(GlassBackground())
            .navigationTitle(recording.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            shareItems = [recordingManager.url(for: recording)]
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

                        if hasMeasurementData {
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

                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fertig") { dismiss() }
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
            let audioURL = recordingManager.url(for: recording)
            audioPlayer.loadAudio(url: audioURL)
            audioPlayer.onAudioSamples = { samples in
                vizAudioEngine.processExternalAudio(samples, sampleRate: recording.sampleRate)
            }
            vizAudioEngine.calibrationOffset = recording.calibrationOffset
            if let weighting = FrequencyWeighting(rawValue: recording.frequencyWeighting) {
                vizAudioEngine.setFrequencyWeighting(weighting)
                playbackWeighting = weighting
            }
            if let timeWeighting = TimeWeighting(rawValue: recording.timeWeighting) {
                vizAudioEngine.setTimeWeighting(timeWeighting)
            }
            if let blockSize = FFTBlockSize(rawValue: recording.fftBlockSize) {
                playbackFFTConfig.blockSize = blockSize
                vizAudioEngine.setBlockSize(blockSize)
            }
            analysisEndTime = max(audioPlayer.duration, recording.duration)
            loadPlaybackWidgets()
            loadStoredMeasurementDataIfAvailable()
        }
        .onDisappear {
            audioPlayer.stop()
            storedDataProvider?.pause()
            spectrogramLoadTask?.cancel()
            spectrogramLoadTask = nil
            weightingTask?.cancel()
            weightingTask = nil
            spectrogramExportTask?.cancel()
            spectrogramExportTask = nil
            exportTask?.cancel()
            exportTask = nil
            activeExportKind = nil
        }
        .onChange(of: playbackWeighting) { _, newValue in
            applyPlaybackWeighting(newValue)
        }
        .onChange(of: spectrogramHistory) { _, _ in
            rebuildWaterfallDataSet()
        }
        .onChange(of: waterfallSliceCount) { _, _ in
            rebuildWaterfallDataSet()
        }
        .onChange(of: waterfallMinDB) { _, _ in
            rebuildWaterfallDataSet()
        }
        .onChange(of: waterfallMaxDB) { _, _ in
            rebuildWaterfallDataSet()
        }
        .onChange(of: audioPlayer.currentTime) { _, time in
            storedDataProvider?.scrub(to: time)
        }
    }

    private var overviewTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCard
                audioPlayerCard
                playbackWidgetsCard
                statisticsCard
                metadataCard
                notesCard
                photosCard
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
                    shareItems = [recordingManager.url(for: recording)]
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
                    isDisabled: !hasMeasurementData || activeExportKind == .pdf,
                    disabledHint: hasMeasurementData ? nil : "Keine Messdaten"
                ) { createCSVExport() }

                ExportActionButton(
                    title: "Messdaten",
                    systemImage: "doc.badge.arrow.up",
                    isDisabled: !hasMeasurementData,
                    disabledHint: "Keine Messdaten"
                ) { shareRawMeasurementData() }
            }
        }
        .padding()
        .glassCard(cornerRadius: 14)
    }

    private var analysisTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let provider = storedDataProvider {
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
            VStack(alignment: .leading, spacing: 14) {
                waterfallCard
                waterfallControlsCard
            }
            .padding()
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.blue)
            Text(recording.name)
                .font(.title3.bold())
            Text(recording.formattedDate)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassCard(cornerRadius: 14)
    }

    private var audioPlayerCard: some View {
        VStack(spacing: 16) {
            playbackWeightingPicker
            if !spectrogramHistory.isEmpty {
                ScrollableSpectrogramView(
                    currentTime: Binding(
                        get: { isDraggingSlider ? audioPlayer.scrubTime : audioPlayer.currentTime },
                        set: { _ in }
                    ),
                    duration: max(audioPlayer.duration, recording.duration),
                    magnitudeHistory: spectrogramHistory,
                    colormapType: 0,
                    sampleRate: Float(recording.sampleRate),
                    calibrationOffset: recording.calibrationOffset,
                    markers: recording.markers ?? [],
                    onSeek: { time in
                        audioPlayer.scrubTime = time
                        audioPlayer.seek(to: time)
                    },
                    showsFullDuration: true
                )
                .frame(height: 280)
                .background(Color.black)
                .cornerRadius(12)
            } else if isLoadingSpectrogram {
                ZStack {
                    Color.black
                    ProgressView("Spektrogramm wird berechnet...")
                        .tint(.white)
                        .foregroundColor(.white)
                }
                .frame(height: 280)
                .cornerRadius(12)
            } else {
                HighEndSpectrogramAdapterWithAxes(audioEngine: vizAudioEngine, timeSpan: .seconds5, scrollSpeed: .fast)
                    .frame(height: 280)
                    .cornerRadius(12)
            }

            HStack(spacing: 20) {
                Button(action: { audioPlayer.seek(by: -5) }) {
                    Image(systemName: "gobackward.5").font(.title2)
                }.disabled(!audioPlayer.isLoaded)

                Button(action: togglePlayback) {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 58))
                }.disabled(!audioPlayer.isLoaded)

                Button(action: { audioPlayer.seek(by: 5) }) {
                    Image(systemName: "goforward.5").font(.title2)
                }.disabled(!audioPlayer.isLoaded)
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
            if isPromotingSpectrogramResolution {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 6)
    }

    private var waterfallCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Wasserfall")
                    .font(.headline)
                Spacer()
                playbackWeightingPicker
                    .frame(maxWidth: 280)
            }

            WaterfallView(
                dataSet: waterfallDataSet,
                highlightedTime: isDraggingSlider ? audioPlayer.scrubTime : audioPlayer.currentTime
            )
            .frame(height: 360)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                Text("\(waterfallDataSet.slices.count) Slices")
                Spacer()
                Text("\(Int(waterfallDataSet.minDB))...\(Int(waterfallDataSet.maxDB)) dB")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .glassCard(cornerRadius: 14)
    }

    private var waterfallControlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Darstellung")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Slices: \(Int(waterfallSliceCount))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(value: $waterfallSliceCount, in: 32...160, step: 8)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Min: \(Int(waterfallMinDB)) dB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $waterfallMinDB, in: -140 ... -40, step: 5)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Max: \(Int(waterfallMaxDB)) dB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $waterfallMaxDB, in: -20 ... 120, step: 5)
                }
            }
        }
        .padding()
        .glassCard(cornerRadius: 14)
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
                        audioEngine: vizAudioEngine,
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

    private var statisticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistik")
                .font(.headline)
            Divider()
            StatRow(icon: "waveform.path", title: "LAeq,Fast", value: String(format: "%.1f dB", recording.laeqFast))
            StatRow(icon: "arrow.up.circle", title: "Maximum", value: String(format: "%.1f dB", recording.peakLevel))
            StatRow(icon: "arrow.down.circle", title: "Minimum", value: String(format: "%.1f dB", recording.minLevel))
            StatRow(icon: "clock", title: "Dauer", value: recording.formattedDuration)
        }
        .padding()
        .glassCard(cornerRadius: 14)
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Konfiguration")
                .font(.headline)
            Divider()
            StatRow(icon: "gauge", title: "Zeitbewertung", value: recording.timeWeighting)
            StatRow(icon: "slider.horizontal.3", title: "Frequenzbewertung", value: recording.frequencyWeighting)
            StatRow(icon: "music.note", title: "Samplerate", value: "\(Int(recording.sampleRate)) Hz")
            StatRow(icon: "hammer", title: "FFT", value: "\(recording.fftBlockSize)")
            StatRow(icon: "ruler", title: "Kalibrierung", value: String(format: "%.1f dB", recording.calibrationOffset))
        }
        .padding()
        .glassCard(cornerRadius: 14)
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notizen")
                .font(.headline)
            Divider()
            TextEditor(text: Binding(
                get: { recording.description },
                set: { newValue in
                    recording.description = newValue
                    recordingManager.updateRecording(recording)
                }
            ))
            .font(.body)
            .foregroundColor(recording.description.isEmpty ? .secondary : .primary)
            .frame(minHeight: 72)
            .overlay(alignment: .topLeading) {
                if recording.description.isEmpty {
                    Text("Notizen hinzufügen…")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding()
        .glassCard(cornerRadius: 14)
    }

    @ViewBuilder
    private func photoThumbnail(fileName: String) -> some View {
        let url = recordingManager.getPhotoURL(fileName: fileName)
        ZStack(alignment: .topTrailing) {
            if let uiImage = UIImage(contentsOfFile: url.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 90, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 90, height: 90)
                    .overlay(Image(systemName: "photo").foregroundColor(.gray))
            }
            Button {
                recordingManager.deletePhoto(fileName: fileName)
                recording.photoFileNames.removeAll { $0 == fileName }
                recordingManager.updateRecording(recording)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.5), in: Circle())
            }
            .padding(4)
        }
    }

    private var photosCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fotos")
                    .font(.headline)
                Spacer()
                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Hinzufügen", systemImage: "plus")
                        .font(.caption)
                }
            }
            Divider()
            if recording.photoFileNames.isEmpty {
                Text("Keine Fotos")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(recording.photoFileNames, id: \.self) { fileName in
                            photoThumbnail(fileName: fileName)
                        }
                    }
                }
            }
        }
        .padding()
        .glassCard(cornerRadius: 14)
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView(isPresented: $showPhotoPicker) { imageData in
                guard let data = imageData else { return }
                if let fileName = try? recordingManager.savePhoto(data, recordingID: recording.id) {
                    recording.photoFileNames.append(fileName)
                    recordingManager.updateRecording(recording)
                }
            }
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
                }

            Text("Ende: \(formatTime(analysisEndTime))")
                .font(.caption)
            Slider(value: $analysisEndTime, in: 0...max(duration, 0.1))
                .onChange(of: analysisEndTime) { _, newValue in
                    if newValue < analysisStartTime {
                        analysisStartTime = newValue
                    }
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

    private func metricsTableCard(provider: StoredDataProvider) -> some View {
        let range = analysisStartTime...analysisEndTime
        let effectiveMetrics = selectedMetrics.isEmpty ? Set(provider.metricKeys.prefix(6)) : selectedMetrics
        let orderedMetrics = Array(effectiveMetrics).sorted()
        let rows = provider.rows(in: range, step: 4)
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
            storedDataProvider?.pause()
        } else {
            audioPlayer.play()
            storedDataProvider?.play()
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
        recordingManager.updateRecording(recording)
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

    private func loadStoredMeasurementDataIfAvailable() {
        // Cancel any in-flight load before kicking off a new one (e.g. when the
        // view reappears after a fast push/pop).
        spectrogramLoadTask?.cancel()

        guard let measurementURL = recordingManager.measurementURL(for: recording),
              FileManager.default.fileExists(atPath: measurementURL.path) else {
            loadSpectrogramHistoryFallback()
            return
        }

        let maxOverviewFrames = Self.maxStoredSpectrogramOverviewFrames
        isLoadingSpectrogram = true
        spectrogramLoadTask = Task.detached(priority: .userInitiated) {
            let result: Result<(StoredDataProvider, [[Float]]), Error>
            do {
                let provider = try StoredDataProvider(fileURL: measurementURL)
                let window = try await provider.spectrogramOverview(maxFrameCount: maxOverviewFrames)
                result = .success((provider, window.bins))
            } catch {
                result = .failure(error)
            }
            if Task.isCancelled { return }
            await MainActor.run {
                guard !Task.isCancelled else {
                    isLoadingSpectrogram = false
                    return
                }
                switch result {
                case .success(let (provider, visualHistory)):
                    storedDataProvider = provider
                    hasMeasurementData = true
                    rawSpectrogramHistory = visualHistory
                    weightedSpectrogramCache.removeAll()
                    applyPlaybackWeighting(playbackWeighting)
                    if selectedMetrics.isEmpty {
                        selectedMetrics = Set(provider.metricKeys.prefix(6))
                    }
                    analysisEndTime = max(analysisEndTime, provider.duration)
                    isLoadingSpectrogram = false
                case .failure(let error):
                    print("[RecordingDetailView] Failed to load stored measurement data: \(error)")
                    isLoadingSpectrogram = false
                    loadSpectrogramHistoryFallback()
                }
            }
        }
    }

    private func loadSpectrogramHistoryFallback() {
        spectrogramLoadTask?.cancel()
        let url = recordingManager.url(for: recording)
        let calibrationOffset = recording.calibrationOffset
        isLoadingSpectrogram = true
        spectrogramLoadTask = Task.detached(priority: .userInitiated) {
            let result = Result { try computeSpectrogramHistoryStreaming(url: url, calibrationOffset: calibrationOffset) }
            if Task.isCancelled { return }
            await MainActor.run {
                guard !Task.isCancelled else {
                    isLoadingSpectrogram = false
                    return
                }
                switch result {
                case .success(let history):
                    rawSpectrogramHistory = history
                    weightedSpectrogramCache.removeAll()
                    applyPlaybackWeighting(playbackWeighting)
                case .failure:
                    break
                }
                isLoadingSpectrogram = false
            }
        }
    }

    private func createCSVExport() {
        guard activeExportKind == nil else { return }
        guard let measurementURL = recordingManager.measurementURL(for: recording) else {
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
        let audioURL = recordingManager.url(for: recording)
        let measurementURL = recordingManager.measurementURL(for: recording)
        let photoURLs = recording.photoFileNames.map { recordingManager.getPhotoURL(fileName: $0) }

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
        let audioURL = recordingManager.url(for: recording)
        let recordingID = recording.id.uuidString
        isExportingSpectrogram = true
        spectrogramExportTask = Task.detached(priority: .userInitiated) {
            let result = Result { try SpectrogramImageExporter().export(audioURL: audioURL, recordingID: recordingID) }
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

    private func shareRawMeasurementData() {
        guard let measurementURL = recordingManager.measurementURL(for: recording),
              FileManager.default.fileExists(atPath: measurementURL.path) else { return }
        shareItems = [measurementURL]
        showShareSheet = true
    }

    private func reloadRecordingState() {
        if let updated = recordingManager.recordings.first(where: { $0.id == recording.id }) {
            recording = updated
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func rebuildWaterfallDataSet() {
        guard let firstColumn = spectrogramHistory.first, !firstColumn.isEmpty else {
            waterfallDataSet = WaterfallDataSet(slices: [], frequencies: [], duration: 0, minDB: Float(waterfallMinDB), maxDB: Float(waterfallMaxDB))
            return
        }

        let minDB = Float(min(waterfallMinDB, waterfallMaxDB - 5))
        let maxDB = Float(max(waterfallMaxDB, waterfallMinDB + 5))
        let duration = max(audioPlayer.duration, recording.duration, storedDataProvider?.duration ?? 0)
        let sourceFrequencies = WaterfallDataBuilder.sourceFrequencies(
            binCount: firstColumn.count,
            sampleRate: storedDataProvider?.sampleRate ?? recording.sampleRate,
            storedProviderHasFullFFT: storedDataProvider?.hasFullFFT == true && firstColumn.count == storedDataProvider?.fftBinCount
        )

        waterfallDataSet = WaterfallDataBuilder.build(
            history: spectrogramHistory,
            sourceFrequencies: sourceFrequencies,
            duration: duration,
            targetSliceCount: Int(waterfallSliceCount),
            minDB: minDB,
            maxDB: maxDB
        )
    }

    nonisolated private func computeSpectrogramHistoryStreaming(url: URL, calibrationOffset: Float) throws -> [[Float]] {
        let fftSize = 4096
        let hopSize = 512
        let frequencyBins = 1024
        let chunkFrames = fftSize * 8

        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat

        guard let dct = vDSP.DCT(count: fftSize, transformType: .II) else { return [] }

        let window = WindowFunction.hann.generate(size: fftSize)
        var windowed = [Float](repeating: 0, count: fftSize)
        var coefficients = [Float](repeating: 0, count: fftSize)
        var magnitudes = [Float](repeating: 0, count: fftSize)

        var history: [[Float]] = []
        var overlap = [Float]()

        while audioFile.framePosition < audioFile.length {
            let remaining = audioFile.length - audioFile.framePosition
            let toRead = AVAudioFrameCount(min(Int64(chunkFrames), remaining))

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: toRead),
                  (try? audioFile.read(into: buffer)) != nil,
                  let channelData = buffer.floatChannelData else { break }

            let frameLength = Int(buffer.frameLength)
            let samples = overlap + Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

            var offset = 0
            while offset + fftSize <= samples.count {
                samples.withUnsafeBufferPointer { ptr in
                    vDSP_vmul(ptr.baseAddress! + offset, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
                }

                dct.transform(windowed, result: &coefficients)
                vDSP_vabs(coefficients, 1, &magnitudes, 1, vDSP_Length(fftSize))
                var scale = 2.0 / Float(fftSize)
                vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(fftSize))

                let minFreq: Float = 20.0
                let nyquist = Float(format.sampleRate) / 2.0
                let maxFreq: Float = min(nyquist, 20_000.0)
                let denomBins = Float(max(frequencyBins - 1, 1))
                let denomSrc = Float(max(magnitudes.count - 1, 1))
                var column = [Float](repeating: -120.0, count: frequencyBins)
                for i in 0..<frequencyBins {
                    let t = Float(i) / denomBins
                    let frequency = minFreq * powf(maxFreq / minFreq, t)
                    let srcIndex = min(magnitudes.count - 1, max(0, Int((frequency / nyquist) * denomSrc)))
                    column[i] = 20.0 * log10(magnitudes[srcIndex] + 1e-10) + calibrationOffset
                }

                history.append(column)
                offset += hopSize
            }

            overlap = offset < samples.count ? Array(samples[offset..<samples.count]) : []
        }

        return history
    }

    private func applyPlaybackWeighting(_ weighting: FrequencyWeighting) {
        guard !rawSpectrogramHistory.isEmpty else {
            spectrogramHistory = []
            return
        }

        if weighting != .z,
           shouldPromoteSpectrogramResolution(),
           !isPromotingSpectrogramResolution {
            promoteSpectrogramResolutionThenApply(weighting)
            return
        }

        if weighting == .z {
            spectrogramHistory = rawSpectrogramHistory
            return
        }

        if let cached = weightedSpectrogramCache[weighting] {
            spectrogramHistory = cached
            return
        }

        let binCount = rawSpectrogramHistory.first?.count ?? storedDataProvider?.fftBinCount ?? 0
        let sampleRate = storedDataProvider?.sampleRate ?? recording.sampleRate
        guard binCount > 0 else {
            spectrogramHistory = rawSpectrogramHistory
            return
        }

        let fftSize = binCount * 2
        let processor = FrequencyWeightingProcessor(fftSize: fftSize, sampleRate: sampleRate)
        let nyquist = Float(sampleRate / 2.0)
        let frequencies = (0..<binCount).map { Float($0) * nyquist / Float(binCount) }
        let source = rawSpectrogramHistory

        weightingTask?.cancel()
        weightingTask = Task.detached(priority: .userInitiated) {
            var weightedHistory: [[Float]] = []
            weightedHistory.reserveCapacity(source.count)
            for column in source {
                weightedHistory.append(
                    processor.applyWeighting(to: column, frequencies: frequencies, weighting: weighting)
                )
            }
            if Task.isCancelled { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                weightedSpectrogramCache[weighting] = weightedHistory
                if playbackWeighting == weighting {
                    spectrogramHistory = weightedHistory
                }
            }
        }
    }

    private func shouldPromoteSpectrogramResolution() -> Bool {
        guard let first = rawSpectrogramHistory.first else { return false }
        if first.count > MeasurementDataFormat.thirdOctaveBandCount {
            return false
        }
        if let provider = storedDataProvider, provider.hasFullFFT {
            return false
        }
        return true
    }

    private func promoteSpectrogramResolutionThenApply(_ weighting: FrequencyWeighting) {
        spectrogramLoadTask?.cancel()
        isPromotingSpectrogramResolution = true
        let audioURL = recordingManager.url(for: recording)
        let calibrationOffset = recording.calibrationOffset
        spectrogramLoadTask = Task.detached(priority: .userInitiated) {
            let result = Result { try computeSpectrogramHistoryStreaming(url: audioURL, calibrationOffset: calibrationOffset) }
            if Task.isCancelled { return }
            await MainActor.run {
                guard !Task.isCancelled else {
                    isPromotingSpectrogramResolution = false
                    return
                }
                switch result {
                case .success(let history):
                    rawSpectrogramHistory = history
                    weightedSpectrogramCache.removeAll()
                    isPromotingSpectrogramResolution = false
                    applyPlaybackWeighting(weighting)
                case .failure:
                    isPromotingSpectrogramResolution = false
                    spectrogramHistory = rawSpectrogramHistory
                }
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
