import SwiftUI
import Charts

/// Kombiniertes Spektralanalyse-Labor Widget
/// Vereint FFT-Parameter, Fensterfunktion, Heisenberg-Visualisierung und A/B-Vergleich
struct SpektralanalyseLaborWidget: View {
    @ObservedObject var fftConfig: FFTConfiguration
    @ObservedObject var audioEngine: AudioEngine

    @State private var selectedTab: LabTab = .parameters

    enum LabTab: String, CaseIterable {
        case parameters = "Parameter"
        case window = "Fenster"
        case resolution = "Auflösung"
        case comparison = "Vergleich"

        var icon: String {
            switch self {
            case .parameters: return "slider.horizontal.3"
            case .window: return "waveform.path"
            case .resolution: return "atom"
            case .comparison: return "rectangle.split.2x1"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar
            HStack(spacing: 0) {
                ForEach(LabTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14))
                            Text(tab.rawValue)
                                .font(.system(size: 9))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundColor(selectedTab == tab ? .blue : .gray)
                        .background(selectedTab == tab ? Color.blue.opacity(0.1) : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(.systemGray6))

            // Content
            ScrollView {
                switch selectedTab {
                case .parameters:
                    ParametersTabView(fftConfig: fftConfig, audioEngine: audioEngine)
                case .window:
                    WindowTabView(fftConfig: fftConfig)
                case .resolution:
                    ResolutionTabView(fftConfig: fftConfig)
                case .comparison:
                    ComparisonTabView(fftConfig: fftConfig)
                }
            }
        }
    }
}

// MARK: - Parameters Tab

private struct ParametersTabView: View {
    @ObservedObject var fftConfig: FFTConfiguration
    @ObservedObject var audioEngine: AudioEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Block Size
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "square.grid.3x3")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text("Blockgröße")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(fftConfig.blockSize.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("", selection: $fftConfig.blockSize) {
                    ForEach(FFTBlockSize.allCases) { size in
                        Text(size.shortDescription).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
            }

            Divider()

            // Window Function
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "waveform.path")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("Fensterfunktion")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                }

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
                            .font(.caption)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Overlap
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "square.on.square")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Overlap")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(Int(fftConfig.overlapPercent))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Slider(value: $fftConfig.overlapPercent, in: 0...75, step: 25)
                    .tint(.orange)
            }

            Divider()

            // Resolution Summary
            HStack(spacing: 16) {
                ResolutionBadge(value: String(format: "%.1f", fftConfig.frequencyResolution), unit: "Hz", label: "Δf", color: .blue)
                ResolutionBadge(value: String(format: "%.0f", fftConfig.timeResolutionMs), unit: "ms", label: "Δt", color: .orange)
                ResolutionBadge(value: "\(fftConfig.binCount)", unit: "", label: "Bins", color: .green)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .onChange(of: fftConfig.windowFunction) { _, newValue in
            audioEngine.setWindowFunction(newValue)
        }
        .onChange(of: fftConfig.blockSize) { _, newValue in
            audioEngine.setBlockSize(newValue)
        }
    }
}

// MARK: - Window Tab

private struct WindowTabView: View {
    @ObservedObject var fftConfig: FFTConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Window Shape Chart
            VStack(alignment: .leading, spacing: 6) {
                Text(fftConfig.windowFunction.localizedName)
                    .font(.caption)
                    .fontWeight(.medium)

                WindowShapeChart(windowFunction: fftConfig.windowFunction)
                    .frame(height: 80)
            }

            // Stats
            HStack(spacing: 12) {
                StatBadge(label: "Hauptlappen", value: String(format: "%.1f×", fftConfig.windowFunction.mainLobeWidth), color: .blue)
                StatBadge(label: "Seitenlappen", value: "\(Int(fftConfig.windowFunction.sidelobeAttenuation)) dB", color: .orange)
                StatBadge(label: "Gain", value: String(format: "%.2f", fftConfig.windowFunction.coherentGain), color: .green)
            }

            Divider()

            // Description
            Text(fftConfig.windowFunction.description)
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Quick selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(WindowFunction.allCases) { window in
                        Button {
                            fftConfig.windowFunction = window
                        } label: {
                            Text(window.localizedName)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(window == fftConfig.windowFunction ? Color.green : Color(.systemGray5))
                                .foregroundColor(window == fftConfig.windowFunction ? .white : .primary)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
    }
}

// MARK: - Resolution Tab

private struct ResolutionTabView: View {
    @ObservedObject var fftConfig: FFTConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Heisenberg Chart
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "atom")
                        .foregroundStyle(.purple)
                    Text("Zeit-Frequenz-Unsicherheit")
                        .font(.caption)
                        .fontWeight(.medium)
                }

                HeisenbergChart(blockSize: fftConfig.blockSize, allSizes: FFTBlockSize.allCases)
                    .frame(height: 120)
            }

            Divider()

            // Current Resolution
            VStack(spacing: 8) {
                ResolutionRow(icon: "waveform", label: "Frequenzauflösung", value: String(format: "%.2f Hz", fftConfig.frequencyResolution), color: .blue)
                ResolutionRow(icon: "clock", label: "Zeitauflösung", value: String(format: "%.1f ms", fftConfig.timeResolutionMs), color: .orange)
                ResolutionRow(icon: "number", label: "Frequenzbins", value: "\(fftConfig.binCount)", color: .green)
            }
        }
        .padding(12)
    }
}

