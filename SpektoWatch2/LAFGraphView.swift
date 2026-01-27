import SwiftUI

struct LAFGraphView: View {
    @ObservedObject var audioEngine: AudioEngine
    var timeSpan: SpectrogramTimeSpan
    var scrollSpeed: ScrollSpeed
    var isPaused: Bool
    var scrollOffset: Float
    
    let dbOffset: Float = 100.0
    
    @State private var levelBuffer: [Float] = []
    @State private var writeIndex: Int = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black)
                
                Canvas { context, size in
                    guard !levelBuffer.isEmpty else { return }
                    
                    let width = size.width
                    let height = size.height
                    let count = levelBuffer.count
                    
                    // Scale: 0 dB (bottom) to 100 dB (top) Absolute
                    let minDB: Float = 0.0
                    let maxDB: Float = 100.0
                    let range = maxDB - minDB
                    
                    var path = Path()
                    
                    let offsetSamples = Int(scrollOffset * Float(count))
                    
                    for i in 0..<count {
                        let x = width * CGFloat(i) / CGFloat(count - 1)
                        
                        // Ring buffer index
                        let index = (writeIndex + offsetSamples - i + 2 * count) % count
                        let level = levelBuffer[index]
                        let absLevel = level + dbOffset
                        let clampedLevel = max(minDB, min(maxDB, absLevel))
                        
                        // Map level to height
                        let normalized = CGFloat((clampedLevel - minDB) / range)
                        let y = height * (1.0 - normalized)
                        
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    
                    // Stroke
                    context.stroke(path, with: .color(.white), lineWidth: 2.0)
                    
                    // Fill (Gradient)
                    var fillPath = path
                    fillPath.addLine(to: CGPoint(x: width, y: height))
                    fillPath.addLine(to: CGPoint(x: 0, y: height))
                    fillPath.closeSubpath()
                    
                    let gradient = Gradient(colors: [.white.opacity(0.3), .white.opacity(0.0)])
                    context.fill(fillPath, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: height)))
                }
            }.drawingGroup() // Metal acceleration
        }
        .onReceive(audioEngine.$currentSpectrogramData) { data in
            guard let data = data, !isPaused else { return }
            updateLevelBuffer(level: data.broadbandLevel)
        }
        .onChange(of: timeSpan) { _, _ in resetBuffer() }
        .onChange(of: scrollSpeed) { _, _ in resetBuffer() }
        .onAppear { resetBuffer() }
    }
    
    private func resetBuffer() {
        let updateRate = 44100.0 / Double(scrollSpeed.rawValue)
        let columns = Int(Double(timeSpan.rawValue) * updateRate)
        let safeColumns = max(10, columns)
        levelBuffer = [Float](repeating: -120.0, count: safeColumns)
        writeIndex = 0
    }
    
    private func updateLevelBuffer(level: Float) {
        guard !levelBuffer.isEmpty else { return }
        writeIndex = (writeIndex + 1) % levelBuffer.count
        let safeLevel = level.isNaN || level.isInfinite ? -120.0 : level
        levelBuffer[writeIndex] = safeLevel
    }
}