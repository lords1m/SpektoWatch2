import SwiftUI
import Charts

/// Erweiterte Frequenzanalyse-View für didaktische Zwecke
/// Ermöglicht Studenten, FFT-Parameter zu ändern und deren Auswirkungen zu verstehen
struct AdvancedAnalysisView: View {
    @ObservedObject var fftConfig: FFTConfiguration
    @ObservedObject var audioEngine: AudioEngine

    @State private var selectedTab: AnalysisTab = .parameters
    @State private var showPresetPicker = false

    enum AnalysisTab: String, CaseIterable {
        case parameters = "Parameter"
        case windows = "Fenster"
        case resolution = "Auflösung"
        case comparison = "Vergleich"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Picker
                Picker("Bereich", selection: $selectedTab) {
                    ForEach(AnalysisTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // Content
                ScrollView {
                    switch selectedTab {
                    case .parameters:
                        ParametersSection(fftConfig: fftConfig)
                    case .windows:
                        WindowFunctionSection(fftConfig: fftConfig)
                    case .resolution:
                        ResolutionSection(fftConfig: fftConfig)
                    case .comparison:
                        ComparisonSection(fftConfig: fftConfig, audioEngine: audioEngine)
                    }
                }
            }
            .navigationTitle("Spektralanalyse")
            .navigationBarTitleDisplayMode(.inline)
            // Übertrage Änderungen an den AudioEngine
            .onChange(of: fftConfig.windowFunction) { _, newValue in
                audioEngine.setWindowFunction(newValue)
            }
            .onChange(of: fftConfig.blockSize) { _, newValue in
                audioEngine.setBlockSize(newValue)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(FFTConfiguration.Preset.allCases) { preset in
                            Button {
                                fftConfig.applyPreset(preset)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(preset.rawValue)
                                    Text(preset.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } label: {
                        Label("Voreinstellungen", systemImage: "slider.horizontal.3")
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Toggle(isOn: $fftConfig.showExplanations) {
                        Image(systemName: fftConfig.showExplanations ? "info.circle.fill" : "info.circle")
                    }
                }
            }
        }
    }
}

// MARK: - Parameters Section

private struct ParametersSection: View {
    @ObservedObject var fftConfig: FFTConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Block Size
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "square.grid.3x3")
                            .foregroundStyle(.blue)
                        Text("Blockgröße (N)")
                            .font(.headline)
                        Spacer()
                        Text("\(fftConfig.blockSize.rawValue) Samples")
                            .foregroundStyle(.secondary)
                    }

                    Picker("Blockgröße", selection: $fftConfig.blockSize) {
                        ForEach(FFTBlockSize.allCases) { size in
                            Text(size.shortDescription).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)

                    if fftConfig.showExplanations {
                        ExplanationBox(
                            title: "Was ist die Blockgröße?",
                            text: "Die Anzahl der Samples, die für eine FFT verwendet werden. Mehr Samples = bessere Frequenzauflösung, aber schlechtere Zeitauflösung (Heisenberg-Unsicherheit).",
                            icon: "lightbulb"
                        )
                    }
                }
            }

            // Window Function
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "waveform.path")
                            .foregroundStyle(.green)
                        Text("Fensterfunktion")
                            .font(.headline)
                        Spacer()
                        Text(fftConfig.windowFunction.localizedName)
                            .foregroundStyle(.secondary)
                    }

                    // Window Picker as Menu for more space
                    Menu {
                        ForEach(WindowFunction.allCases) { window in
                            Button {
                                fftConfig.windowFunction = window
                            } label: {
                                HStack {
                                    Text(window.localizedName)
                                    if window == fftConfig.windowFunction {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(fftConfig.windowFunction.localizedName)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    if fftConfig.showExplanations {
                        ExplanationBox(
                            title: "Warum Fensterfunktionen?",
                            text: "FFT nimmt an, dass das Signal periodisch ist. Fensterfunktionen reduzieren Artefakte (spektrale Leckage) an den Blockgrenzen.",
                            icon: "waveform.path.ecg"
                        )
                    }
                }
            }

            // Overlap
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "square.on.square")
                            .foregroundStyle(.orange)
                        Text("Overlap")
                            .font(.headline)
                        Spacer()
                        Text("\(Int(fftConfig.overlapPercent))%")
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $fftConfig.overlapPercent, in: 0...75, step: 25)

                    HStack {
                        Text("0%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Hop: \(fftConfig.hopSize) Samples")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("75%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if fftConfig.showExplanations {
                        ExplanationBox(
                            title: "Was ist Overlap?",
                            text: "Überlappung aufeinanderfolgender FFT-Blöcke. Mehr Overlap = flüssigere Darstellung, aber mehr Rechenaufwand.",
                            icon: "arrow.left.and.right"
                        )
                    }
                }
            }

            // Current Resolution Summary
            CurrentResolutionCard(fftConfig: fftConfig)
        }
        .padding()
    }
}

