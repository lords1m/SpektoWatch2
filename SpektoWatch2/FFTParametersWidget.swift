import SwiftUI

/// Widget zur Anzeige und Steuerung der FFT-Parameter
struct FFTParametersWidget: View {
    @ObservedObject var fftConfig: FFTConfiguration
    @ObservedObject var audioEngine: AudioEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Block Size
            HStack {
                Image(systemName: "square.grid.3x3")
                    .foregroundStyle(.blue)
                    .font(.caption)
                Text("Block")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(fftConfig.blockSize.rawValue)")
                    .font(.caption)
                    .fontWeight(.semibold)
            }

            Picker("", selection: $fftConfig.blockSize) {
                ForEach(FFTBlockSize.allCases) { size in
                    Text(size.shortDescription).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.mini)

            Divider()

            // Window Function
            HStack {
                Image(systemName: "waveform.path")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text("Fenster")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Divider()

            // Overlap
            HStack {
                Image(systemName: "square.on.square")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Overlap")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(fftConfig.overlapPercent))%")
                    .font(.caption)
                    .fontWeight(.semibold)
            }

            Slider(value: $fftConfig.overlapPercent, in: 0...75, step: 25)
                .controlSize(.mini)

            Spacer()

            // Resolution Summary
            HStack(spacing: 12) {
                VStack {
                    Text(String(format: "%.1f", fftConfig.frequencyResolution))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                    Text("Hz")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider().frame(height: 20)

                VStack {
                    Text(String(format: "%.0f", fftConfig.timeResolutionMs))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.orange)
                    Text("ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider().frame(height: 20)

                VStack {
                    Text("\(fftConfig.binCount)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                    Text("Bins")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
