import SwiftUI

/// Watch-side policy for live measurement routing (auto / iPhone / watch mic).
struct WatchMeasurementSourceSettingsView: View {
    @EnvironmentObject private var audioEngine: WatchAudioEngine
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager

    var body: some View {
        List {
            Section {
                Picker("Messquelle", selection: preferenceBinding) {
                    if !WatchAudioEngine.isWatchOnlyApp {
                        Text(WatchMeasurementSourcePreference.auto.displayName)
                            .tag(WatchMeasurementSourcePreference.auto)
                        Text(WatchMeasurementSourcePreference.iPhone.displayName)
                            .tag(WatchMeasurementSourcePreference.iPhone)
                    }
                    Text(WatchMeasurementSourcePreference.appleWatch.displayName)
                        .tag(WatchMeasurementSourcePreference.appleWatch)
                }
                .pickerStyle(.inline)
                .disabled(audioEngine.isRecording)
            } footer: {
                Text(footerText)
            }

            Section("Aktuell") {
                HStack {
                    WatchMeasurementSourceIndicator()
                    Spacer()
                    statusCaption
                }
            }
        }
        .navigationTitle("Messquelle")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("watchMeasurementSourceSettingsView")
    }

    private var preferenceBinding: Binding<WatchMeasurementSourcePreference> {
        Binding(
            get: { audioEngine.measurementSourcePreference },
            set: { audioEngine.setMeasurementSourcePreference($0) }
        )
    }

    private var footerText: String {
        if WatchAudioEngine.isWatchOnlyApp {
            return "Diese App nutzt immer das Apple Watch Mikrofon."
        }
        switch audioEngine.measurementSourcePreference {
        case .auto:
            return "Automatisch: solange das iPhone misst und erreichbar ist, werden die Werte gespiegelt. Sonst misst die Watch selbst."
        case .iPhone:
            return "Live-Werte kommen vom iPhone. Aufnahmen auf der Watch koordinieren mit der iPhone-App."
        case .appleWatch:
            return "Live-Werte und Aufnahmen kommen vom Apple Watch Mikrofon."
        }
    }

    @ViewBuilder
    private var statusCaption: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if connectivityManager.isReachable {
                Label("iPhone erreichbar", systemImage: "link")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Label("iPhone nicht erreichbar", systemImage: "link.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if connectivityManager.phoneAppState?.isRecording == true {
                Label("iPhone misst", systemImage: "record.circle")
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.85))
            }
        }
    }
}
