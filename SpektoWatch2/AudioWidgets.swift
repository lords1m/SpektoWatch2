import SwiftUI

// MARK: - Frequency Spectrum Widget
struct FrequencySpectrumWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    let dbOffset: Float = 100.0
    
    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let spectrum = audioEngine.currentSpectrum
            
            if spectrum.isEmpty {
                let text = Text("Warte auf Audio...").font(.caption).foregroundColor(.gray)
                context.draw(text, at: CGPoint(x: size.width/2, y: size.height/2))
                return
            }
            
            guard !spectrum.isEmpty else { return }
            
            // Layout
            let bottomPadding: CGFloat = 16
            let leftPadding: CGFloat = 24
            let graphWidth = width - leftPadding
            let graphHeight = height - bottomPadding
            
            // Draw background grid
            let path = Path { p in
                p.addRect(CGRect(x: 0, y: 0, width: width, height: height))
            }
            context.fill(path, with: .color(Color(UIColor.systemBackground)))
            
            // Draw Y-Axis (dB)
            let minDB: Float = 0.0
            let maxDB: Float = 100.0
            let range = maxDB - minDB
            
            let yLabels: [Float] = [100, 80, 60, 40, 20, 0]
            for db in yLabels {
                let normalizedVal = CGFloat((db - minDB) / range)
                let y = (1.0 - normalizedVal) * graphHeight
                
                var gridPath = Path()
                gridPath.move(to: CGPoint(x: leftPadding, y: y))
                gridPath.addLine(to: CGPoint(x: width, y: y))
                context.stroke(gridPath, with: .color(Color.gray.opacity(0.2)), lineWidth: 0.5)
                
                let text = Text("\(Int(db))").font(.system(size: 8)).foregroundColor(.gray)
                context.draw(text, at: CGPoint(x: leftPadding / 2, y: y))
            }
            
            // Draw bars
            // Downsample to ~100 bars for performance and look
            let barCount = 100
            let step = max(1, spectrum.count / barCount)
            let barWidth = graphWidth / CGFloat(barCount)
            
            for i in 0..<barCount {
                let idx = i * step
                if idx < spectrum.count {
                    // Max pooling for the bin
                    let endIdx = min(idx + step, spectrum.count)
                    let val = spectrum[idx..<endIdx].max() ?? -120.0
                    let absVal = val + dbOffset
                    
                    // Map dB to height (0dB to 100dB)
                    let normalized = CGFloat((absVal - minDB) / range)
                    let clamped = max(0, min(1, normalized))
                    
                    let barHeight = clamped * graphHeight
                    let x = leftPadding + CGFloat(i) * barWidth
                    let y = graphHeight - barHeight
                    
                    let barRect = CGRect(x: x, y: y, width: barWidth - 1, height: barHeight)
                    
                    // Color gradient based on height
                    let color: Color = clamped > 0.8 ? .red : (clamped > 0.6 ? .yellow : .green)
                    context.fill(Path(barRect), with: .color(color))
                }
            }
            
            // Draw X-Axis Labels (Linear Freq)
            let xLabels: [(String, CGFloat)] = [("0", 0.0), ("5k", 0.23), ("10k", 0.45), ("15k", 0.68), ("20k", 0.91)]
            
            for (label, normalizedX) in xLabels {
                let x = leftPadding + normalizedX * graphWidth
                let text = Text(label).font(.system(size: 8)).foregroundColor(.gray)
                context.draw(text, at: CGPoint(x: x, y: height - bottomPadding / 2))
            }
        }
        .drawingGroup() // Metal acceleration
        .onAppear {
            print("[FrequencySpectrumWidget] View appeared")
        }
    }
}

// MARK: - Level Meter Widget
struct LevelMeterWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    
    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text("L")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(width: 20)
                
                GeometryReader { geo in
                    let width = geo.size.width
                    let height = geo.size.height
                    
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                    
                    // Level Bar
                    let level = audioEngine.currentLevel // dB
                    let minDB: Float = -60.0
                    let maxDB: Float = 0.0
                    let norm = CGFloat((level - minDB) / (maxDB - minDB))
                    let clamped = max(0, min(1, norm))
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                        .frame(width: width * clamped)
                    
                    // Peak Hold (simplified)
                    let peak = audioEngine.currentPeakLevel
                    let peakNorm = CGFloat((peak - minDB) / (maxDB - minDB))
                    let peakClamped = max(0, min(1, peakNorm))
                    
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2, height: height)
                        .offset(x: width * peakClamped)
                }
            }
            .frame(height: 20)
            
            // Scale
            HStack {
                Spacer().frame(width: 20)
                HStack {
                    Text("-60").font(.caption2).foregroundColor(.gray)
                    Spacer()
                    Text("-30").font(.caption2).foregroundColor(.gray)
                    Spacer()
                    Text("0").font(.caption2).foregroundColor(.gray)
                }
            }
        }
        .padding(10)
        .background(Color(UIColor.systemBackground))
        .onAppear {
            print("[LevelMeterWidget] View appeared")
        }
    }
}

