import SwiftUI

/// Settings hub — separates measurement from appearance.
struct SettingsRootView: View {
    @Binding var selectedMicrophoneSource: MicrophoneSource
    @Binding var watchGain: Float
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SpectrogramSettingsView(
                            selectedMicrophoneSource: $selectedMicrophoneSource,
                            audioEngine: audioEngine
                        )
                    } label: {
                        Label("Messung & Audio", systemImage: "waveform.badge.mic")
                    }
                    .accessibilityIdentifier("settingsMeasurementLink")

                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label("Darstellung", systemImage: "paintpalette")
                    }
                    .accessibilityIdentifier("settingsAppearanceLink")

                    NavigationLink {
                        WatchAppSettingsView(watchGain: $watchGain)
                    } label: {
                        Label("Apple Watch", systemImage: "applewatch")
                    }
                    .accessibilityIdentifier("settingsWatchLink")
                }
            }
            .polishedFormChrome()
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .accessibilityIdentifier("settingsRootView")
        }
    }
}

struct AppearanceSettingsView: View {
    var body: some View {
        Form {
            DesignTweaksSections()
        }
        .polishedFormChrome()
        .navigationTitle("Darstellung")
        .navigationBarTitleDisplayMode(.inline)
    }
}
