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

        var icon: String {
            switch self {
            case .parameters: return "slider.horizontal.3"
            case .window: return "waveform.path"
            case .resolution: return "atom"
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

            // Overlap — only 4 discrete positions (0/25/50/75 %); use a
            // segmented picker so the UI matches the actual discrete values.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "square.on.square")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Overlap")
                        .font(.caption)
                        .fontWeight(.medium)
                }

                Picker("Overlap", selection: Binding(
                    get: {
                        // Snap to nearest valid option — default is 87.5 % which
                        // falls outside the picker range, so it maps to 75 %.
                        let v = fftConfig.overlapPercent
                        let valid: [Float] = [0, 25, 50, 75]
                        return Int(valid.min(by: { abs($0 - v) < abs($1 - v) }) ?? 75)
                    },
                    set: { fftConfig.overlapPercent = Float($0) }
                )) {
                    Text("0%").tag(0)
                    Text("25%").tag(25)
                    Text("50%").tag(50)
                    Text("75%").tag(75)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            // Resolution Summary
            HStack(spacing: 16) {
                ResolutionBadge(value: String(format: "%.1f", fftConfig.frequencyResolution), unit: "Hz", label: "Δf", color: .blue)
                ResolutionBadge(value: String(format: "%.0f", fftConfig.timeResolutionMs), unit: "ms", label: "Δt", color: .orange)
                ResolutionBadge(value: "\(fftConfig.binCount)", unit: "", label: "Bins", color: .green)
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Reset to defaults
            Button {
                fftConfig.windowFunction = .blackmanHarris
                fftConfig.blockSize = .size2048
                fftConfig.overlapPercent = 75.0
                audioEngine.setWindowFunction(.blackmanHarris)
                audioEngine.setBlockSize(.size2048)
            } label: {
                Label("Zurücksetzen", systemImage: "arrow.uturn.backward")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
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

