import SwiftUI

// MARK: - Spectrum Resolution Mode
enum SpectrumResolutionMode: String, CaseIterable {
    case full = "Voll"
    case thirdOctave = "Terz"
    case octave = "Oktav"

    var icon: String {
        switch self {
        case .full: return "waveform.path"
        case .thirdOctave: return "chart.bar.fill"
        case .octave: return "chart.bar"
        }
    }
}

// MARK: - Frequency Spectrum Widget
struct FrequencySpectrumWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    @State private var resolutionMode: SpectrumResolutionMode = .full

    var body: some View {
        VStack(spacing: 0) {
            // Resolution Mode Picker
            HStack(spacing: 4) {
                ForEach(SpectrumResolutionMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            resolutionMode = mode
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 10))
                            Text(mode.rawValue)
                                .font(.system(size: 10))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(resolutionMode == mode ? Color.blue : Color(.systemGray5))
                        .foregroundColor(resolutionMode == mode ? .white : .primary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            // Spectrum Display
            switch resolutionMode {
            case .full:
                FullSpectrumView(audioEngine: audioEngine)
            case .thirdOctave:
                ThirdOctaveSpectrumView(audioEngine: audioEngine)
            case .octave:
                OctaveSpectrumView(audioEngine: audioEngine)
            }
        }
        .onAppear {
            print("[FrequencySpectrumWidget] View appeared")
        }
    }
}

// MARK: - Full Resolution Spectrum
private struct FullSpectrumView: View {
    @ObservedObject var audioEngine: AudioEngine
    let dbOffset: Float = 0.0

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

            let bottomPadding: CGFloat = 16
            let leftPadding: CGFloat = 24
            let graphWidth = width - leftPadding
            let graphHeight = height - bottomPadding

            // Background
            context.fill(Path(CGRect(x: 0, y: 0, width: width, height: height)), with: .color(Color(UIColor.systemBackground)))

            // Y-Axis
            let minDB: Float = 0.0
            let maxDB: Float = 100.0
            let range = maxDB - minDB

            for db in [100, 80, 60, 40, 20, 0] as [Float] {
                let y = (1.0 - CGFloat((db - minDB) / range)) * graphHeight
                var gridPath = Path()
                gridPath.move(to: CGPoint(x: leftPadding, y: y))
                gridPath.addLine(to: CGPoint(x: width, y: y))
                context.stroke(gridPath, with: .color(Color.gray.opacity(0.2)), lineWidth: 0.5)
                context.draw(Text("\(Int(db))").font(.system(size: 8)).foregroundColor(.gray), at: CGPoint(x: leftPadding / 2, y: y))
            }

            // Bars
            let barCount = 100
            let step = max(1, spectrum.count / barCount)
            let barWidth = graphWidth / CGFloat(barCount)

            for i in 0..<barCount {
                let idx = i * step
                if idx < spectrum.count {
                    let endIdx = min(idx + step, spectrum.count)
                    let val = spectrum[idx..<endIdx].max() ?? -120.0
                    let normalized = CGFloat((val + dbOffset - minDB) / range)
                    let clamped = max(0, min(1, normalized))

                    let barHeight = clamped * graphHeight
                    let x = leftPadding + CGFloat(i) * barWidth
                    let barRect = CGRect(x: x, y: graphHeight - barHeight, width: barWidth - 1, height: barHeight)

                    let color: Color = clamped > 0.8 ? .red : (clamped > 0.6 ? .yellow : .green)
                    context.fill(Path(barRect), with: .color(color))
                }
            }

            // X-Axis Labels
            for (label, normX) in [("0", 0.0), ("5k", 0.23), ("10k", 0.45), ("15k", 0.68), ("20k", 0.91)] as [(String, CGFloat)] {
                context.draw(Text(label).font(.system(size: 8)).foregroundColor(.gray), at: CGPoint(x: leftPadding + normX * graphWidth, y: height - bottomPadding / 2))
            }
        }
        .drawingGroup()
    }
}

