import SwiftUI

struct SpectrogramWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    var settings: [String: String]
    
    var colormapType: Int { Int(settings["colormap"] ?? "0") ?? 0 }
    var timeSpan: SpectrogramTimeSpan { SpectrogramTimeSpan(rawValue: Int(settings["timeSpan"] ?? "5") ?? 5) ?? .seconds5 }
    var scrollSpeed: ScrollSpeed { .fast } // Could also be a setting
    
    var body: some View {
        HighEndSpectrogramAdapterWithAxes(
            audioEngine: audioEngine,
            colormapType: colormapType,
            timeSpan: timeSpan,
            scrollSpeed: scrollSpeed,
            isPaused: false,
            scrollOffset: 0.0
        )
    }
}