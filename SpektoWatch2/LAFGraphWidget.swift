import SwiftUI

struct LAFGraphWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    
    var body: some View {
        HStack(spacing: 4) {
            // Y-Axis
            ZStack(alignment: .topTrailing) {
                Text("100")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .position(x: 17.5, y: 8)
                Text("0")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .position(x: 17.5, y: 142) // Approx bottom
            }
            .frame(width: 35)
            
            LAFGraphView(
                audioEngine: audioEngine,
                timeSpan: .seconds5,
                scrollSpeed: .fast,
                isPaused: false,
                scrollOffset: 0.0
            )
            .cornerRadius(10)
        }
    }
}