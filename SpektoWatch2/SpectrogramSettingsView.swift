import SwiftUI

struct SpectrogramSettingsView: View {
    @Binding var selectedMicrophoneSource: MicrophoneSource
    @Binding var selectedColormap: Int
    @Binding var sensitivity: Double
    @Binding var timeWeighting: TimeWeighting
    @Binding var frequencyWeighting: FrequencyWeighting
    @Binding var timeSpan: SpectrogramTimeSpan
    @Binding var scrollSpeed: ScrollSpeed
    @Binding var watchGain: Float
    
    @Environment(\.dismiss) var dismiss

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
                
                Section(header: Text("Darstellung")) {
                    Picker("Farbschema", selection: $selectedColormap) {
                        Text("Turbo").tag(0)
                        Text("Jet").tag(1)
                        Text("Viridis").tag(2)
                    }
                    .pickerStyle(.segmented)
                    
                    Picker("Zeitbereich", selection: $timeSpan) {
                        ForEach(SpectrogramTimeSpan.allCases) { span in
                            Text(span.title).tag(span)
                        }
                    }
                    
                    Picker("Geschwindigkeit", selection: $scrollSpeed) {
                        ForEach(ScrollSpeed.allCases, id: \.self) { speed in
                            Text(speed.label).tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section(header: Text("Sensitivität: \(Int(sensitivity)) dB")) {
                    HStack {
                        Text("0 dB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $sensitivity, in: 0...60, step: 1)
                        Text("60 dB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Messung")) {
                    Picker("Zeitbewertung", selection: $timeWeighting) {
                        ForEach(TimeWeighting.allCases, id: \.self) { weighting in
                            Text(weighting.rawValue).tag(weighting)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Picker("Frequenzbewertung", selection: $frequencyWeighting) {
                        ForEach(FrequencyWeighting.allCases, id: \.self) { weighting in
                            Text(weighting.rawValue).tag(weighting)
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
    }
}