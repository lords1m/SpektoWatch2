import SwiftUI

// MARK: - Spectrum Band Mode
enum SpectrumBandMode: String, CaseIterable {
    case bark = "Bark"
    case octave = "Oktav"
    case thirdOctave = "Terz"

    init(settingValue: String) {
        switch settingValue.lowercased() {
        case "bark": self = .bark
        case "octave", "oktav": self = .octave
        case "terz", "thirdoctave", "third_octave": self = .thirdOctave
        default: self = .thirdOctave
        }
    }
}

// MARK: - Frequency Spectrum Widget
struct FrequencySpectrumWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    var settings: [String: String]

    private var weighting: String { settings["freqWeighting"] ?? "Z" }
    private var bandMode: SpectrumBandMode { SpectrumBandMode(settingValue: settings["frequencyBands"] ?? "terz") }
    private var frequencies: [Float] { audioEngine.currentSpectrogramData?.frequencies ?? [] }
    private var weightedSpectrum: [Float] {
        guard let data = audioEngine.currentSpectrogramData else {
            return audioEngine.currentSpectrum
        }
        return data.magnitudes(for: weighting)
    }

    var body: some View {
        SpectrumBandChartView(mode: bandMode, frequencies: frequencies, spectrum: weightedSpectrum)
        .onAppear {
            print("[FrequencySpectrumWidget] View appeared (\(weighting), \(bandMode.rawValue))")
        }
    }
}

private struct SpectrumBandData {
    let values: [Float]
    let labels: [String]
    let labelStride: Int
}

// MARK: - Spectrum Band Chart
private struct SpectrumBandChartView: View {
    let mode: SpectrumBandMode
    let frequencies: [Float]
    let spectrum: [Float]

    @State private var leqValues: [Float] = []
    @State private var sampleCount: Int = 0
    private let leqAlpha: Float = 0.02

    var body: some View {
        Canvas { context, size in
            let bandData = computeBandData(mode: mode, frequencies: frequencies, spectrum: spectrum)
            let bands = bandData.values
            let width = size.width
            let height = size.height

            if bands.isEmpty || bands.allSatisfy({ $0 <= -100 }) {
                let text = Text("Warte auf Audio...").font(.caption).foregroundColor(.gray)
                context.draw(text, at: CGPoint(x: size.width/2, y: size.height/2))
                return
            }

            let bottomPadding: CGFloat = 20
            let leftPadding: CGFloat = 24
            let graphWidth = width - leftPadding
            let graphHeight = height - bottomPadding

            context.fill(Path(CGRect(x: 0, y: 0, width: width, height: height)), with: .color(Color(UIColor.systemBackground)))

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

            let barCount = bands.count
            let barWidth = graphWidth / CGFloat(barCount)
            let barGap: CGFloat = (mode == .octave) ? 4 : 1

            for i in 0..<barCount {
                let val = bands[i]
                let normalized = CGFloat((val - minDB) / range)
                let clamped = max(0, min(1, normalized))
                let barHeight = clamped * graphHeight
                let x = leftPadding + CGFloat(i) * barWidth
                let barRect = CGRect(
                    x: x + barGap / 2,
                    y: graphHeight - barHeight,
                    width: max(0, barWidth - barGap),
                    height: barHeight
                )

                let hue = 0.62 - Double(i) / Double(max(barCount, 1)) * 0.42
                let color = Color(hue: hue, saturation: 0.82, brightness: 0.92)
                context.fill(Path(barRect), with: .color(color))

                if i < leqValues.count {
                    let leqNorm = CGFloat((leqValues[i] - minDB) / range)
                    let leqClamped = max(0, min(1, leqNorm))
                    let leqY = graphHeight - leqClamped * graphHeight
                    var leqPath = Path()
                    leqPath.move(to: CGPoint(x: x + barGap / 2, y: leqY))
                    leqPath.addLine(to: CGPoint(x: x + barWidth - barGap / 2, y: leqY))
                    context.stroke(leqPath, with: .color(.white), lineWidth: 2)
                }
            }

            for i in stride(from: 0, to: bandData.labels.count, by: max(1, bandData.labelStride)) {
                let x = leftPadding + CGFloat(i) * barWidth + barWidth / 2
                context.draw(Text(bandData.labels[i]).font(.system(size: 8)).foregroundColor(.gray), at: CGPoint(x: x, y: height - bottomPadding / 2))
            }
        }
        .drawingGroup()
        .onAppear {
            resetLeq()
            updateLeq(with: computeBandData(mode: mode, frequencies: frequencies, spectrum: spectrum).values)
        }
        .onChange(of: mode) { _, _ in
            resetLeq()
        }
        .onChange(of: spectrum) { _, newSpectrum in
            updateLeq(with: computeBandData(mode: mode, frequencies: frequencies, spectrum: newSpectrum).values)
        }
    }

