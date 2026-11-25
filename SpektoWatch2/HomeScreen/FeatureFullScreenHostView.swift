import SwiftUI

struct FeatureLauncherDestination: Identifiable, Equatable {
    let id: UUID
    let widget: WidgetConfiguration

    init(widget: WidgetConfiguration) {
        self.id = widget.id
        self.widget = widget
    }
}

struct FeatureFullScreenHostView: View {
    let destination: FeatureLauncherDestination
    let audioEngine: AudioEngine
    let fftConfig: FFTConfiguration
    @Binding var selectedMicrophoneSource: MicrophoneSource
    @Binding var watchGain: Float

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @AppStorage("design.colormap") private var designColormap: String = Colormap.viridis.rawValue

    private var widget: WidgetConfiguration { destination.widget }

    var body: some View {
        switch widget.type {
        case .audioEditor:
            AudioEditorLauncherView()
                .environment(services)
        case .recordings:
            RecordingsListView()
                .environment(services)
        case .settings:
            SettingsRootView(
                selectedMicrophoneSource: $selectedMicrophoneSource,
                watchGain: $watchGain,
                audioEngine: audioEngine
            )
            .environment(services)
        default:
            NavigationStack {
                launchedContent
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(GlassBackground().ignoresSafeArea())
                    .navigationTitle(widget.type.rawValue)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                dismiss()
                            } label: {
                                Label("Schließen", systemImage: "xmark.circle.fill")
                            }
                            .accessibilityIdentifier("featureLauncherCloseButton")
                        }
                    }
            }
            .accessibilityIdentifier("featureFullScreenHostView")
        }
    }

    @ViewBuilder
    private var launchedContent: some View {
        switch widget.type {
        case .spectrogram:
            let useOverrides = WidgetSettings.usesWidgetOverrides(widget.settings)
            let colormap = useOverrides
                ? (Int(widget.settings["colormap"] ?? "") ?? WidgetSettings.defaultSpectrogramColormap)
                : DesignColormap.metalRawValue(from: designColormap)
            let spanRaw = Int(widget.settings["timeSpan"] ?? "") ?? WidgetSettings.defaultTimeSpanSeconds
            let span = useOverrides ? (SpectrogramTimeSpan(rawValue: spanRaw) ?? .seconds5) : .seconds5
            let weighting = useOverrides
                ? (widget.settings["freqWeighting"] ?? audioEngine.frequencyWeighting.rawValue)
                : audioEngine.frequencyWeighting.rawValue
            let sensitivity = useOverrides
                ? (Float(widget.settings["sensitivity"] ?? "") ?? WidgetSettings.defaultSpectrogramSensitivity)
                : WidgetSettings.defaultSpectrogramSensitivity
            let smoothing = useOverrides
                ? (Float(widget.settings["frequencySmoothing"] ?? "") ?? 0.0)
                : audioEngine.spectrogramFrequencySmoothing

            InteractiveLiveSpectrogramView(
                audioEngine: audioEngine,
                colormapType: colormap,
                timeSpan: span,
                scrollSpeed: audioEngine.scrollSpeed,
                freqWeighting: weighting,
                sensitivity: sensitivity,
                frequencySmoothing: smoothing,
                noiseFloor: WidgetSettings.spectrogramNoiseFloorDB(widget.settings),
                engineStatus: audioEngine.engineStatus
            )
        case .levelHistory:
            LevelHistoryWidget(audioEngine: audioEngine, settings: widget.settings)
        case .frequencyDisplay, .octaveBands:
            FrequencySpectrumWidget(audioEngine: audioEngine, settings: widget.settings)
        case .levelMeter:
            LevelMeterWidget(audioEngine: audioEngine, settings: widget.settings)
        case .singleValue:
            SingleValueWidget(audioEngine: audioEngine, settings: widget.settings)
        case .toneGenerator:
            ToneGeneratorWidget()
        case .spektralanalyseLab:
            SpektralanalyseLaborWidget(fftConfig: fftConfig, audioEngine: audioEngine)
        case .waterfall:
            WaterfallWidget(audioEngine: audioEngine, settings: widget.settings)
        case .phaseMeter:
            PhaseMeterWidget(audioEngine: audioEngine)
        case .masking:
            if let maskingEngine = services.maskingEngine {
                MaskingEntryWidget(engine: maskingEngine)
            }
        case .audioEditor, .recordings, .settings:
            EmptyView()
        }
    }
}
