import SwiftUI

struct SpectrogramWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    
    // Default settings for the widget instance
    // In a full implementation, these would come from WidgetConfiguration.settings
    var colormapType: Int = 0
    var timeSpan: SpectrogramTimeSpan = .seconds5
    var scrollSpeed: ScrollSpeed = .fast
    
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