// MARK: - 1/3 Octave (Terz) Spectrum
private struct ThirdOctaveSpectrumView: View {
    @ObservedObject var audioEngine: AudioEngine
    @State private var leqValues: [Float] = Array(repeating: -120.0, count: 31)
    @State private var sampleCount: Int = 0

    // 31 Terzbänder nach IEC 61260
    static let centerFreqs: [String] = [
        "20", "25", "31.5", "40", "50", "63", "80", "100", "125", "160",
        "200", "250", "315", "400", "500", "630", "800", "1k", "1.25k", "1.6k",
        "2k", "2.5k", "3.15k", "4k", "5k", "6.3k", "8k", "10k", "12.5k", "16k", "20k"
    ]

    // Leq Smoothing Factor (exponentieller gleitender Durchschnitt)
    private let leqAlpha: Float = 0.02

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let bands = audioEngine.currentOctaveBands

            if bands.allSatisfy({ $0 <= -100 }) {
                let text = Text("Warte auf Audio...").font(.caption).foregroundColor(.gray)
                context.draw(text, at: CGPoint(x: size.width/2, y: size.height/2))
                return
            }

            let bottomPadding: CGFloat = 20
            let leftPadding: CGFloat = 24
            let graphWidth = width - leftPadding
            let graphHeight = height - bottomPadding

            // Background
            context.fill(Path(CGRect(x: 0, y: 0, width: width, height: height)), with: .color(Color(UIColor.systemBackground)))

            // Y-Axis
            let minDB: Float = 20.0
            let maxDB: Float = 100.0
            let range = maxDB - minDB

            for db in [100, 80, 60, 40, 20] as [Float] {
                let y = (1.0 - CGFloat((db - minDB) / range)) * graphHeight
                var gridPath = Path()
                gridPath.move(to: CGPoint(x: leftPadding, y: y))
                gridPath.addLine(to: CGPoint(x: width, y: y))
                context.stroke(gridPath, with: .color(Color.gray.opacity(0.2)), lineWidth: 0.5)
                context.draw(Text("\(Int(db))").font(.system(size: 8)).foregroundColor(.gray), at: CGPoint(x: leftPadding / 2, y: y))
            }

            // Bars
            let barCount = bands.count
            let barWidth = graphWidth / CGFloat(barCount)
            let barGap: CGFloat = 1

            for (i, val) in bands.enumerated() {
                let normalized = CGFloat((val - minDB) / range)
                let clamped = max(0, min(1, normalized))

                let barHeight = clamped * graphHeight
                let x = leftPadding + CGFloat(i) * barWidth
                let barRect = CGRect(x: x + barGap/2, y: graphHeight - barHeight, width: barWidth - barGap, height: barHeight)

                // Color gradient based on frequency
                let hue = 0.6 - Double(i) / Double(barCount) * 0.4
                let color = Color(hue: hue, saturation: 0.8, brightness: 0.9)
                context.fill(Path(barRect), with: .color(color))

                // Top highlight
                let topRect = CGRect(x: x + barGap/2, y: graphHeight - barHeight, width: barWidth - barGap, height: 2)
                context.fill(Path(topRect), with: .color(.white.opacity(0.4)))

                // Leq Marker (Mittelwert-Strich)
                if i < leqValues.count {
                    let leqNorm = CGFloat((leqValues[i] - minDB) / range)
                    let leqClamped = max(0, min(1, leqNorm))
                    let leqY = graphHeight - leqClamped * graphHeight

                    var leqPath = Path()
                    leqPath.move(to: CGPoint(x: x + 1, y: leqY))
                    leqPath.addLine(to: CGPoint(x: x + barWidth - 1, y: leqY))
                    context.stroke(leqPath, with: .color(.white), lineWidth: 2)
                }
            }

