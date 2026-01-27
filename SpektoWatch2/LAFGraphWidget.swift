import SwiftUI

struct LAFGraphWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    var settings: [String: String]
    
    var timeSpan: SpectrogramTimeSpan { SpectrogramTimeSpan(rawValue: Int(settings["timeSpan"] ?? "5") ?? 5) ?? .seconds5 }
    
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
                timeSpan: timeSpan,
                scrollSpeed: .fast,
                isPaused: false,
                scrollOffset: 0.0
            )
            .cornerRadius(10)
        }
        .onAppear {
            print("[LAFGraphWidget] View appeared with timeSpan: \(timeSpan)")
        }
    }
}