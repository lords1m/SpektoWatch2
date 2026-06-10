import SwiftUI

/// Waterfall tab content for `RecordingDetailView`.
struct RecordingWaterfallSection: View {
    @ObservedObject var controller: WaterfallPlaybackController
    @Binding var playbackWeighting: FrequencyWeighting
    var isLoadingSpectrogram: Bool
    var isPromotingResolution: Bool
    var spectrogramHistoryEmpty: Bool
    var usesAudioSpectralFallback: Bool
    var highlightedTime: TimeInterval?
    var autoFitToastText: String?
    var onDisplaySettingsChanged: () -> Void
    var onAutoFitDBRange: () -> Void

    /// Render-only overlays — local to the analysis surface, no rebuild needed.
    @State private var showPeaks = true
    @State private var showStatistics = true

    /// Taller surface than the old fixed 360 so the heatmap is genuinely
    /// bigger and the colorbar / peak panel have room.
    private static let waterfallHeight: CGFloat = 460

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if usesAudioSpectralFallback {
                spectralFallbackBanner
            }
            waterfallCard
            waterfallControlsCard
        }
    }

    private var spectralFallbackBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform.badge.exclamationmark")
                .foregroundStyle(.orange)
            Text("Spektraldaten stammen aus der Audio-Datei, nicht aus der Messaufzeichnung. Frequenzbewertung A/C kann abweichen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var waterfallCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Wasserfall")
                    .font(.headline)
                Spacer()
                weightingPicker
                    .frame(maxWidth: 280)
            }

            ZStack {
                WaterfallView(
                    dataSet: controller.dataSet,
                    highlightedTime: highlightedTime,
                    options: .analysis(
                        spectrumMode: controller.display.spectrumMode,
                        showPeaks: showPeaks,
                        showStatistics: showStatistics
                    )
                )
                .frame(maxWidth: .infinity)
                .frame(height: Self.waterfallHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("recordingWaterfallView")

                if isLoadingSpectrogram || controller.isBuilding {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                    ProgressView(isLoadingSpectrogram ? "Spektrum wird geladen…" : "Wasserfall wird aufbereitet…")
                        .tint(.white)
                        .foregroundStyle(.white)
                } else if spectrogramHistoryEmpty {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black)
                    Text("Keine Wasserfall-Daten")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: Self.waterfallHeight)

            HStack {
                Text("\(controller.dataSet.slices.count) Zeitabschnitte")
                Spacer()
                Text("\(Int(controller.dataSet.minDB))…\(Int(controller.dataSet.maxDB)) dB SPL")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .glassCard(cornerRadius: 14)
    }

    private var weightingPicker: some View {
        HStack(spacing: 8) {
            Text("Bewertung")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("Frequenzbewertung", selection: $playbackWeighting) {
                ForEach(FrequencyWeighting.allCases, id: \.self) { weighting in
                    Text(weighting.rawValue).tag(weighting)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            if isPromotingResolution {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
    }

    private var waterfallControlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Darstellung")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Zeitscheiben: \(controller.display.sliceCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(controller.display.sliceCount) },
                        set: {
                            controller.display.sliceCount = Int($0)
                            onDisplaySettingsChanged()
                        }
                    ),
                    in: 32...160,
                    step: 8
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Spektrum")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Spektrum", selection: Binding(
                    get: { controller.display.spectrumMode },
                    set: {
                        controller.display.spectrumMode = $0
                        onDisplaySettingsChanged()
                    }
                )) {
                    ForEach(WaterfallSpectrumMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Toggle("Spitzen anzeigen", isOn: $showPeaks)
            Toggle("Statistik (Max-Hold / Ø)", isOn: $showStatistics)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Min: \(Int(controller.display.minDB)) dB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(controller.display.minDB) },
                            set: {
                                controller.display.minDB = Float($0)
                                onDisplaySettingsChanged()
                            }
                        ),
                        in: 0...90,
                        step: 5
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Max: \(Int(controller.display.maxDB)) dB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(controller.display.maxDB) },
                            set: {
                                controller.display.maxDB = Float($0)
                                onDisplaySettingsChanged()
                            }
                        ),
                        in: 60...140,
                        step: 5
                    )
                }
            }

            Button {
                onAutoFitDBRange()
            } label: {
                Label("dB-Bereich automatisch anpassen", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            if let autoFitToastText {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(autoFitToastText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .glassCard(cornerRadius: 14)
    }
}
