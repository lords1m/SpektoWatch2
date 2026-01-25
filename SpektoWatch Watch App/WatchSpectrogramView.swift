import SwiftUI

struct WatchSpectrogramView: View {
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @State private var frames: [[Float]] = []
    
    // Konfiguration für Watch-Display
    private let maxFrames = 60    // Ca. 6 Sekunden Historie (bei 10 FPS Update vom iPhone)
    private let displayBins = 40  // Reduzierte vertikale Auflösung für Performance/Lesbarkeit
    
    var body: some View {
        VStack(spacing: 4) {
            // Spektrogramm Canvas
            Canvas { context, size in
                let width = size.width
                let height = size.height
                let colWidth = width / CGFloat(maxFrames)
                let rowHeight = height / CGFloat(displayBins)
                
                for (t, magnitudes) in frames.enumerated() {
                    let x = CGFloat(t) * colWidth
                    
                    for (f, mag) in magnitudes.enumerated() {
                        // dB Normalisierung (-100 bis -10 dB)
                        let normalized = (mag + 100.0) / 90.0
                        
                        if normalized > 0.1 { // Noise Gate
                            let color = spectrogramColor(Double(normalized))
                            // Y invertieren (tiefste Frequenz unten)
                            let y = height - CGFloat(f + 1) * rowHeight
                            
                            let rect = CGRect(x: x, y: y, width: colWidth + 0.5, height: rowHeight + 0.5)
                            context.fill(Path(rect), with: .color(color))
                        }
                    }
                }
            }
            .background(Color.black)
            .cornerRadius(8)
            .frame(maxHeight: .infinity)
            
            // Status & Steuerung
            HStack {
                Circle()
                    .fill(connectivityManager.isReachable ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Spacer()
                
                // Aufnahme-Steuerung (sendet Befehl an iPhone)
                Button(action: {
                    connectivityManager.requestRecordingStart()
                }) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                }
                .frame(width: 30, height: 30)
                .background(Color.green.opacity(0.3))
                .clipShape(Circle())
                
                Button(action: {
                    connectivityManager.requestRecordingStop()
                }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12))
                }
                .frame(width: 30, height: 30)
                .background(Color.red.opacity(0.3))
                .clipShape(Circle())
            }
            .padding(.horizontal, 4)
            .frame(height: 30)
        }
        .onReceive(connectivityManager.$spectrogramData) { data in
            guard let data = data else { return }
            
            // Downsampling für Watch-Performance (Max-Pooling)
            let downsampled = downsample(data.magnitudes, targetCount: displayBins)
            
            frames.append(downsampled)
            if frames.count > maxFrames {
                frames.removeFirst()
            }
        }
    }
    
    private func downsample(_ data: [Float], targetCount: Int) -> [Float] {
        guard !data.isEmpty else { return Array(repeating: -120, count: targetCount) }
        let chunkSize = data.count / targetCount
        var result = [Float]()
        
        for i in 0..<targetCount {
            let start = i * chunkSize
            let end = min(start + chunkSize, data.count)
            // Max-Pooling um Peaks zu erhalten
            let maxVal = (start < end) ? (data[start..<end].max() ?? -120.0) : -120.0
            result.append(maxVal)
        }
        return result
    }
    
    private func spectrogramColor(_ value: Double) -> Color {
        // Turbo-ähnliche Colormap (Blau -> Grün -> Rot)
        let v = max(0, min(1, value))
        return Color(
            red: max(0, min(1, 4 * v - 2)),
            green: max(0, min(1, 2 - abs(4 * v - 2))),
            blue: max(0, min(1, 2 - 4 * v))
        )
    }
}