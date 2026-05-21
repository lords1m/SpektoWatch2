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

    private var useWidgetOverrides: Bool { WidgetSettings.usesWidgetOverrides(settings) }
    private var weighting: String {
        if useWidgetOverrides {
            return settings["freqWeighting"] ?? audioEngine.frequencyWeighting.rawValue
        }
        return audioEngine.frequencyWeighting.rawValue
    }
    private var bandMode: SpectrumBandMode {
        if useWidgetOverrides {
            return SpectrumBandMode(settingValue: settings["frequencyBands"] ?? WidgetSettings.defaultSpectrumBandMode)
        }
        return SpectrumBandMode(settingValue: WidgetSettings.defaultSpectrumBandMode)
    }
    private var frequencies: [Float] { audioEngine.currentSpectrogramData?.frequencies ?? [] }
    private var weightedSpectrum: [Float] {
        guard let data = audioEngine.currentSpectrogramData else {
            return audioEngine.currentSpectrum
        }
        return data.magnitudes(for: weighting)
    }
    private var weightedThirdOctaveBands: [Float] {
        switch weighting.uppercased() {
        case "A": return audioEngine.currentOctaveBandsA
        case "C": return audioEngine.currentOctaveBandsC
        default: return audioEngine.currentOctaveBandsZ
        }
    }

    var body: some View {
        SpectrumBandChartView(
            mode: bandMode,
            frequencies: frequencies,
            spectrum: weightedSpectrum,
            precomputedThirdOctave: weightedThirdOctaveBands,
            weightingLabel: weighting,
            yMinDB: Double(WidgetSettings.chartYMinDB(settings)),
            yMaxDB: Double(WidgetSettings.chartYMaxDB(settings))
        )
        .onAppear {
            print("[FrequencySpectrumWidget] View appeared (\(weighting), \(bandMode.rawValue), override=\(useWidgetOverrides))")
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
    let precomputedThirdOctave: [Float]
    let weightingLabel: String
    var yMinDB: Double = 20
    var yMaxDB: Double = 110

    @State private var leqValues: [Float] = []
    @State private var sampleCount: Int = 0
    @State private var diagnosticsCounter: Int = 0
    private let leqAlpha: Float = 0.02
    private let enableWidgetDiagnostics = ProcessInfo.processInfo.environment["SPEKTO_DEBUG_WIDGET_SPECTRUM"] == "1"

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

            let bottomPadding: CGFloat = 22
            let leftPadding: CGFloat = 34
            let rightPadding: CGFloat = 8
            let topPadding: CGFloat = 8
            let chartRect = CGRect(
                x: leftPadding,
                y: topPadding,
                width: max(1, width - leftPadding - rightPadding),
                height: max(1, height - topPadding - bottomPadding)
            )

            let minDB: Double = min(yMinDB, yMaxDB - 5)
            let maxDB: Double = max(yMaxDB, yMinDB + 5)
            let majorTicks = ScientificAxis.majorTicks(min: minDB, max: maxDB, targetTicks: 9)
            let minorTicks = ScientificAxis.minorTicks(major: majorTicks, subdivisions: 2)

            for tick in minorTicks where tick >= minDB && tick <= maxDB {
                let yNorm = ScientificAxis.normalized(tick, min: minDB, max: maxDB)
                let y = chartRect.maxY - CGFloat(yNorm) * chartRect.height
                var path = Path()
                path.move(to: CGPoint(x: chartRect.minX, y: y))
                path.addLine(to: CGPoint(x: chartRect.maxX, y: y))
                context.stroke(path, with: .color(ScientificChartPalette.gridMinor), lineWidth: 0.5)
            }

            for tick in majorTicks where tick >= minDB && tick <= maxDB {
                let yNorm = ScientificAxis.normalized(tick, min: minDB, max: maxDB)
                let y = chartRect.maxY - CGFloat(yNorm) * chartRect.height
                var path = Path()
                path.move(to: CGPoint(x: chartRect.minX, y: y))
                path.addLine(to: CGPoint(x: chartRect.maxX, y: y))
                context.stroke(path, with: .color(ScientificChartPalette.gridMajor), lineWidth: 0.7)
                context.draw(
                    Text("\(Int(tick))").font(.system(size: 8, weight: .regular, design: .monospaced)).foregroundColor(ScientificChartPalette.axis),
                    at: CGPoint(x: chartRect.minX - 14, y: y)
                )
            }

            let barCount = bands.count
            let barWidth = chartRect.width / CGFloat(max(barCount, 1))
            let barGap: CGFloat = (mode == .octave) ? 3 : 1

            for i in 0..<barCount {
                let val = bands[i]
                let normalized = CGFloat(ScientificAxis.normalized(Double(val), min: minDB, max: maxDB))
                let clamped = max(0, min(1, normalized))
                let barHeight = clamped * chartRect.height
                let x = chartRect.minX + CGFloat(i) * barWidth
                let barRect = CGRect(
                    x: x + barGap / 2,
                    y: chartRect.maxY - barHeight,
                    width: max(0, barWidth - barGap),
                    height: barHeight
                )

                context.fill(Path(barRect), with: .color(ScientificChartPalette.series.opacity(0.85)))

                if i < leqValues.count {
                    let leqNorm = CGFloat(ScientificAxis.normalized(Double(leqValues[i]), min: minDB, max: maxDB))
                    let leqClamped = max(0, min(1, leqNorm))
                    let leqY = chartRect.maxY - leqClamped * chartRect.height
                    var leqPath = Path()
                    leqPath.move(to: CGPoint(x: x + barGap / 2, y: leqY))
                    leqPath.addLine(to: CGPoint(x: x + barWidth - barGap / 2, y: leqY))
                    context.stroke(leqPath, with: .color(ScientificChartPalette.secondarySeries), lineWidth: 1.4)
                }
            }

            var axisPath = Path()
            axisPath.move(to: CGPoint(x: chartRect.minX, y: chartRect.minY))
            axisPath.addLine(to: CGPoint(x: chartRect.minX, y: chartRect.maxY))
            axisPath.addLine(to: CGPoint(x: chartRect.maxX, y: chartRect.maxY))
            context.stroke(axisPath, with: .color(ScientificChartPalette.axis), lineWidth: 1.0)

            for i in stride(from: 0, to: bandData.labels.count, by: max(1, bandData.labelStride)) {
                let x = chartRect.minX + CGFloat(i) * barWidth + barWidth / 2
                context.draw(
                    Text(bandData.labels[i]).font(.system(size: 8, weight: .regular, design: .monospaced)).foregroundColor(ScientificChartPalette.axis),
                    at: CGPoint(x: x, y: height - bottomPadding / 2)
                )
            }
        }
        .drawingGroup()
        .onAppear {
            resetLeq()
            let bandData = computeBandData(mode: mode, frequencies: frequencies, spectrum: spectrum)
            updateLeq(with: bandData.values)
            logBandDiagnosticsIfNeeded(bandData)
        }
        .onChange(of: mode) { _, _ in
            resetLeq()
        }
        .onChange(of: spectrum) { _, newSpectrum in
            let bandData = computeBandData(mode: mode, frequencies: frequencies, spectrum: newSpectrum)
            updateLeq(with: bandData.values)
            logBandDiagnosticsIfNeeded(bandData)
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
            let values = precomputedThirdOctave.count == centerFreqs.count
                ? precomputedThirdOctave
                : thirdOctaveBands(centerFrequencies: centerFreqs, frequencies: frequencies, spectrum: spectrum)
            return SpectrumBandData(
                values: values,
                labels: labels,
                labelStride: 5
            )

        case .octave:
            let labels = ["31.5", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
            let thirdCenters: [Float] = [
                20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630,
                800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
            ]
            let thirds = precomputedThirdOctave.count == thirdCenters.count
                ? precomputedThirdOctave
                : thirdOctaveBands(centerFrequencies: thirdCenters, frequencies: frequencies, spectrum: spectrum)
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
        let usableIndices = frequencies.indices.filter { idx in
            idx < spectrum.count && frequencies[idx] >= 0.0 && frequencies[idx] <= 20000.0
        }
        guard !usableIndices.isEmpty else { return bands }

        let lowerFactor = pow(2.0 as Float, -1.0 / 6.0)
        let upperFactor = pow(2.0 as Float, 1.0 / 6.0)
        for (i, center) in centerFrequencies.enumerated() {
            let lower = center * lowerFactor
            let upper = center * upperFactor
            var hasBinInBand = false
            var bandLinearSum: Float = 0.0
            var bandBinCount = 0
            for idx in usableIndices {
                let freq = frequencies[idx]
                if freq >= lower && freq < upper {
                    hasBinInBand = true
                    bandLinearSum += pow(10.0, spectrum[idx] / 10.0)
                    bandBinCount += 1
                }
            }
            if hasBinInBand, bandBinCount > 0 {
                // Band SPL = sum of linear bin powers, then back to dB.
                // Mirrors the fix in AudioEngine.computeDisplayThirdOctaveBands —
                // mean-of-bin-power under-reports by 10·log10(bins per band)
                // and produces the apparent "negative offset" vs broadband LAeq.
                bands[i] = 10.0 * log10(max(bandLinearSum, 1e-12))
                continue
            }

            // Coarse FFT grids can miss narrow low-frequency 1/3-octave bands.
            // Fallback to linear interpolation between neighboring FFT bins.
            if center <= 250.0 {
                bands[i] = interpolatedMagnitude(
                    targetFrequency: center,
                    frequencies: frequencies,
                    spectrum: spectrum,
                    usableIndices: usableIndices
                )
            } else {
                bands[i] = -120.0
            }
        }
        return bands
    }

    private func interpolatedMagnitude(
        targetFrequency: Float,
        frequencies: [Float],
        spectrum: [Float],
        usableIndices: [Int]
    ) -> Float {
        guard let first = usableIndices.first, let last = usableIndices.last else { return -120.0 }
        if targetFrequency <= frequencies[first] { return spectrum[first] }
        if targetFrequency >= frequencies[last] { return spectrum[last] }

        var upperIdx = first
        for idx in usableIndices where frequencies[idx] >= targetFrequency {
            upperIdx = idx
            break
        }
        guard let position = usableIndices.firstIndex(of: upperIdx), position > 0 else {
            return spectrum[upperIdx]
        }

        let lowerIdx = usableIndices[position - 1]
        let f0 = frequencies[lowerIdx]
        let f1 = frequencies[upperIdx]
        if abs(f1 - f0) < 0.001 {
            return max(spectrum[lowerIdx], spectrum[upperIdx])
        }

        let t = (targetFrequency - f0) / (f1 - f0)
        return spectrum[lowerIdx] * (1.0 - t) + spectrum[upperIdx] * t
    }

    private func logBandDiagnosticsIfNeeded(_ bandData: SpectrumBandData) {
        guard enableWidgetDiagnostics else { return }
        diagnosticsCounter += 1
        guard diagnosticsCounter % 60 == 0 else { return }

        let preview = zip(bandData.labels, bandData.values)
            .prefix(10)
            .map { label, value in "\(label)=\(String(format: "%.1f", value))" }
            .joined(separator: ",")
        let freqMin = frequencies.first ?? 0
        let freqMax = frequencies.last ?? 0
        let firstPositive = frequencies.first(where: { $0 > 0 }) ?? 0
        print(
            "[SpectrumWidgetDiag] mode=\(mode.rawValue) weighting=\(weightingLabel.uppercased()) bins=\(frequencies.count) " +
            "freqRange=\(String(format: "%.0f", freqMin))-\(String(format: "%.0f", freqMax))Hz binHz=\(String(format: "%.2f", firstPositive)) " +
            "bands{\(preview)}"
        )
    }
}

// MARK: - Level Meter Widget
struct LevelMeterWidget: View {
    @ObservedObject var audioEngine: AudioEngine
    var settings: [String: String] = [:]

    private var yMinDB: Float { WidgetSettings.chartYMinDB(settings) }
    private var yMaxDB: Float { WidgetSettings.chartYMaxDB(settings) }

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
                    let minDB: Float = yMinDB
                    let maxDB: Float = max(yMaxDB, yMinDB + 5)
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
        .onAppear {
            print("[LevelMeterWidget] View appeared")
        }
    }
}

