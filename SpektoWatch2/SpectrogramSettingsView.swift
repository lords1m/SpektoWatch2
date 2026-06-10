import SwiftUI
import AVFoundation

struct SpectrogramSettingsView: View {
    @Binding var selectedMicrophoneSource: MicrophoneSource
    @ObservedObject var audioEngine: AudioEngine
    @EnvironmentObject var fftConfiguration: FFTConfiguration

    @Environment(\.dismiss) var dismiss
    @State private var isStereo = false

    var body: some View {
        Form {
                Section(header: Text("Audioquelle")) {
                    Picker("Quelle", selection: $selectedMicrophoneSource) {
                        ForEach(MicrophoneSource.allCases, id: \.self) { source in
                            Label(source.rawValue, systemImage: source == .iPhone ? "iphone" : "applewatch")
                                .tag(source)
                        }
                    }
                    .pickerStyle(.segmented)

                    if selectedMicrophoneSource == .iPhone && !audioEngine.availableDataSources.isEmpty {
                        Picker("Aufnahmemodus", selection: $isStereo) {
                            Text("Mono").tag(false)
                            Text("Stereo").tag(true)
                        }

                        if isStereo {
                            Picker("Stereo-Konfiguration", selection: $audioEngine.selectedStereoMode) {
                                ForEach(StereoInputMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                        } else {
                            Picker("Mikrofon", selection: $audioEngine.selectedDataSource) {
                                ForEach(audioEngine.availableDataSources, id: \.dataSourceID) { source in
                                    Text(source.dataSourceName).tag(source as AVAudioSessionDataSourceDescription?)
                                }
                            }
                        }
                    }
                }

                Section(header: Text("Messung")) {
                    Picker("Zeitbewertung", selection: $audioEngine.timeWeighting) {
                        ForEach(TimeWeighting.allCases, id: \.self) { weighting in
                            Text(weighting.rawValue).tag(weighting)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Frequenzbewertung", selection: $audioEngine.frequencyWeighting) {
                        ForEach(FrequencyWeighting.allCases, id: \.self) { weighting in
                            Text(weighting.rawValue).tag(weighting)
                        }
                    }
                }

                Section(header: Text("Spektrogramm")) {
                    Picker("Auflösung", selection: $audioEngine.spectrogramResolution) {
                        ForEach(SpectrogramResolution.allCases) { resolution in
                            Text(resolution.germanTitle).tag(resolution)
                        }
                    }

                    Text(audioEngine.spectrogramResolution.germanDetail)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Frequenzachse", selection: $audioEngine.spectrogramFrequencyScale) {
                        ForEach(SpectrogramFrequencyScale.allCases) { scale in
                            Text(scale.germanTitle).tag(scale)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(audioEngine.spectrogramFrequencyScale.germanDetail)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Frequenzbereich")
                            Spacer()
                            Text("\(frequencyLabel(audioEngine.spectrogramMinFrequency)) – \(frequencyLabel(audioEngine.spectrogramMaxFrequency))")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Min")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Slider(value: $audioEngine.spectrogramMinFrequency, in: 0...2000, step: 10)
                        }
                        HStack {
                            Text("Max")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Slider(value: $audioEngine.spectrogramMaxFrequency, in: 1000...maxFrequencyCeiling, step: 100)
                        }

                        Button {
                            audioEngine.resetSpectrogramFrequencyRangeToMicrophoneDefault()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Auf Mikrofon-Standard zurücksetzen")
                            }
                            .font(.caption)
                        }
                    }
                }

                Section(header: Text("Kalibrierung: \(Int(audioEngine.calibrationOffset)) dB")) {
                    HStack {
                        Text("80")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $audioEngine.calibrationOffset, in: 80...110, step: 1)
                        Text("110")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("Niedrigerer Wert = niedrigere angezeigte Pegel")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: {
                        audioEngine.resetCalibrationToDeviceDefault()
                    }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Auf Gerätewert zurücksetzen (\(Int(CalibrationProvider.recommendedOffset())) dB)")
                        }
                    }
                }

                Section {
                    Picker("Zeitauflösung (FFT-Blockgröße)", selection: $fftConfiguration.blockSize) {
                        ForEach(FFTBlockSize.allCases) { size in
                            Text(size.shortDescription).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)

                    Menu {
                        ForEach(WindowFunction.allCases) { window in
                            Button {
                                fftConfiguration.windowFunction = window
                            } label: {
                                HStack {
                                    Text(window.localizedName)
                                    if window == fftConfiguration.windowFunction {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Fensterfunktion")
                            Spacer()
                            Text(fftConfiguration.windowFunction.localizedName)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundColor(.secondary)
                        }
                    }
                }

            }
            .polishedFormChrome()
            .navigationTitle("Messung & Audio")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settingsMeasurementView")
        .onAppear {
            audioEngine.checkAvailableInputs()
            // Sync engine to persisted settings on first open
            audioEngine.setWindowFunction(fftConfiguration.windowFunction)
            audioEngine.setBlockSize(fftConfiguration.blockSize)
            audioEngine.scrollSpeed = .closest(to: fftConfiguration.hopSize)
        }
        .onChange(of: fftConfiguration.windowFunction) { _, newValue in
            audioEngine.setWindowFunction(newValue)
        }
        .onChange(of: fftConfiguration.blockSize) { _, newValue in
            audioEngine.setBlockSize(newValue)
            audioEngine.scrollSpeed = .closest(to: fftConfiguration.hopSize)
        }
        .onChange(of: fftConfiguration.overlapPercent) { _, _ in
            audioEngine.scrollSpeed = .closest(to: fftConfiguration.hopSize)
        }
        .onChange(of: isStereo) { _, newValue in
            if newValue {
                audioEngine.applyStereoMode()
            }
        }
    }

    /// Upper bound for the "Max" slider: the smaller of 24 kHz and the device
    /// Nyquist (44.1 kHz mic → ~22.05 kHz). Kept ≥ 2 kHz so the slider is valid.
    private var maxFrequencyCeiling: Double {
        let nyquist = AVAudioSession.sharedInstance().sampleRate / 2.0
        let resolved = nyquist > 1000 ? nyquist : 22_050
        return max(2_000, min(SpectrogramFrequencyRange.absoluteMax, resolved))
    }

    private func frequencyLabel(_ freq: Double) -> String {
        freq >= 1000
            ? String(format: "%.1f kHz", freq / 1000)
            : String(format: "%.0f Hz", freq)
    }
}