            // X-Axis Labels (every 5th band)
            for i in stride(from: 0, to: Self.centerFreqs.count, by: 5) {
                let x = leftPadding + CGFloat(i) * barWidth + barWidth / 2
                context.draw(Text(Self.centerFreqs[i]).font(.system(size: 7)).foregroundColor(.gray), at: CGPoint(x: x, y: height - bottomPadding / 2))
            }
        }
        .drawingGroup()
        .onChange(of: audioEngine.currentOctaveBands) { _, newBands in
            updateLeq(bands: newBands)
        }
    }

    private func updateLeq(bands: [Float]) {
        guard bands.count == leqValues.count else { return }
        sampleCount += 1

        for i in 0..<bands.count {
            if sampleCount == 1 {
                leqValues[i] = bands[i]
            } else {
                // Energetischer Mittelwert (Leq)
                let currentLinear = pow(10, bands[i] / 10.0)
                let leqLinear = pow(10, leqValues[i] / 10.0)
                let newLeqLinear = leqLinear * (1 - leqAlpha) + currentLinear * leqAlpha
                leqValues[i] = 10 * log10(max(newLeqLinear, 1e-10))
            }
        }
    }
}

// MARK: - Octave Spectrum
private struct OctaveSpectrumView: View {
    @ObservedObject var audioEngine: AudioEngine
    @State private var leqValues: [Float] = Array(repeating: -120.0, count: 10)
    @State private var sampleCount: Int = 0