// MARK: - Window Function Section

private struct WindowFunctionSection: View {
    @ObservedObject var fftConfig: FFTConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Window Shape Visualization
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Fensterform: \(fftConfig.windowFunction.localizedName)")
                        .font(.headline)

                    WindowShapeChart(windowFunction: fftConfig.windowFunction)
                        .frame(height: 150)
                }
            }

            // Window Comparison Table
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Vergleich der Fensterfunktionen")
                        .font(.headline)

                    WindowComparisonTable(selectedWindow: fftConfig.windowFunction)
                }
            }

            // Selected Window Details
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text(fftConfig.windowFunction.localizedName)
                            .font(.headline)
                    }

                    Text(fftConfig.windowFunction.description)
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Divider()

                    HStack(spacing: 20) {
                        StatBox(
                            label: "Hauptlappen",
                            value: String(format: "%.1f×", fftConfig.windowFunction.mainLobeWidth),
                            color: .blue
                        )
                        StatBox(
                            label: "Seitenlappen",
                            value: "\(Int(fftConfig.windowFunction.sidelobeAttenuation)) dB",
                            color: .orange
                        )
                        StatBox(
                            label: "Koh. Gain",
                            value: String(format: "%.2f", fftConfig.windowFunction.coherentGain),
                            color: .green
                        )
                    }
                }
            }

            if fftConfig.showExplanations {
                // Educational Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "graduationcap")
                                .foregroundStyle(.purple)
                            Text("Spektrale Leckage verstehen")
                                .font(.headline)
                        }

                        Text("""
                        Wenn ein Signal nicht exakt eine ganze Anzahl von Perioden im FFT-Block hat, \
                        "leckt" die Energie in benachbarte Frequenzbins. Dies erscheint als \
                        verschmiertes Spektrum statt scharfer Peaks.

                        **Rectangular-Fenster**: Maximale Leckage, aber schärfste Peaks
                        **Blackman-Harris**: Minimale Leckage, aber breitere Peaks

                        Tipp: Verwende das "Didaktisch"-Preset, um Leckage bei einem Sinuston zu demonstrieren!
                        """)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Resolution Section

