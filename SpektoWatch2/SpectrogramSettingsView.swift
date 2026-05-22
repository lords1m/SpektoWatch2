import SwiftUI
import AVFoundation

struct SpectrogramSettingsView: View {
    @Binding var selectedMicrophoneSource: MicrophoneSource
    @Binding var watchGain: Float
    @ObservedObject var audioEngine: AudioEngine
    @EnvironmentObject var fftConfiguration: FFTConfiguration

    @Environment(\.dismiss) var dismiss
    @State private var isStereo = false

    var body: some View {
        NavigationView {
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

                if selectedMicrophoneSource == .appleWatch {
                    Section(header: Text("Watch-Verstärkung: \(String(format: "%.1f", watchGain))x")) {
                        HStack {
                            Text("0x")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Slider(value: $watchGain, in: 0...10, step: 0.1)
                            Text("10x")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Frequenzglättung")
                            Spacer()
                            Text(smoothingLabel(audioEngine.spectrogramFrequencySmoothing))
                                .foregroundColor(.secondary)
                        }

                        Slider(value: $audioEngine.spectrogramFrequencySmoothing, in: 0...1, step: 0.05)

                        Text("0 = aus, höher = weichere Frequenzverläufe")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Zeitglättung")
                            Spacer()
                            Text(smoothingLabel(audioEngine.spectrogramTemporalSmoothing))
                                .foregroundColor(.secondary)
                        }

                        Slider(value: $audioEngine.spectrogramTemporalSmoothing, in: 0...1, step: 0.05)

                        Text("0 = aus, 1 = volle IEC-Zeitbewertung")
                            .font(.caption)
                            .foregroundColor(.secondary)
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

                // Design / Anpassen — theme, accent, density, numerals,
                // colormap. Lives directly in the main settings so users
                // don't have to hunt through the accent menu.
                DesignTweaksSections()

                Section(header: Text("Apple Watch")) {
                    NavigationLink(destination: WatchDashboardSettingsView()) {
                        HStack {
                            Image(systemName: "applewatch")
                                .foregroundColor(.blue)
                            Text("Watch-Layout anpassen")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlassBackground())
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
            .accessibilityIdentifier("settingsView")
        }
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

    private func smoothingLabel(_ value: Float) -> String {
        switch value {
        case ..<0.05: return "Aus"
        case ..<0.35: return "Leicht"
        case ..<0.7: return "Mittel"
        default: return "Stark"
        }
    }
}