// MARK: - Octave Band Analyzer Widget
struct OctaveBandWidget: View {
    @ObservedObject var audioEngine: AudioEngine

    var body: some View {
        let weighting = audioEngine.frequencyWeighting.rawValue
        let frequencies = audioEngine.currentSpectrogramData?.frequencies ?? []
        let spectrum = audioEngine.currentSpectrogramData?.magnitudes(for: weighting) ?? audioEngine.currentSpectrum
        SpectrumBandChartView(
            mode: .thirdOctave,
            frequencies: frequencies,
            spectrum: spectrum,
            precomputedThirdOctave: audioEngine.currentOctaveBands,
            weightingLabel: weighting
        )
        .onAppear {
            print("[OctaveBandWidget] View appeared")
        }
    }
}

// MARK: - Phase Meter Widget
struct PhaseMeterWidget: View {
    @ObservedObject var audioEngine: AudioEngine

    var body: some View {
        if audioEngine.isStereoActive {
            stereoContent
        } else {
            monoPlaceholder
        }
    }

    // MARK: Stereo view

    private var stereoContent: some View {
        HStack(spacing: 16) {
            // Correlation bar
            VStack(spacing: 4) {
                Text("Korrelation")
                    .font(.caption)
                    .foregroundColor(.gray)

                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let phase = audioEngine.currentStereoPhase

                    // Gradient background: red (–1, out of phase) → green (+1, mono/in phase)
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.red, .yellow, .green],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .opacity(0.3)
                        .cornerRadius(4)

                    // Center marker
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 1, height: h)
                        .position(x: w / 2, y: h / 2)

                    // Needle
                    let x = (CGFloat(phase) + 1.0) / 2.0 * w
                    Circle()
                        .fill(indicatorColor(phase: phase))
                        .frame(width: 12, height: 12)
                        .position(x: x, y: h / 2)
                        .shadow(color: indicatorColor(phase: phase).opacity(0.6), radius: 4)
                }
                .frame(height: 28)