    // 10 Oktavbänder (31.5 Hz - 16 kHz)
    static let octaveCenterFreqs: [Float] = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let octaveLabels: [String] = ["31.5", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    // Terzbänder zu Oktavbändern zusammenfassen (jeweils 3 Terzen = 1 Oktave)
    static let terzToOctaveMapping: [[Int]] = [
        [1, 2, 3],      // 31.5 Hz
        [4, 5, 6],      // 63 Hz
        [7, 8, 9],      // 125 Hz
        [10, 11, 12],   // 250 Hz
        [13, 14, 15],   // 500 Hz
        [16, 17, 18],   // 1 kHz
        [19, 20, 21],   // 2 kHz
        [22, 23, 24],   // 4 kHz
        [25, 26, 27],   // 8 kHz
        [28, 29, 30]    // 16 kHz
    ]

    // Leq Smoothing Factor
    private let leqAlpha: Float = 0.02

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let terzBands = audioEngine.currentOctaveBands

            if terzBands.allSatisfy({ $0 <= -100 }) {
                let text = Text("Warte auf Audio...").font(.caption).foregroundColor(.gray)
                context.draw(text, at: CGPoint(x: size.width/2, y: size.height/2))
                return
            }

            // Oktavbänder berechnen (energetische Summe der 3 Terzen)
            var octaveBands: [Float] = []
            for indices in Self.terzToOctaveMapping {
                var sumLinear: Float = 0
                for idx in indices {
                    if idx < terzBands.count {
                        sumLinear += pow(10, terzBands[idx] / 10.0)
                    }
                }
                let octaveDb = 10 * log10(max(sumLinear, 1e-10))
                octaveBands.append(octaveDb)
            }

            let bottomPadding: CGFloat = 20
            let leftPadding: CGFloat = 24
            let graphWidth = width - leftPadding
            let graphHeight = height - bottomPadding

            // Background
            context.fill(Path(CGRect(x: 0, y: 0, width: width, height: height)), with: .color(Color(UIColor.systemBackground)))

            // Y-Axis
            let minDB: Float = 20.0
            let maxDB: Float = 100.0
            let range = maxDB - minDB

            for db in [100, 80, 60, 40, 20] as [Float] {
                let y = (1.0 - CGFloat((db - minDB) / range)) * graphHeight
                var gridPath = Path()
                gridPath.move(to: CGPoint(x: leftPadding, y: y))
                gridPath.addLine(to: CGPoint(x: width, y: y))
                context.stroke(gridPath, with: .color(Color.gray.opacity(0.2)), lineWidth: 0.5)
                context.draw(Text("\(Int(db))").font(.system(size: 8)).foregroundColor(.gray), at: CGPoint(x: leftPadding / 2, y: y))
            }

            // Bars
            let barCount = octaveBands.count
            let barWidth = graphWidth / CGFloat(barCount)
            let barGap: CGFloat = 4

            for (i, val) in octaveBands.enumerated() {
                let normalized = CGFloat((val - minDB) / range)
                let clamped = max(0, min(1, normalized))

                let barHeight = clamped * graphHeight
                let x = leftPadding + CGFloat(i) * barWidth
                let barRect = CGRect(x: x + barGap/2, y: graphHeight - barHeight, width: barWidth - barGap, height: barHeight)

                // Color gradient based on level
                let color: Color = clamped > 0.8 ? .red : (clamped > 0.6 ? .orange : .blue)
                context.fill(Path(barRect), with: .color(color))

                // Top highlight
                let topRect = CGRect(x: x + barGap/2, y: graphHeight - barHeight, width: barWidth - barGap, height: 3)
                context.fill(Path(topRect), with: .color(.white.opacity(0.5)))

                // Leq Marker (Mittelwert-Strich)
                if i < leqValues.count {
                    let leqNorm = CGFloat((leqValues[i] - minDB) / range)
                    let leqClamped = max(0, min(1, leqNorm))
                    let leqY = graphHeight - leqClamped * graphHeight

                    var leqPath = Path()
                    leqPath.move(to: CGPoint(x: x + barGap/2, y: leqY))
                    leqPath.addLine(to: CGPoint(x: x + barWidth - barGap/2, y: leqY))
                    context.stroke(leqPath, with: .color(.white), lineWidth: 3)
                }

                // Value label on bar
                if barHeight > 25 {
                    let valueText = Text("\(Int(val))").font(.system(size: 9, weight: .medium)).foregroundColor(.white)
                    context.draw(valueText, at: CGPoint(x: x + barWidth/2, y: graphHeight - barHeight + 12))
                }
            }

            // X-Axis Labels
            for (i, label) in Self.octaveLabels.enumerated() {
                let x = leftPadding + CGFloat(i) * barWidth + barWidth / 2
                context.draw(Text(label).font(.system(size: 9, weight: .medium)).foregroundColor(.gray), at: CGPoint(x: x, y: height - bottomPadding / 2))
            }
        }
        .drawingGroup()
        .onChange(of: audioEngine.currentOctaveBands) { _, newBands in
            updateLeq(bands: newBands)
        }
    }

    private func updateLeq(bands: [Float]) {
        // Berechne Oktavbänder aus Terzbändern
        var octaveBands: [Float] = []
        for indices in Self.terzToOctaveMapping {
            var sumLinear: Float = 0
            for idx in indices {
                if idx < bands.count {
                    sumLinear += pow(10, bands[idx] / 10.0)
                }
            }
            let octaveDb = 10 * log10(max(sumLinear, 1e-10))
            octaveBands.append(octaveDb)
        }

        guard octaveBands.count == leqValues.count else { return }
        sampleCount += 1

        for i in 0..<octaveBands.count {
            if sampleCount == 1 {
                leqValues[i] = octaveBands[i]
            } else {
                // Energetischer Mittelwert (Leq)
                let currentLinear = pow(10, octaveBands[i] / 10.0)
                let leqLinear = pow(10, leqValues[i] / 10.0)
                let newLeqLinear = leqLinear * (1 - leqAlpha) + currentLinear * leqAlpha
                leqValues[i] = 10 * log10(max(newLeqLinear, 1e-10))
            }
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
                    let level = audioEngine.currentLevel // dB SPL (kalibriert)
                    let minDB: Float = 30.0   // 30 dB SPL
                    let maxDB: Float = 100.0  // 100 dB SPL
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
                    Text("30").font(.caption2).foregroundColor(.gray)
                    Spacer()
                    Text("65").font(.caption2).foregroundColor(.gray)
                    Spacer()
                    Text("100").font(.caption2).foregroundColor(.gray)
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
                // Werte sind bereits in dB SPL kalibriert
                let minDB: Float = 20.0   // 20 dB SPL
                let maxDB: Float = 100.0  // 100 dB SPL
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