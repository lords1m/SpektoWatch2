import SwiftUI

struct SpectrogramWidget: View {
    private let audioEngine: AudioEngine
    var settings: [String: String]
    @AppStorage("design.colormap") private var designColormap: String = Colormap.viridis.rawValue

    init(audioEngine: AudioEngine, settings: [String: String]) {
        self.audioEngine = audioEngine
        self.settings = settings
    }

    private var useWidgetOverrides: Bool { WidgetSettings.usesWidgetOverrides(settings) }
    var colormapType: Int {
        let fallback = String(WidgetSettings.defaultSpectrogramColormap)
        if useWidgetOverrides {
            return Int(settings["colormap"] ?? fallback) ?? WidgetSettings.defaultSpectrogramColormap
        }
        return DesignColormap.metalRawValue(from: designColormap)
    }
    var timeSpan: SpectrogramTimeSpan {
        let fallback = WidgetSettings.defaultTimeSpanSeconds
        guard useWidgetOverrides else {
            return SpectrogramTimeSpan(rawValue: fallback) ?? .seconds5
        }
        let raw = Int(settings["timeSpan"] ?? String(fallback)) ?? fallback
        return SpectrogramTimeSpan(rawValue: raw) ?? SpectrogramTimeSpan(rawValue: fallback) ?? .seconds5
    }
    var scrollSpeed: ScrollSpeed { audioEngine.scrollSpeed }
    var freqWeighting: String {
        if useWidgetOverrides {
            return settings["freqWeighting"] ?? audioEngine.frequencyWeighting.rawValue
        }
        return audioEngine.frequencyWeighting.rawValue
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
            return audioEngine.spectrogramFrequencySmoothing
        }
        let raw = settings["frequencySmoothing"] ?? "0.0"
        return Float(raw) ?? 0.0
    }

    var noiseFloor: Float { WidgetSettings.spectrogramNoiseFloorDB(settings) }

    @State private var showFullscreen = false
    /// Shared so the fullscreen cover primes from (and continues) the same live
    /// scroll history instead of starting blank.
    @State private var columnHistory = SpectrogramColumnHistory()

    var body: some View {
        let engineStatus = audioEngine.engineStatus
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
                noiseFloor: noiseFloor,
                columnHistory: columnHistory
            )

            Button { showFullscreen = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.black.opacity(0.5)))
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Spektrogramm vergrößern")
            .padding(8)
        }
        .innerCanvas(cornerRadius: 0)
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
                engineStatus: engineStatus,
                columnHistory: columnHistory
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
    let columnHistory: SpectrogramColumnHistory

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            InteractiveLiveSpectrogramView(
                audioEngine: audioEngine,
                colormapType: colormapType,
                timeSpan: timeSpan,
                scrollSpeed: scrollSpeed,
                freqWeighting: freqWeighting,
                sensitivity: sensitivity,
                frequencySmoothing: frequencySmoothing,
                noiseFloor: noiseFloor,
                engineStatus: engineStatus,
                columnHistory: columnHistory
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 44)

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(12)
        }
    }
}