    private func resetLeq() {
        leqValues = []
        sampleCount = 0
    }

    private func updateLeq(with bands: [Float]) {
        guard !bands.isEmpty else { return }
        if leqValues.count != bands.count {
            leqValues = [Float](repeating: -120.0, count: bands.count)
            sampleCount = 0
        }
        sampleCount += 1
        for i in 0..<bands.count {
            if sampleCount == 1 {
                leqValues[i] = bands[i]
            } else {
                let currentLinear = pow(10, bands[i] / 10.0)
                let leqLinear = pow(10, leqValues[i] / 10.0)
                let newLeqLinear = leqLinear * (1 - leqAlpha) + currentLinear * leqAlpha
                leqValues[i] = 10 * log10(max(newLeqLinear, 1e-10))
            }
        }
    }

    private func computeBandData(mode: SpectrumBandMode, frequencies: [Float], spectrum: [Float]) -> SpectrumBandData {
        switch mode {
        case .thirdOctave:
            let labels = [
                "20", "25", "31.5", "40", "50", "63", "80", "100", "125", "160",
                "200", "250", "315", "400", "500", "630", "800", "1k", "1.25k", "1.6k",
                "2k", "2.5k", "3.15k", "4k", "5k", "6.3k", "8k", "10k", "12.5k", "16k", "20k"
            ]
            let centerFreqs: [Float] = [
                20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630,
                800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
            ]
            return SpectrumBandData(
                values: thirdOctaveBands(centerFrequencies: centerFreqs, frequencies: frequencies, spectrum: spectrum),
                labels: labels,
                labelStride: 5
            )

        case .octave:
            let labels = ["31.5", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
            let thirdCenters: [Float] = [
                20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630,
                800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
            ]
            let thirds = thirdOctaveBands(centerFrequencies: thirdCenters, frequencies: frequencies, spectrum: spectrum)
            let mapping: [[Int]] = [[1, 2, 3], [4, 5, 6], [7, 8, 9], [10, 11, 12], [13, 14, 15], [16, 17, 18], [19, 20, 21], [22, 23, 24], [25, 26, 27], [28, 29, 30]]
            var octaveValues: [Float] = []
            for indices in mapping {
                var sumLinear: Float = 0
                for idx in indices where idx < thirds.count {
                    sumLinear += pow(10, thirds[idx] / 10.0)
                }
                octaveValues.append(10 * log10(max(sumLinear, 1e-10)))
            }
            return SpectrumBandData(values: octaveValues, labels: labels, labelStride: 1)

        case .bark:
            // 24 Bark bands, approximated by standard edge frequencies.
            let barkEdges: [Float] = [
                20, 100, 200, 300, 400, 510, 630, 770, 920, 1080, 1270, 1480, 1720,
                2000, 2320, 2700, 3150, 3700, 4400, 5300, 6400, 7700, 9500, 12000, 15500
            ]
            var barkValues: [Float] = []
            for i in 0..<(barkEdges.count - 1) {
                let lower = barkEdges[i]
                let upper = barkEdges[i + 1]
                var sumLinear: Float = 0
                var hasBin = false
                for (idx, freq) in frequencies.enumerated() where idx < spectrum.count {
                    if freq >= lower && freq < upper {
                        sumLinear += pow(10, spectrum[idx] / 10.0)
                        hasBin = true
                    }
                }
                barkValues.append(hasBin ? 10 * log10(max(sumLinear, 1e-10)) : -120.0)
            }
            let labels = (1...24).map(String.init)
            return SpectrumBandData(values: barkValues, labels: labels, labelStride: 3)
        }
    }

    private func thirdOctaveBands(centerFrequencies: [Float], frequencies: [Float], spectrum: [Float]) -> [Float] {
        var bands = [Float](repeating: -120.0, count: centerFrequencies.count)
        guard !frequencies.isEmpty, !spectrum.isEmpty else { return bands }
        let lowerFactor = pow(2.0 as Float, -1.0 / 6.0)
        let upperFactor = pow(2.0 as Float, 1.0 / 6.0)
        for (i, center) in centerFrequencies.enumerated() {
            let lower = center * lowerFactor
            let upper = center * upperFactor
            var bandMax: Float = -120.0
            for (idx, freq) in frequencies.enumerated() where idx < spectrum.count {
                if freq >= lower && freq < upper {
                    bandMax = max(bandMax, spectrum[idx])
                }
            }
            bands[i] = bandMax
        }
        return bands
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
