import AVFoundation
import SwiftUI

struct AudioExportSheet: View {
    let source: AudioAsset
    let recipe: AudioEditRecipe
    let sourceSampleRate: Double
    let sourceChannels: Int
    let onFinishedReplacingOriginal: (Recording) -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var options = AudioExportOptions()
    @State private var isExporting = false
    @State private var progress: Double = 0
    @State private var exportTask: Task<Void, Never>?
    @State private var exportedShareURL: URL?
    @State private var showShareSheet = false
    @State private var showReplaceConfirmation = false
    @State private var errorMessage: String?
    @State private var statusBanner: String?

    init(
        source: AudioAsset,
        recipe: AudioEditRecipe,
        sourceSampleRate: Double,
        sourceChannels: Int,
        onFinishedReplacingOriginal: @escaping (Recording) -> Void = { _ in }
    ) {
        self.source = source
        self.recipe = recipe
        self.sourceSampleRate = sourceSampleRate
        self.sourceChannels = sourceChannels
        self.onFinishedReplacingOriginal = onFinishedReplacingOriginal
        _options = State(initialValue: AudioExportOptions(
            format: .m4aAAC,
            pcmBitDepth: 16,
            bitrateKbps: 192,
            useVBR: false,
            targetSampleRate: nil,
            downmixToMono: false,
            title: source.displayTitle
        ))
    }