// MARK: - Octave Band Analyzer Widget
struct OctaveBandWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    
    let centerFreqs: [String] = [
        "20", "25", "31", "40", "50", "63", "80", "100", "125", "160", "200", "250", "315", "400", "500", "630", "800",
        "1k", "1.2", "1.6", "2k", "2.5", "3.1", "4k", "5k", "6.3", "8k", "10k", "12", "16k", "20k"
    ]
    
    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let bands = audioEngine.currentOctaveBands
            
            if audioEngine.currentSpectrum.isEmpty {
                let text = Text("Warte auf Audio...").font(.caption).foregroundColor(.gray)
                context.draw(text, at: CGPoint(x: size.width/2, y: size.height/2))
                return
            }
            
            let barWidth = width / CGFloat(bands.count)
            
            for (i, val) in bands.enumerated() {
                let minDB: Float = -90.0
                let maxDB: Float = -10.0
                let norm = CGFloat((val - minDB) / (maxDB - minDB))
                let clamped = max(0, min(1, norm))
                
                let barHeight = clamped * height
                let x = CGFloat(i) * barWidth
                let y = height - barHeight
                
                // 3D Effect: Front face
                let barRect = CGRect(x: x + 1, y: y, width: barWidth - 2, height: barHeight)
                context.fill(Path(barRect), with: .color(.blue.opacity(0.8)))
                
                // Top highlight
                let topRect = CGRect(x: x + 1, y: y, width: barWidth - 2, height: 2)
                context.fill(Path(topRect), with: .color(.white.opacity(0.5)))
            }
            
            // Draw Labels (every 3rd)
            for i in stride(from: 0, to: centerFreqs.count, by: 3) {
                let x = CGFloat(i) * barWidth + barWidth / 2
                let text = Text(centerFreqs[i]).font(.system(size: 8)).foregroundColor(.gray)
                context.draw(text, at: CGPoint(x: x, y: height - 10))
            }
        }
        .drawingGroup()
        .onAppear {
            print("[OctaveBandWidget] View appeared")
        }
    }
}

// MARK: - Phase Meter Widget
struct PhaseMeterWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    
    var body: some View {
        HStack {
            // Correlation Bar
            VStack {
                Text("Korrelation")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                GeometryReader { geo in
                    let width = geo.size.width
                    let height = geo.size.height
                    let phase = audioEngine.currentStereoPhase // -1 to 1
                    
                    // Background
                    Rectangle()
                        .fill(LinearGradient(colors: [.red, .yellow, .green], startPoint: .leading, endPoint: .trailing))
                        .mask(
                            HStack(spacing: 0) {
                                Rectangle().fill(Color.white).frame(width: width/2) // -1 to 0
                                Rectangle().fill(Color.white).frame(width: width/2) // 0 to 1
                            }
                        )
                        .opacity(0.3)
                    
                    // Center Line
                    Rectangle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 1, height: height)
                        .position(x: width/2, y: height/2)
                    
                    // Indicator
                    let x = (CGFloat(phase) + 1.0) / 2.0 * width
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 10, height: 10)
                        .position(x: x, y: height/2)
                        .shadow(radius: 2)
                }
                .frame(height: 30)
                
                HStack {
                    Text("-1").font(.caption2)
                    Spacer()
                    Text("0").font(.caption2)
                    Spacer()
                    Text("+1").font(.caption2)
                }
                .foregroundColor(.gray)
            }
            .padding()
            
            // Goniometer (Simulated for Mono/Stereo visualization)
            // Since we don't have full L/R buffer history here easily without copying lots of data,
            // we visualize the phase correlation as a shape.
            Canvas { context, size in
                if audioEngine.currentSpectrum.isEmpty {
                    let text = Text("Warte auf Audio...").font(.caption).foregroundColor(.gray)
                    context.draw(text, at: CGPoint(x: size.width/2, y: size.height/2))
                    return
                }
                
                let center = CGPoint(x: size.width/2, y: size.height/2)
                let radius = min(size.width, size.height) / 2 - 5
                
                // Draw Circle
                context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius*2, height: radius*2)), with: .color(.gray.opacity(0.3)))
                
                // Draw Phase Vector
                // +1 = Vertical Line (Mono)
                // 0 = Circle (Stereo)
                // -1 = Horizontal Line (Out of Phase)
                
                let phase = CGFloat(audioEngine.currentStereoPhase)
                // Map phase to ellipse width/height ratio
                // This is an approximation for visualization
                
                let w = radius * (1.0 - phase) // +1 -> 0 width, -1 -> 2*radius width
                let h = radius * (1.0 + phase) // +1 -> 2*radius height, -1 -> 0 height
                // Normalize to keep size somewhat constant
                let scale = radius / (max(w, h) + 1e-5)
                
                let ellipseRect = CGRect(x: center.x - w*scale, y: center.y - h*scale, width: w*scale*2, height: h*scale*2)
                context.stroke(Path(ellipseIn: ellipseRect), with: .color(.green), lineWidth: 2)
            }
            .frame(width: 100)
        }
        .background(Color(UIColor.systemBackground))
        .onAppear {
            print("[PhaseMeterWidget] View appeared")
        }
    }
}