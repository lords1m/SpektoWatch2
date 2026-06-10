import SwiftUI
import Combine

/// Dashboard-level options (e.g. Pegel tile orientation on the watch home grid).
struct WatchDashboardLayoutSettingsView: View {
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager
    @State private var config = WatchDashboardConfig.load()

    private var levelMeterWidget: WatchWidgetConfig? {
        config.orderedDisplayWidgets.first { $0.type == .levelMeter }
    }

    var body: some View {
        List {
            if let meter = levelMeterWidget {
                Section {
                    Picker("Ausrichtung", selection: orientationBinding(for: meter)) {
                        ForEach(LevelMeterOrientation.allCases) { orientation in
                            Text(orientation.displayName).tag(orientation)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Pegel auf dem Dashboard")
                } footer: {
                    Text("Horizontal: schmale Leiste über zwei Spalten. Vertikal: höhere Kachel mit Balken nach oben.")
                }
            } else {
                Section {
                    Text("Kein Pegel-Widget im Dashboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Dashboard-Pegel")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let received = connectivityManager.watchDashboardConfig {
                config = received
            }
        }
        .onReceive(connectivityManager.$watchDashboardConfig.compactMap { $0 }) { newConfig in
            config = newConfig
        }
    }

    private func orientationBinding(for meter: WatchWidgetConfig) -> Binding<LevelMeterOrientation> {
        Binding(
            get: { meter.resolvedLevelMeterOrientation() },
            set: { newOrientation in
                guard let index = config.widgets.firstIndex(where: { $0.id == meter.id }) else { return }
                config.widgets[index].levelMeterOrientation = newOrientation
                config.version += 1
                config.save()
                connectivityManager.sendWatchDashboardConfig(config)
            }
        )
    }
}