    private var estimatedSizeString: String {
        let bytes = options.estimatedByteSize(
            duration: recipe.effectiveDuration,
            sourceSampleRate: sourceSampleRate,
            sourceChannels: sourceChannels
        )
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Zielformat") {
                    Picker("Format", selection: $options.format) {
                        ForEach(AudioExportFormat.allCases) { fmt in
                            Text(fmt.displayName).tag(fmt)
                        }
                    }
                    Text(options.format.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Qualität & Parameter") {
                    if options.format.supportsBitrate {
                        Picker("Bitrate", selection: $options.bitrateKbps) {
                            Text("128 kbps").tag(128)
                            Text("192 kbps").tag(192)
                            Text("256 kbps").tag(256)
                            Text("320 kbps").tag(320)
                        }
                        if options.format == .mp3 {
                            Toggle("Variable Bitrate (VBR)", isOn: $options.useVBR)
                        }
                    }

                    if options.format.supportsBitDepth {
                        Picker("Bittiefe", selection: $options.pcmBitDepth) {
                            Text("16-Bit PCM").tag(16)
                            Text("24-Bit PCM").tag(24)
                        }
                    }

                    Picker("Abtastrate", selection: Binding(
                        get: { options.targetSampleRate ?? 0 },
                        set: { options.targetSampleRate = ($0 == 0) ? nil : $0 }
                    )) {
                        Text("Original (\(Int(sourceSampleRate)) Hz)").tag(0.0)
                        Text("44,1 kHz").tag(44100.0)
                        Text("48 kHz").tag(48000.0)
                    }

                    Toggle("Mono-Downmix", isOn: $options.downmixToMono)

                    HStack {
                        Text("Geschätzte Größe")
                        Spacer()
                        Text("≈ \(estimatedSizeString)")
                            .font(.readout(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if let statusBanner {
                    Section {
                        Label(statusBanner, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(FerriteStatus.live)
                    }
                }

                Section("Aktionen") {
                    Button {
                        startExport(mode: .share)
                    } label: {
                        Label("Exportieren & Teilen", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isExporting)
                    .accessibilityIdentifier("audioExportShareButton")

                    if source.recordingID != nil {
                        Button {
                            startExport(mode: .saveAsCopy)
                        } label: {
                            Label("Als neue Kopie speichern", systemImage: "doc.on.doc.fill")
                        }
                        .disabled(isExporting)
                        .accessibilityIdentifier("audioExportSaveCopyButton")

                        Button(role: .destructive) {
                            showReplaceConfirmation = true
                        } label: {
                            Label("Original ersetzen", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(isExporting)
                    } else {
                        Button {
                            startExport(mode: .importIntoRecordings)
                        } label: {
                            Label("In Aufnahmen importieren", systemImage: "tray.and.arrow.down")
                        }
                        .disabled(isExporting)
                    }
                }
            }
            .polishedFormChrome()
            .navigationTitle("Export & Konvertierung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        exportTask?.cancel()
                        dismiss()
                    }
                }
            }
            .overlay {
                if isExporting {
                    VStack(spacing: 14) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(width: 220)
                        Text("Wird konvertiert (\(Int(progress * 100))%)…")
                            .font(.subheadline.weight(.medium))
                        Button("Abbrechen", role: .cancel) {
                            exportTask?.cancel()
                            isExporting = false
                        }
                    }
                    .padding(24)
                    .glassCard(cornerRadius: Radius.card)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedShareURL {
                    ActivityView(activityItems: [url])
                }
            }
            .alert("Originaldatei ersetzen?", isPresented: $showReplaceConfirmation) {
                Button("Abbrechen", role: .cancel) {}
                Button("Ersetzen", role: .destructive) {
                    startExport(mode: .replaceOriginal)
                }
            } message: {
                Text("Die bearbeitete Audiodatei überschreibt das Original. Kalibrierte .spekto-Messdaten werden abgekoppelt, da Zeit- oder Filteränderungen den Bezug verändern.")
            }
            .alert("Fehler", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .accessibilityIdentifier("audioExportSheet")
    }

    private enum ExportActionMode {
        case share
        case saveAsCopy
        case replaceOriginal
        case importIntoRecordings
    }

    private func startExport(mode: ExportActionMode) {
        exportTask?.cancel()
        isExporting = true
        progress = 0
        statusBanner = nil

        let sourceURL = source.fileURL
        let currentOptions = options
        let currentRecipe = recipe

        exportTask = Task {
            do {
                let outputURL = try await AudioFormatConverter.renderAndConvert(
                    sourceURL: sourceURL,
                    recipe: currentRecipe,
                    options: currentOptions
                ) { p in
                    Task { @MainActor in
                        self.progress = p
                    }
                }

                let fileInfo = try? AVAudioFile(forReading: outputURL)
                let outRate = fileInfo?.processingFormat.sampleRate ?? (currentOptions.targetSampleRate ?? sourceSampleRate)
                let outChannels = Int(fileInfo?.processingFormat.channelCount ?? UInt32(currentOptions.downmixToMono ? 1 : sourceChannels))
                let outDuration = fileInfo.map { Double($0.length) / max(1, $0.processingFormat.sampleRate) } ?? currentRecipe.effectiveDuration

                await MainActor.run {
                    isExporting = false
                    switch mode {
                    case .share:
                        exportedShareURL = outputURL
                        showShareSheet = true
                    case .saveAsCopy:
                        if let rec = services.recordingManager.recording(for: source) {
                            let saved = services.recordingManager.saveEditedCopy(
                                from: rec,
                                editedAudioURL: outputURL,
                                duration: outDuration,
                                sampleRate: outRate,
                                channelCount: outChannels
                            )
                            statusBanner = saved != nil ? "Als neue Kopie gespeichert." : nil
                            if saved == nil { errorMessage = "Kopie konnte nicht gespeichert werden." }
                        } else {
                            errorMessage = "Quelle ist nicht in Aufnahmen gespeichert."
                        }
                    case .replaceOriginal:
                        if let rec = services.recordingManager.recording(for: source) {
                            if let updated = services.recordingManager.replaceAudio(
                                for: rec,
                                with: outputURL,
                                duration: outDuration,
                                sampleRate: outRate,
                                channelCount: outChannels
                            ) {
                                onFinishedReplacingOriginal(updated)
                                statusBanner = "Original aktualisiert."
                                dismiss()
                            } else {
                                errorMessage = "Original konnte nicht ersetzt werden."
                            }
                        } else {
                            errorMessage = "Quelle ist nicht in Aufnahmen gespeichert."
                        }
                    case .importIntoRecordings:
                        let imported = services.recordingManager.importExternalAudio(
                            url: outputURL,
                            title: currentOptions.title.isEmpty ? source.displayTitle : currentOptions.title,
                            duration: outDuration,
                            sampleRate: outRate,
                            channelCount: outChannels
                        )
                        statusBanner = imported != nil ? "In Aufnahmen importiert." : nil
                        if imported == nil { errorMessage = "Import fehlgeschlagen." }
                    }
                }
            } catch is CancellationError {
                await MainActor.run { isExporting = false }
            } catch {
                await MainActor.run {
                    isExporting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