private struct ResolutionSection: View {
    @ObservedObject var fftConfig: FFTConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Heisenberg Visualization
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "atom")
                            .foregroundStyle(.purple)
                        Text("Zeit-Frequenz-Unsicherheit")
                            .font(.headline)
                    }

                    HeisenbergVisualization(
                        blockSize: fftConfig.blockSize,
                        allSizes: FFTBlockSize.allCases
                    )
                    .frame(height: 200)

                    if fftConfig.showExplanations {
                        Text("""
                        Das Heisenberg-Unsicherheitsprinzip gilt auch für die Signalanalyse: \
                        Man kann nicht gleichzeitig perfekte Zeit- UND Frequenzauflösung haben. \
                        Das Produkt Δt × Δf ist konstant.
                        """)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            // Current Resolution Details
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Aktuelle Auflösung")
                        .font(.headline)

                    VStack(spacing: 12) {
                        ResolutionRow(
                            icon: "waveform",
                            label: "Frequenzauflösung (Δf)",
                            value: String(format: "%.2f Hz", fftConfig.frequencyResolution),
                            detail: "Kleinste unterscheidbare Frequenzdifferenz"
                        )

                        ResolutionRow(
                            icon: "clock",
                            label: "Zeitauflösung (Δt)",
                            value: String(format: "%.1f ms", fftConfig.timeResolutionMs),
                            detail: "Zeit für einen FFT-Block"
                        )

                        ResolutionRow(
                            icon: "number",
                            label: "Frequenzbins",
                            value: "\(fftConfig.binCount)",
                            detail: "Anzahl der Frequenzpunkte im Spektrum"
                        )

                        ResolutionRow(
                            icon: "arrow.up.and.down",
                            label: "Nyquist-Frequenz",
                            value: "22.05 kHz",
                            detail: "Maximale darstellbare Frequenz"
                        )
                    }
                }
            }

            // Practical Examples
            if fftConfig.showExplanations {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "music.note")
                                .foregroundStyle(.orange)
                            Text("Praktisches Beispiel")
                                .font(.headline)
                        }

                        let canDistinguish = fftConfig.frequencyResolution < 1.0
                        // A4 = 440.0 Hz, A#4 = 466.16 Hz (Differenz ~26 Hz)

                        Text("""
                        Mit Δf = \(String(format: "%.2f", fftConfig.frequencyResolution)) Hz \
                        \(canDistinguish ? "kannst" : "kannst du NICHT") du A4 (440 Hz) von A#4 (466 Hz) unterscheiden.

                        Für Musik-Tuning (±1 Hz Genauigkeit) brauchst du mindestens 8192 Samples.
                        Für Sprache reichen oft 2048 Samples.
                        """)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Comparison Section

private struct ComparisonSection: View {
    @ObservedObject var fftConfig: FFTConfiguration
    @ObservedObject var audioEngine: AudioEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Enable Comparison Mode
            GroupBox {
                Toggle(isOn: $fftConfig.comparisonModeEnabled) {
                    HStack {
                        Image(systemName: "rectangle.split.2x1")
                            .foregroundStyle(.blue)
                        Text("A/B Vergleichsmodus")
                            .font(.headline)
                    }
                }
            }

            if fftConfig.comparisonModeEnabled {
                // Configuration A (Current)
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Circle()
                                .fill(.blue)
                                .frame(width: 12, height: 12)
                            Text("Konfiguration A")
                                .font(.headline)
                        }

                        HStack {
                            Text("Fenster:")
                            Spacer()
                            Text(fftConfig.windowFunction.localizedName)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Blockgröße:")
                            Spacer()
                            Text("\(fftConfig.blockSize.rawValue)")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Δf:")
                            Spacer()
                            Text(String(format: "%.2f Hz", fftConfig.frequencyResolution))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Configuration B
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Circle()
                                .fill(.orange)
                                .frame(width: 12, height: 12)
                            Text("Konfiguration B")
                                .font(.headline)
                        }

                        Picker("Fenster", selection: $fftConfig.comparisonWindowFunction) {
                            ForEach(WindowFunction.allCases) { window in
                                Text(window.localizedName).tag(window)
                            }
                        }

                        Picker("Blockgröße", selection: $fftConfig.comparisonBlockSize) {
                            ForEach(FFTBlockSize.allCases) { size in
                                Text(size.shortDescription).tag(size)
                            }
                        }
                        .pickerStyle(.segmented)

