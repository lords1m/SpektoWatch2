import SwiftUI

struct LevelHistoryWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    var settings: [String: String]
    
    var metricLabel: String {
        "L\(settings["freqWeighting"] ?? "A")\(settings["timeWeighting"]?.prefix(1) ?? "F")"
    }
    
    var body: some View {
        HStack(spacing: 4) {
            // Y-Axis
            GeometryReader { geo in
                ZStack(alignment: .topTrailing) {
                    Text("100")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .position(x: 17.5, y: 8)
                    Text("50")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .position(x: 17.5, y: geo.size.height / 2)
                    Text("0")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .position(x: 17.5, y: geo.size.height - 8)
                }
            }
            .frame(width: 35)
            
            LevelHistoryView(
                audioEngine: audioEngine,
                settings: settings,
                scrollSpeed: .fast,
                isPaused: false,
                scrollOffset: 0.0
            )
            .cornerRadius(10)
            .overlay(Text(metricLabel).font(.caption).padding(4).background(Color.black.opacity(0.5)).cornerRadius(4).padding(4), alignment: .topLeading)
        }
    }
}