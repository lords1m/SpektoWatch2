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

    var body: some View {
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
        .onReceive(scrollSpeedPublisher) { engineScrollSpeed = $0 }
        .onReceive(frequencyWeightingPublisher) { engineFrequencyWeighting = $0.rawValue }
        .onReceive(spectrogramFrequencySmoothingPublisher) { engineSpectrogramFrequencySmoothing = $0 }
        .onReceive(engineStatusPublisher) { engineStatus = $0 }
        .onAppear {
            print("[SpectrogramWidget] View appeared with colormap: \(colormapType), timeSpan: \(timeSpan), sensitivity: \(sensitivity), override=\(useWidgetOverrides)")
        }
    }
}
