import SwiftUI
import AVFoundation

struct SpectrogramSettingsView: View {
    @Binding var selectedMicrophoneSource: MicrophoneSource
    @Binding var watchGain: Float
    @ObservedObject var audioEngine: AudioEngine
    @EnvironmentObject var fftConfiguration: FFTConfiguration

    @Environment(\.dismiss) var dismiss
    @State private var isStereo = false
    @State private var showAdvancedAnalysis = false

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
                            Text("Auf Gerätewert zurücksetzen (\(Int(AudioEngine.getRecommendedCalibrationOffset())) dB)")
                        }
                    }
                }

                Section(header: Text("Erweiterte Analyse")) {
                    Button {
                        showAdvancedAnalysis = true
                    } label: {
                        HStack {
                            Image(systemName: "waveform.path.ecg.rectangle")
                                .foregroundColor(.purple)
                            VStack(alignment: .leading) {
                                Text("Spektralanalyse-Labor")
                                Text("FFT-Parameter, Fensterfunktionen, Auflösung")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }

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
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            audioEngine.checkAvailableInputs()
        }
        .onChange(of: isStereo) { _, newValue in
            if newValue {
                audioEngine.applyStereoMode()
            }
        }
        .fullScreenCover(isPresented: $showAdvancedAnalysis) {
            NavigationStack {
                AdvancedAnalysisView(fftConfig: fftConfiguration, audioEngine: audioEngine)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fertig") {
                                showAdvancedAnalysis = false
                            }
                        }
                    }
            }
        }
    }
}
