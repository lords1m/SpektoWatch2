import SwiftUI

struct SpectrogramWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    var settings: [String: String]

    var colormapType: Int { Int(settings["colormap"] ?? "0") ?? 0 }
    var timeSpan: SpectrogramTimeSpan {
        let raw = Int(settings["timeSpan"] ?? "5") ?? 5
        return SpectrogramTimeSpan(rawValue: raw) ?? .seconds5
    }
    var scrollSpeed: ScrollSpeed { audioEngine.scrollSpeed }
    var freqWeighting: String { settings["freqWeighting"] ?? "Z" }
    var sensitivity: Float { Float(settings["sensitivity"] ?? "50") ?? 50.0 }

    var body: some View {
        HighEndSpectrogramAdapterWithAxes(
            audioEngine: audioEngine,
            colormapType: colormapType,
            timeSpan: timeSpan,
            scrollSpeed: scrollSpeed,
            isPaused: false,
            scrollOffset: 0.0,
            freqWeighting: freqWeighting,
            sensitivity: sensitivity
        )
        .onAppear {
            print("[SpectrogramWidget] View appeared with colormap: \(colormapType), timeSpan: \(timeSpan), sensitivity: \(sensitivity)")
        }
    }
}