// MARK: - Comparison Tab

private struct ComparisonTabView: View {
    @ObservedObject var fftConfig: FFTConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Toggle
            Toggle(isOn: $fftConfig.comparisonModeEnabled) {
                HStack {
                    Image(systemName: "rectangle.split.2x1")
                        .foregroundStyle(fftConfig.comparisonModeEnabled ? .blue : .gray)
                    Text("A/B Vergleich")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if fftConfig.comparisonModeEnabled {
                HStack(spacing: 8) {
                    // Config A
                    ConfigCard(
                        label: "A",
                        color: .blue,
                        windowName: fftConfig.windowFunction.localizedName,
                        blockSize: fftConfig.blockSize.rawValue,
                        freqRes: fftConfig.frequencyResolution
                    )

                    // Config B (editable)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Circle().fill(.orange).frame(width: 8, height: 8)
                            Text("B").font(.caption).fontWeight(.bold)
                        }

                        Menu {
                            ForEach(WindowFunction.allCases) { window in
                                Button(window.localizedName) {
                                    fftConfig.comparisonWindowFunction = window
                                }
                            }
                        } label: {
                            Text(fftConfig.comparisonWindowFunction.localizedName)
                                .font(.caption2)
                        }

                        Menu {
                            ForEach(FFTBlockSize.allCases) { size in
                                Button("\(size.rawValue)") {
                                    fftConfig.comparisonBlockSize = size
                                }
                            }
                        } label: {
                            Text("\(fftConfig.comparisonBlockSize.rawValue)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        let freqResB = 44100.0 / Float(fftConfig.comparisonBlockSize.rawValue)
                        Text(String(format: "Δf = %.1f Hz", freqResB))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }

                // Differences
                DifferenceSummary(
                    windowA: fftConfig.windowFunction,
                    windowB: fftConfig.comparisonWindowFunction
                )
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "rectangle.split.2x1")
                        .font(.title)
                        .foregroundStyle(.gray.opacity(0.3))
                    Text("Aktivieren für A/B Vergleich")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            }
        }
        .padding(12)
    }
}

// MARK: - Helper Views

private struct ResolutionBadge: View {
    let value: String
    let unit: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

private struct StatBadge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WindowShapeChart: View {
    let windowFunction: WindowFunction

    var body: some View {
        let values = windowFunction.generate(size: 128)
        let data = values.enumerated().map { (index: $0.offset, value: $0.element) }

        Chart(data, id: \.index) { point in
            LineMark(
                x: .value("Sample", point.index),
                y: .value("Amplitude", point.value)
            )
            .foregroundStyle(.green.gradient)

            AreaMark(
                x: .value("Sample", point.index),
                y: .value("Amplitude", point.value)
            )
            .foregroundStyle(.green.opacity(0.2))
        }
        .chartYScale(domain: 0...1.1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

private struct HeisenbergChart: View {
    let blockSize: FFTBlockSize
    let allSizes: [FFTBlockSize]

    var body: some View {
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
            .foregroundStyle(point.size == blockSize ? .purple : .gray.opacity(0.4))
            .symbolSize(point.size == blockSize ? 120 : 50)

            if point.size == blockSize {
                RuleMark(x: .value("Δt", point.timeRes))
                    .foregroundStyle(.purple.opacity(0.3))
                    .lineStyle(StrokeStyle(dash: [4, 4]))
                RuleMark(y: .value("Δf", point.freqRes))
                    .foregroundStyle(.purple.opacity(0.3))
                    .lineStyle(StrokeStyle(dash: [4, 4]))
            }
        }
        .chartXScale(type: .log)
        .chartYScale(type: .log)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
    }
}

private struct ResolutionRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption)
                .frame(width: 20)
            Text(label)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

private struct ConfigCard: View {
    let label: String
    let color: Color
    let windowName: String
    let blockSize: Int
    let freqRes: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).font(.caption).fontWeight(.bold)
            }
            Text(windowName)
                .font(.caption2)
            Text("\(blockSize) Samples")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "Δf = %.1f Hz", freqRes))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

private struct DifferenceSummary: View {
    let windowA: WindowFunction
    let windowB: WindowFunction

    var body: some View {
        let sidelobeA = windowA.sidelobeAttenuation
        let sidelobeB = windowB.sidelobeAttenuation
        let lobeA = windowA.mainLobeWidth
        let lobeB = windowB.mainLobeWidth

        HStack(spacing: 8) {
            if sidelobeA < sidelobeB {
                DifferenceChip(text: "A: weniger Leckage", color: .blue)
            } else if sidelobeB < sidelobeA {
                DifferenceChip(text: "B: weniger Leckage", color: .orange)
            }

            if lobeA < lobeB {
                DifferenceChip(text: "A: schärfer", color: .blue)
            } else if lobeB < lobeA {
                DifferenceChip(text: "B: schärfer", color: .orange)
            }
        }
    }
}

private struct DifferenceChip: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}