                        let freqResB = 44100.0 / Float(fftConfig.comparisonBlockSize.rawValue)
                        HStack {
                            Text("Δf:")
                            Spacer()
                            Text(String(format: "%.2f Hz", freqResB))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Comparison Chart (Placeholder for real spectrum)
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Spektrum-Vergleich")
                            .font(.headline)

                        ComparisonSpectrumView(
                            configA: (fftConfig.windowFunction, fftConfig.blockSize),
                            configB: (fftConfig.comparisonWindowFunction, fftConfig.comparisonBlockSize)
                        )
                        .frame(height: 200)

                        Text("Blau = Konfiguration A, Orange = Konfiguration B")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Difference Summary
                if fftConfig.showExplanations {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Unterschiede")
                                .font(.headline)

                            let sidelobeA = fftConfig.windowFunction.sidelobeAttenuation
                            let sidelobeB = fftConfig.comparisonWindowFunction.sidelobeAttenuation

                            if sidelobeA < sidelobeB {
                                DifferenceRow(
                                    text: "Konfiguration A hat \(Int(sidelobeB - sidelobeA)) dB weniger Leckage",
                                    color: .blue
                                )
                            } else if sidelobeB < sidelobeA {
                                DifferenceRow(
                                    text: "Konfiguration B hat \(Int(sidelobeA - sidelobeB)) dB weniger Leckage",
                                    color: .orange
                                )
                            }

                            let lobeA = fftConfig.windowFunction.mainLobeWidth
                            let lobeB = fftConfig.comparisonWindowFunction.mainLobeWidth

                            if lobeA < lobeB {
                                DifferenceRow(
                                    text: "Konfiguration A hat schärfere Peaks",
                                    color: .blue
                                )
                            } else if lobeB < lobeA {
                                DifferenceRow(
                                    text: "Konfiguration B hat schärfere Peaks",
                                    color: .orange
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Helper Views

private struct ExplanationBox: View {
    let title: String
    let text: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.yellow)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(8)
    }
}

private struct StatBox: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CurrentResolutionCard: View {
    @ObservedObject var fftConfig: FFTConfiguration

    var body: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "gauge.with.needle")
                        .foregroundStyle(.purple)
                    Text("Aktuelle Auflösung")
                        .font(.headline)
                    Spacer()
                }

                HStack(spacing: 20) {
                    VStack {
                        Text(String(format: "%.1f", fftConfig.frequencyResolution))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                        Text("Hz (Δf)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()
                        .frame(height: 40)

                    VStack {
                        Text(String(format: "%.0f", fftConfig.timeResolutionMs))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                        Text("ms (Δt)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()
                        .frame(height: 40)

                    VStack {
                        Text("\(fftConfig.binCount)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                        Text("Bins")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct WindowShapeChart: View {
    let windowFunction: WindowFunction

    var body: some View {
        let values = windowFunction.generate(size: 256)
        let data = values.enumerated().map { (index: $0.offset, value: $0.element) }

        Chart(data, id: \.index) { point in
            LineMark(
                x: .value("Sample", point.index),
                y: .value("Amplitude", point.value)
            )
            .foregroundStyle(.blue.gradient)

            AreaMark(
                x: .value("Sample", point.index),
                y: .value("Amplitude", point.value)
            )
            .foregroundStyle(.blue.opacity(0.2))
        }
        .chartYScale(domain: 0...1.1)
        .chartXAxis(.hidden)
    }
}

private struct WindowComparisonTable: View {
    let selectedWindow: WindowFunction

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Fenster")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(width: 100, alignment: .leading)
                Text("Lappen")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(width: 50)
                Text("Seiten")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(width: 50)
                Spacer()
            }
            .padding(.vertical, 4)
            .background(Color(.systemGray6))

            ForEach(WindowFunction.allCases) { window in
                HStack {
                    HStack {
                        if window == selectedWindow {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.caption)
                        }
                        Text(window.localizedName)
                            .font(.caption)
                    }
                    .frame(width: 100, alignment: .leading)

                    Text(String(format: "%.1f×", window.mainLobeWidth))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50)

                    Text("\(Int(window.sidelobeAttenuation))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50)

                    // Visual bar
                    GeometryReader { geo in
                        let normalizedAttenuation = (abs(window.sidelobeAttenuation) - 13) / 80
                        Rectangle()
                            .fill(window == selectedWindow ? .blue : .gray.opacity(0.5))
                            .frame(width: geo.size.width * CGFloat(normalizedAttenuation))
                    }
                    .frame(height: 8)
                }
                .padding(.vertical, 6)
                .background(window == selectedWindow ? Color.blue.opacity(0.1) : Color.clear)
            }
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

private struct HeisenbergVisualization: View {
    let blockSize: FFTBlockSize
    let allSizes: [FFTBlockSize]

    var body: some View {
        GeometryReader { geo in
            let data = allSizes.map { size in
                (
                    size: size,
                    freqRes: 44100.0 / Float(size.rawValue),
                    timeRes: Float(size.rawValue) / 44100.0 * 1000.0
                )
            }

            Chart(data, id: \.size) { point in
                PointMark(
                    x: .value("Δt (ms)", point.timeRes),
                    y: .value("Δf (Hz)", point.freqRes)
                )
                .foregroundStyle(point.size == blockSize ? .blue : .gray.opacity(0.5))
                .symbolSize(point.size == blockSize ? 200 : 100)

                if point.size == blockSize {
                    RuleMark(x: .value("Δt", point.timeRes))
                        .foregroundStyle(.blue.opacity(0.3))
                        .lineStyle(StrokeStyle(dash: [5, 5]))
                    RuleMark(y: .value("Δf", point.freqRes))
                        .foregroundStyle(.blue.opacity(0.3))
                        .lineStyle(StrokeStyle(dash: [5, 5]))
                }
            }
            .chartXAxisLabel("Zeitauflösung (ms)")
            .chartYAxisLabel("Frequenzauflösung (Hz)")
            .chartXScale(type: .log)
            .chartYScale(type: .log)
        }
    }
}

private struct ResolutionRow: View {
    let icon: String
    let label: String
    let value: String
    let detail: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
    }
}

private struct ComparisonSpectrumView: View {
    let configA: (WindowFunction, FFTBlockSize)
    let configB: (WindowFunction, FFTBlockSize)

    var body: some View {
        // Generate synthetic spectrum showing difference in window effects
        // Test tone: 1 kHz at 44100 Hz sample rate

        GeometryReader { geo in
            Canvas { context, size in
                let midY = size.height / 2

                // Draw frequency axis
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: midY))
                        path.addLine(to: CGPoint(x: size.width, y: midY))
                    },
                    with: .color(.gray.opacity(0.3)),
                    lineWidth: 1
                )

                // Draw simulated spectra for both configs
                drawSpectrum(context: context, size: size, config: configA, color: .blue, yOffset: -30)
                drawSpectrum(context: context, size: size, config: configB, color: .orange, yOffset: 30)
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private func drawSpectrum(context: GraphicsContext, size: CGSize, config: (WindowFunction, FFTBlockSize), color: Color, yOffset: CGFloat) {
        let centerX = size.width / 2
        let baseY = size.height / 2 + yOffset

        // Main lobe width based on window
        let lobeWidth = CGFloat(config.0.mainLobeWidth) * 20

        // Side lobe level based on window
        let sidelobeLevel = CGFloat(abs(config.0.sidelobeAttenuation)) / 100.0

        var path = Path()

        // Draw main lobe (Gaussian-ish shape)
        path.move(to: CGPoint(x: centerX - lobeWidth * 2, y: baseY))

        for x in stride(from: -lobeWidth * 2, through: lobeWidth * 2, by: 2) {
            let normalizedX = x / lobeWidth
            let y = exp(-normalizedX * normalizedX * 2) * 60
            path.addLine(to: CGPoint(x: centerX + x, y: baseY - y))
        }

        path.addLine(to: CGPoint(x: centerX + lobeWidth * 2, y: baseY))

        // Draw sidelobes
        let sidelobeHeight = 60 * (1 - sidelobeLevel)
        for offset in [3.0, 4.5, 6.0] {
            let sideX1 = centerX + CGFloat(offset) * lobeWidth
            let sideX2 = centerX - CGFloat(offset) * lobeWidth
            let height = sidelobeHeight / CGFloat(offset)

            path.move(to: CGPoint(x: sideX1 - 5, y: baseY))
            path.addLine(to: CGPoint(x: sideX1, y: baseY - height))
            path.addLine(to: CGPoint(x: sideX1 + 5, y: baseY))

            path.move(to: CGPoint(x: sideX2 - 5, y: baseY))
            path.addLine(to: CGPoint(x: sideX2, y: baseY - height))
            path.addLine(to: CGPoint(x: sideX2 + 5, y: baseY))
        }

        context.stroke(path, with: .color(color), lineWidth: 2)
    }
}

private struct DifferenceRow: View {
    let text: String
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    AdvancedAnalysisView(
        fftConfig: FFTConfiguration(),
        audioEngine: AudioEngine(
            filterManager: BandstopFilterManager(),
            connectivityManager: WatchConnectivityManager()
        )
    )
}
