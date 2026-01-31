import SwiftUI

/// Widget zum A/B-Vergleich verschiedener FFT-Konfigurationen
struct SpectrumComparisonWidget: View {
    @ObservedObject var fftConfig: FFTConfiguration
    @ObservedObject var audioEngine: AudioEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with Toggle
            HStack {
                Image(systemName: "rectangle.split.2x1")
                    .foregroundStyle(fftConfig.comparisonModeEnabled ? .blue : .gray)
                Text("A/B Vergleich")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Toggle("", isOn: $fftConfig.comparisonModeEnabled)
                    .labelsHidden()
                    .controlSize(.mini)
            }

            if fftConfig.comparisonModeEnabled {
                // Configs Side by Side
                HStack(spacing: 8) {
                    // Config A
                    ConfigCardWidget(
                        label: "A",
                        color: .blue,
                        windowName: fftConfig.windowFunction.localizedName,
                        blockSize: fftConfig.blockSize.rawValue,
                        freqRes: fftConfig.frequencyResolution,
                        sidelobe: Int(fftConfig.windowFunction.sidelobeAttenuation)
                    )

                    // Config B
                    ConfigCardEditableWidget(
                        label: "B",
                        color: .orange,
                        windowFunction: $fftConfig.comparisonWindowFunction,
                        blockSize: $fftConfig.comparisonBlockSize
                    )
                }

                // Spectrum Comparison Preview
                ComparisonSpectrumPreviewWidget(
                    configA: (fftConfig.windowFunction, fftConfig.blockSize),
                    configB: (fftConfig.comparisonWindowFunction, fftConfig.comparisonBlockSize)
                )
                .frame(maxHeight: .infinity)

                // Differences
                DifferenceSummaryWidget(
                    windowA: fftConfig.windowFunction,
                    windowB: fftConfig.comparisonWindowFunction,
                    blockA: fftConfig.blockSize,
                    blockB: fftConfig.comparisonBlockSize
                )
            } else {
                // Inactive state
                VStack {
                    Spacer()
                    Image(systemName: "rectangle.split.2x1")
                        .font(.largeTitle)
                        .foregroundStyle(.gray.opacity(0.3))
                    Text("Aktivieren um zwei Konfigurationen zu vergleichen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
    }
}

// MARK: - Helper Views

private struct ConfigCardWidget: View {
    let label: String
    let color: Color
    let windowName: String
    let blockSize: Int
    let freqRes: Float
    let sidelobe: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.caption)
                    .fontWeight(.bold)
            }

            Text(windowName)
                .font(.caption2)
                .lineLimit(1)
            Text("\(blockSize) Samples")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "f = %.1f Hz", freqRes))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

private struct ConfigCardEditableWidget: View {
    let label: String
    let color: Color
    @Binding var windowFunction: WindowFunction
    @Binding var blockSize: FFTBlockSize

    private var freqRes: Float {
        44100.0 / Float(blockSize.rawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.caption)
                    .fontWeight(.bold)
            }

            Menu {
                ForEach(WindowFunction.allCases) { window in
                    Button(window.localizedName) {
                        windowFunction = window
                    }
                }
            } label: {
                Text(windowFunction.localizedName)
                    .font(.caption2)
                    .lineLimit(1)
            }

            Menu {
                ForEach(FFTBlockSize.allCases) { size in
                    Button("\(size.rawValue)") {
                        blockSize = size
                    }
                }
            } label: {
                Text("\(blockSize.rawValue) Samples")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(String(format: "f = %.1f Hz", freqRes))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

private struct ComparisonSpectrumPreviewWidget: View {
    let configA: (WindowFunction, FFTBlockSize)
    let configB: (WindowFunction, FFTBlockSize)

    var body: some View {
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
                drawSpectrum(context: context, size: size, config: configA, color: .blue, yOffset: -15)
                drawSpectrum(context: context, size: size, config: configB, color: .orange, yOffset: 15)
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private func drawSpectrum(context: GraphicsContext, size: CGSize, config: (WindowFunction, FFTBlockSize), color: Color, yOffset: CGFloat) {
        let centerX = size.width / 2
        let baseY = size.height / 2 + yOffset

        // Main lobe width based on window
        let lobeWidth = CGFloat(config.0.mainLobeWidth) * 12

        // Side lobe level based on window
        let sidelobeLevel = CGFloat(abs(config.0.sidelobeAttenuation)) / 100.0

        var path = Path()

        // Draw main lobe (Gaussian-ish shape)
        path.move(to: CGPoint(x: centerX - lobeWidth * 2, y: baseY))

        for x in stride(from: -lobeWidth * 2, through: lobeWidth * 2, by: 2) {
            let normalizedX = x / lobeWidth
            let y = exp(-normalizedX * normalizedX * 2) * 30
            path.addLine(to: CGPoint(x: centerX + x, y: baseY - y))
        }

        path.addLine(to: CGPoint(x: centerX + lobeWidth * 2, y: baseY))

        // Draw sidelobes
        let sidelobeHeight = 30 * (1 - sidelobeLevel)
        for offset in [3.0, 4.5] {
            let sideX1 = centerX + CGFloat(offset) * lobeWidth
            let sideX2 = centerX - CGFloat(offset) * lobeWidth
            let height = sidelobeHeight / CGFloat(offset)

            path.move(to: CGPoint(x: sideX1 - 3, y: baseY))
            path.addLine(to: CGPoint(x: sideX1, y: baseY - height))
            path.addLine(to: CGPoint(x: sideX1 + 3, y: baseY))

            path.move(to: CGPoint(x: sideX2 - 3, y: baseY))
            path.addLine(to: CGPoint(x: sideX2, y: baseY - height))
            path.addLine(to: CGPoint(x: sideX2 + 3, y: baseY))
        }

        context.stroke(path, with: .color(color), lineWidth: 1.5)
    }
}

private struct DifferenceSummaryWidget: View {
    let windowA: WindowFunction
    let windowB: WindowFunction
    let blockA: FFTBlockSize
    let blockB: FFTBlockSize

    var body: some View {
        let sidelobeA = windowA.sidelobeAttenuation
        let sidelobeB = windowB.sidelobeAttenuation
        let lobeA = windowA.mainLobeWidth
        let lobeB = windowB.mainLobeWidth

        HStack(spacing: 8) {
            if sidelobeA < sidelobeB {
                DifferenceChipWidget(text: "A: weniger Leckage", color: .blue)
            } else if sidelobeB < sidelobeA {
                DifferenceChipWidget(text: "B: weniger Leckage", color: .orange)
            }

            if lobeA < lobeB {
                DifferenceChipWidget(text: "A: schärfer", color: .blue)
            } else if lobeB < lobeA {
                DifferenceChipWidget(text: "B: schärfer", color: .orange)
            }
        }
    }
}

private struct DifferenceChipWidget: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}