                HStack {
                    Text("−1").font(.caption2)
                    Spacer()
                    Text("0").font(.caption2)
                    Spacer()
                    Text("+1").font(.caption2)
                }
                .foregroundColor(.gray)

                // Numeric readout
                Text(String(format: "%.2f", audioEngine.currentStereoPhase))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(indicatorColor(phase: audioEngine.currentStereoPhase))
            }
            .padding()

            // Correlation ellipse (phase-scope approximation)
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 6

                // Reference circle
                context.stroke(
                    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                           width: radius * 2, height: radius * 2)),
                    with: .color(.gray.opacity(0.3))
                )

                // 45° reference lines (L and R axes of a real goniometer)
                let d = radius * 0.85
                var lAxis = Path()
                lAxis.move(to: CGPoint(x: center.x - d * 0.707, y: center.y + d * 0.707))
                lAxis.addLine(to: CGPoint(x: center.x + d * 0.707, y: center.y - d * 0.707))
                context.stroke(lAxis, with: .color(.gray.opacity(0.2)), lineWidth: 1)

                var rAxis = Path()
                rAxis.move(to: CGPoint(x: center.x + d * 0.707, y: center.y + d * 0.707))
                rAxis.addLine(to: CGPoint(x: center.x - d * 0.707, y: center.y - d * 0.707))
                context.stroke(rAxis, with: .color(.gray.opacity(0.2)), lineWidth: 1)

                // Phase ellipse:
                // +1 (mono/in-phase)  → tall vertical line
                //  0 (uncorrelated)   → circle
                // –1 (out-of-phase)   → wide horizontal line
                let phase = CGFloat(audioEngine.currentStereoPhase)
                let scaleX = sqrt(max(0, (1.0 - phase) / 2.0))
                let scaleY = sqrt(max(0, (1.0 + phase) / 2.0))
                let ew = radius * scaleX
                let eh = radius * scaleY
                if ew > 0.5 || eh > 0.5 {
                    let ellipseRect = CGRect(x: center.x - ew, y: center.y - eh,
                                            width: ew * 2, height: eh * 2)
                    context.stroke(Path(ellipseIn: ellipseRect),
                                   with: .color(.green), lineWidth: 2)
                }
            }
            .frame(width: 110)
        }
    }

    // MARK: Mono placeholder

    private var monoPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.slash")
                .font(.title2)
                .foregroundColor(.gray)
            Text("Kein Stereo-Signal")
                .font(.caption)
                .foregroundColor(.gray)
            Text("Stereo-Mikrofon in den\nEinstellungen aktivieren")
                .font(.caption2)
                .foregroundColor(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private func indicatorColor(phase: Float) -> Color {
        switch phase {
        case ..<(-0.1): return .red
        case (-0.1)..<0.3: return .yellow
        default: return .green
        }
    }
}
