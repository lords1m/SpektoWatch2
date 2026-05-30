import SwiftUI
import Combine

struct SpectrogramWidget: View {
    private let audioEngine: AudioEngine
    var settings: [String: String]

    private let scrollSpeedPublisher: Published<ScrollSpeed>.Publisher
    private let frequencyWeightingPublisher: Published<FrequencyWeighting>.Publisher
    private let spectrogramFrequencySmoothingPublisher: Published<Float>.Publisher
    private let engineStatusPublisher: Published<EngineStatus>.Publisher

    @State private var engineScrollSpeed: ScrollSpeed
    @State private var engineFrequencyWeighting: String
    @State private var engineSpectrogramFrequencySmoothing: Float
    @State private var engineStatus: EngineStatus

    init(audioEngine: AudioEngine, settings: [String: String]) {
        self.audioEngine = audioEngine
        self.settings = settings
        self.scrollSpeedPublisher = audioEngine.$scrollSpeed
        self.frequencyWeightingPublisher = audioEngine.$frequencyWeighting
        self.spectrogramFrequencySmoothingPublisher = audioEngine.$spectrogramFrequencySmoothing
        self.engineStatusPublisher = audioEngine.$engineStatus
        _engineScrollSpeed = State(initialValue: audioEngine.scrollSpeed)
        _engineFrequencyWeighting = State(initialValue: audioEngine.frequencyWeighting.rawValue)
        _engineSpectrogramFrequencySmoothing = State(initialValue: audioEngine.spectrogramFrequencySmoothing)
        _engineStatus = State(initialValue: audioEngine.engineStatus)
    }

    private var useWidgetOverrides: Bool { WidgetSettings.usesWidgetOverrides(settings) }
    var colormapType: Int {
        let fallback = String(WidgetSettings.defaultSpectrogramColormap)
        guard useWidgetOverrides else {
            return WidgetSettings.defaultSpectrogramColormap
        }
        return Int(settings["colormap"] ?? fallback) ?? WidgetSettings.defaultSpectrogramColormap
    }
    var timeSpan: SpectrogramTimeSpan {
        let fallback = WidgetSettings.defaultTimeSpanSeconds
        guard useWidgetOverrides else {
            return SpectrogramTimeSpan(rawValue: fallback) ?? .seconds5
        }
        let raw = Int(settings["timeSpan"] ?? String(fallback)) ?? fallback
        return SpectrogramTimeSpan(rawValue: raw) ?? SpectrogramTimeSpan(rawValue: fallback) ?? .seconds5
    }
    var scrollSpeed: ScrollSpeed { engineScrollSpeed }
    var freqWeighting: String {
        if useWidgetOverrides {
            return settings["freqWeighting"] ?? engineFrequencyWeighting
        }
        return engineFrequencyWeighting
    }
    var sensitivity: Float {
        guard useWidgetOverrides else {
            return WidgetSettings.defaultSpectrogramSensitivity
        }
        return Float(settings["sensitivity"] ?? String(Int(WidgetSettings.defaultSpectrogramSensitivity))) ?? WidgetSettings.defaultSpectrogramSensitivity
    }

    /// Per-widget frequency smoothing on top of the always-on baseline in
    /// `HighEndSpectrogramAdapter.applyFrequencySmoothingIfNeeded`. When the
    /// override toggle is off the widget reads the app-global value so the
    /// existing global slider keeps working as before.
    var frequencySmoothing: Float {
        guard useWidgetOverrides else {
            return engineSpectrogramFrequencySmoothing
        }
        let raw = settings["frequencySmoothing"] ?? "0.0"
        return Float(raw) ?? 0.0
    }

    var noiseFloor: Float { WidgetSettings.noiseFloorDB(settings) }

    @State private var showFullscreen = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HighEndSpectrogramAdapterWithAxes(
                audioEngine: audioEngine,
                colormapType: colormapType,
                timeSpan: timeSpan,
                scrollSpeed: scrollSpeed,
                isPaused: engineStatus != .running,
                freqWeighting: freqWeighting,
                sensitivity: sensitivity,
                frequencySmoothing: frequencySmoothing,
                noiseFloor: noiseFloor
            )

            Button { showFullscreen = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.black.opacity(0.5)))
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .padding(8)
        }
        .onReceive(scrollSpeedPublisher) { engineScrollSpeed = $0 }
        .onReceive(frequencyWeightingPublisher) { engineFrequencyWeighting = $0.rawValue }
        .onReceive(spectrogramFrequencySmoothingPublisher) { engineSpectrogramFrequencySmoothing = $0 }
        .onReceive(engineStatusPublisher) { engineStatus = $0 }
        .fullScreenCover(isPresented: $showFullscreen) {
            SpectrogramFullscreenView(
                audioEngine: audioEngine,
                colormapType: colormapType,
                timeSpan: timeSpan,
                scrollSpeed: scrollSpeed,
                freqWeighting: freqWeighting,
                sensitivity: sensitivity,
                frequencySmoothing: frequencySmoothing,
                noiseFloor: noiseFloor,
                engineStatus: engineStatus
            )
        }
    }
}

private struct SpectrogramFullscreenView: View {
    @Environment(\.dismiss) private var dismiss
    let audioEngine: AudioEngine
    let colormapType: Int
    let timeSpan: SpectrogramTimeSpan
    let scrollSpeed: ScrollSpeed
    let freqWeighting: String
    let sensitivity: Float
    let frequencySmoothing: Float
    let noiseFloor: Float
    let engineStatus: EngineStatus

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            HighEndSpectrogramAdapterWithAxes(
                audioEngine: audioEngine,
                colormapType: colormapType,
                timeSpan: timeSpan,
                scrollSpeed: scrollSpeed,
                isPaused: engineStatus != .running,
                freqWeighting: freqWeighting,
                sensitivity: sensitivity,
                frequencySmoothing: frequencySmoothing,
                noiseFloor: noiseFloor
            )
            .ignoresSafeArea()

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(12)
        }
    }
}
